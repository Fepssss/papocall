#include "flutter_rnnoise.h"

#include <atomic>

#include "rnnoise.h"
#include "rtc_audio_processing.h"

namespace flutter_webrtc_plugin {
namespace {

constexpr int kQuadroRnnoise = 480;  // FRAME_SIZE do modelo: 10 ms a 48 kHz
constexpr int kTaxaAlvo = 48000;
constexpr int kRazaoMaxima = 6;      // 8 kHz é o chão aceitável (8000 * 6 = 48000)

// Filtra um quadro de captura pelo modelo do Xiph sem sair da thread de áudio.
//
// O caminho nativo entrega 160 floats a 16 kHz (medido com a sonda), e o RNNoise
// só conhece 480 amostras a 48 kHz — daí o esticar e o enxugar abaixo. Nada aqui
// aloca, abre arquivo ou chama o Dart: um atraso deste callback é silêncio no
// microfone de todo mundo na sala.
class RnnoiseFiltro : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  void Initialize(int sample_rate_hz, int num_channels) override {
    canais_ = num_channels;
    razao_ = calcularRazao(sample_rate_hz, num_channels);
    tem_anterior_ = false;
    amostra_anterior_ = 0.0f;
    // O modelo já vem aberto na instalação; isto só cobre quem instalar o
    // filtro antes de abrir o APM, em que Initialize chega primeiro.
    abrirModelo();
    if (!modelo_aberto_) ativo_.store(false);
  }

  void Process(int num_bands, int num_frames, int buffer_size, float* buffer) override {
    (void)num_bands;
    (void)buffer_size;
    if (!ativo_.load(std::memory_order_relaxed)) return;
    if (!estado_ || razao_ <= 0) return;
    if (num_frames <= 0 || num_frames * razao_ != kQuadroRnnoise) return;

    // O quadro chega na escala de short — pico medido em 31073 num volume de
    // fala normal — que é justamente a escala que o modelo espera. Não há
    // conversão de propósito: multiplicar por 32768 "porque o WebRTC entrega em
    // ±1", como diz a documentação, entregaria o microfone ceifado.
    float anterior = tem_anterior_ ? amostra_anterior_ : buffer[0];
    int pos = 0;
    for (int i = 0; i < num_frames; ++i) {
      const float atual = buffer[i];
      const float degrau = (atual - anterior) / razao_;
      for (int k = 0; k < razao_; ++k) quadro_[pos++] = anterior + degrau * (k + 1);
      anterior = atual;
    }
    amostra_anterior_ = anterior;
    tem_anterior_ = true;

    rnnoise_process_frame(estado_, filtrado_, quadro_);

    // Enxugar somando as `razao_` amostras do quadro filtrado: sem essa média, o
    // que o modelo regenerou acima de Nyquist voltaria dobrado sobre a fala como
    // chiado.
    for (int i = 0; i < num_frames; ++i) {
      const int base = i * razao_;
      double soma = 0.0;
      for (int k = 0; k < razao_; ++k) soma += filtrado_[base + k];
      buffer[i] = static_cast<float>(soma / razao_);
    }
  }

  void Reset(int new_rate) override {
    // Chamado quando a captura muda de taxa no meio da chamada. O estado do
    // modelo sobrevive: ele sempre trabalha a 48 kHz, o que muda é só a razão.
    razao_ = calcularRazao(new_rate, canais_);
    tem_anterior_ = false;
    amostra_anterior_ = 0.0f;
  }

  void Release() override {
    // O estado vive enquanto o processo vive. Destruir aqui não teria onde ser
    // recriado com garantia — o adapter do libwebrtc não avisa antes de o APM
    // morrer — e o custo é fixo, de algumas centenas de kilobytes, não
    // crescente.
  }

  void definirAtivo(bool valor) { ativo_.store(valor, std::memory_order_relaxed); }
  bool ativo() const { return ativo_.load(std::memory_order_relaxed); }
  bool modeloAberto() const { return modelo_aberto_; }

  // Abre o modelo agora, na thread de quem instala, para que a instalação possa
  // responder com verdade se o RNNoise está disponível — em vez de deixar isso
  // para o primeiro quadro de áudio, quando já seria tarde para avisar.
  void abrirModelo() {
    if (!estado_) estado_ = rnnoise_create(nullptr);
    modelo_aberto_ = estado_ != nullptr;
  }

 private:
  static int calcularRazao(int sample_rate_hz, int num_channels) {
    // O APM só entrega o canal 0 no quadro, então uma captura estéreo sairia com
    // um ouvido filtrado e o outro não: sem filtro é melhor que meio filtro.
    if (num_channels != 1) return 0;
    if (sample_rate_hz <= 0 || kTaxaAlvo % sample_rate_hz != 0) return 0;
    const int razao = kTaxaAlvo / sample_rate_hz;
    return (razao >= 1 && razao <= kRazaoMaxima) ? razao : 0;
  }

  std::atomic<bool> ativo_{false};
  bool modelo_aberto_ = false;
  int razao_ = 0;
  int canais_ = 1;
  bool tem_anterior_ = false;
  float amostra_anterior_ = 0.0f;
  float quadro_[kQuadroRnnoise];
  float filtrado_[kQuadroRnnoise];
  DenoiseState* estado_ = nullptr;
};

// O adaptador do libwebrtc guarda só o ponteiro e nunca destrói: um exemplar por
// processo é o único tamanho seguro aqui, igual à sonda.
RnnoiseFiltro* g_filtro = nullptr;

}  // namespace

bool InstalarRnnoise(libwebrtc::RTCAudioProcessing* processing) {
  if (!processing) return false;
  if (!g_filtro) g_filtro = new RnnoiseFiltro();
  // O modelo abre aqui, na thread da plataforma. O Initialize que o adaptador
  // faz na thread de áudio pode nem chegar a ocorrer se a captura não reiniciar.
  g_filtro->abrirModelo();
  processing->SetCapturePostProcessing(g_filtro);
  return g_filtro->modeloAberto();
}

void DefinirRnnoiseAtivo(bool ativo) {
  if (!g_filtro) return;
  if (!g_filtro->modeloAberto()) return;
  g_filtro->definirAtivo(ativo);
}

bool RnnoiseDisponivel() { return g_filtro != nullptr && g_filtro->modeloAberto(); }

}  // namespace flutter_webrtc_plugin
