#include "flutter_audio_probe.h"

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>

#include "rtc_audio_processing.h"

namespace flutter_webrtc_plugin {
namespace {

// Os três arquivos vivem no diretório temporário do usuário. A marca é o
// interruptor: sem ela nada é instalado, e sem instalar nada o caminho de áudio
// continua exatamente como veio do pub.
constexpr char kNomeDaMarca[] = "papocall_audio_probe.on";
constexpr char kNomeDoDespejo[] = "papocall_audio_probe.f32";
constexpr char kNomeDoResumo[] = "papocall_audio_probe.txt";

// Um quadro são 10 ms, então 500 quadros são 5 segundos de conversa.
constexpr long long kQuadrosPorResumo = 500;

// Caminho largo, não texto: o diretório temporário costuma levar o nome de
// quem logou, e esse nome pode ter acento.
std::filesystem::path caminhoDaTemporada(const char* nome) {
  std::error_code ec;
  const std::filesystem::path pasta = std::filesystem::temp_directory_path(ec);
  if (ec) return std::filesystem::path(nome);
  return pasta / nome;
}

bool marcaExiste() {
  std::ifstream marca(caminhoDaTemporada(kNomeDaMarca));
  return marca.good();
}

// Passa o áudio adiante sem tocar nele e mede o que chega.
class AudioProbe : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  void Initialize(int sample_rate_hz, int num_channels) override {
    taxa_hz_ = sample_rate_hz;
    canais_ = num_channels;
    quadros_ = 0;
    somados_us_ = 0;
    pior_us_ = 0;
    pico_ = 0.0f;
    trocas_de_taxa_ = 0;
    despejo_.open(caminhoDaTemporada(kNomeDoDespejo), std::ios::binary | std::ios::trunc);
    escreverResumo();
  }

  void Process(int num_bands, int num_frames, int buffer_size, float* buffer) override {
    if (!despejo_.is_open() || num_frames <= 0) return;

    const auto inicio = std::chrono::steady_clock::now();

    float pico = 0.0f;
    for (int i = 0; i < num_frames; ++i) {
      const float valor = buffer[i] < 0.0f ? -buffer[i] : buffer[i];
      if (valor > pico) pico = valor;
    }
    despejo_.write(reinterpret_cast<const char*>(buffer),
                   static_cast<std::streamsize>(num_frames) * static_cast<std::streamsize>(sizeof(float)));

    const auto fim = std::chrono::steady_clock::now();
    const long long deste =
        std::chrono::duration_cast<std::chrono::microseconds>(fim - inicio).count();
    somados_us_ += deste;
    if (deste > pior_us_) pior_us_ = deste;

    ++quadros_;
    if (pico > pico_) pico_ = pico;
    num_bands_ = num_bands;
    tamanho_buffer_ = buffer_size;

    if (quadros_ % kQuadrosPorResumo == 0) {
      despejo_.flush();
      escreverResumo();
    }
  }

  void Reset(int new_rate) override {
    ++trocas_de_taxa_;
    taxa_hz_ = new_rate;
  }

  void Release() override {
    if (!despejo_.is_open()) return;
    despejo_.flush();
    despejo_.close();
    escreverResumo();
  }

 private:
  // Reescrito a cada 5 s para dar para ler com o aplicativo no ar: quem mede
  // uma chamada não tem como garantir um Release() no fim dela.
  void escreverResumo() {
    std::ofstream resumo(caminhoDaTemporada(kNomeDoResumo));
    if (!resumo) return;
    const long long media = quadros_ ? somados_us_ / quadros_ : 0;
    char linha[256];
    std::snprintf(linha, sizeof(linha),
                  "taxa_hz=%d\ncanais=%d\nnum_bands=%d\nbuffer_size=%d\n"
                  "quadros=%lld\ntrocas_de_taxa=%d\npico=%.6f\n"
                  "media_us_por_quadro=%lld\npior_us_por_quadro=%lld\n"
                  "audio_segundos=%.2f\n",
                  taxa_hz_, canais_, num_bands_, tamanho_buffer_, quadros_,
                  trocas_de_taxa_, static_cast<double>(pico_), media, pior_us_,
                  static_cast<double>(quadros_) / 100.0);
    resumo << linha;
  }

  std::ofstream despejo_;
  int taxa_hz_ = 0;
  int canais_ = 0;
  int num_bands_ = 0;
  int tamanho_buffer_ = 0;
  long long quadros_ = 0;
  long long somados_us_ = 0;
  long long pior_us_ = 0;
  int trocas_de_taxa_ = 0;
  float pico_ = 0.0f;
};

// Quem guarda a referência é o adaptador do libwebrtc, e ele só conhece o
// ponteiro: não destrói, e não avisa antes de o APM morrer. Viver enquanto o
// processo vive é o único tamanho seguro aqui.
AudioProbe* g_sonda = nullptr;

}  // namespace

void MaybeInstallAudioProbe(libwebrtc::RTCAudioProcessing* processing) {
  if (!processing || !marcaExiste()) return;
  if (!g_sonda) g_sonda = new AudioProbe();
  processing->SetCapturePostProcessing(g_sonda);
}

}  // namespace flutter_webrtc_plugin
