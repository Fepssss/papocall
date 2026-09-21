# PapoCall

<p align="center">
  <img src="public/logo.png" alt="PapoCall Logo" width="120" />
</p>

<p align="center">
  <strong>Aplicativo Desktop Nativo para Windows de Comunicação em Tempo Real</strong><br>
  Voz de ultra-baixa latência, compartilhamento de tela com economia de GPU, chat MQTT e estética HUD militar sóbria.
</p>

<p align="center">
  <a href="https://github.com/Fepssss/papocall/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-Windows%2064--bit-blue.svg" alt="Platform: Windows">
  <img src="https://img.shields.io/badge/version-1.0.0d-brightgreen.svg" alt="Version 1.0.0d">
  <a href="https://papocall.vercel.app"><img src="https://img.shields.io/badge/website-papocall.vercel.app-22C55E.svg" alt="Website"></a>
</p>

---

## 🎯 Sobre o PapoCall

O **PapoCall** é uma aplicação desktop nativa desenvolvida em **Flutter 3.x** para Windows, projetada para entregar a melhor experiência de comunicação por voz, vídeo e texto para squads de jogos e comunidades táticas.

Diferente de aplicativos baseados em navegadores pesados ou frameworks WebView2, o PapoCall é compilado 100% nativamente em código de máquina, consumindo uma fração de memória RAM e GPU.

---

## ⚡ Principais Funcionalidades

- 🎙️ **Voz RTC de Ultra-Baixa Latência**: Motor baseado em WebRTC via **LiveKit Cloud** com codec Opus 48kHz HD (latência inferior a 35ms).
- 🖥️ **Modo Eco para Streamers**: Suspensão inteligente da renderização local da própria live quando a janela é minimizada ou perde o foco, poupando GPU para o jogo enquanto os espectadores assistem fluidamente.
- 📡 **Mensageria Dupla Resiliente**: Chat em tempo real via broker **EMQX MQTT** com conexão prioritária TCP nativa (porta 1883) e fallback transparente para WebSocket seguro (WSS porta 8084).
- 🏰 **Criação e Gestão de Servidores**: Crie seus próprios servidores com templates para Jogos, Comunidade ou Estudo, geração de códigos de convite e persistência em disco.
- 🎛️ **Central de Comando (Home Page)**: Visualização em tela cheia com acesso de 1 clique às salas de voz mais ativas, radar de squad de amigos conectados e diagnósticos ao vivo de hardware.
- 🛡️ **Segurança e Confiabilidade**: Proteção contra colisão de identidade (`DUPLICATE_IDENTITY`) e total separação de credenciais.

---

## 💻 Requisitos do Sistema

- **Sistema Operacional**: Windows 10 (versão 1903+) ou Windows 11 (64-bit).
- **Processador**: Intel Core i3 / AMD Ryzen 3 ou superior.
- **Memória RAM**: 4 GB (uso médio de ~90 MB).
- **Conexão**: Banda larga para conferências WebRTC.

---

## 📥 Download e Instalação

Você pode baixar a versão mais recente diretamente do site oficial:
👉 **[https://papocall.vercel.app](https://papocall.vercel.app)**

Ou baixar diretamente o instalador oficial:
- **[PapoCall-Setup.exe](https://papocall.vercel.app/downloads/PapoCall-Setup.exe)**

---

## 🛠️ Como Compilar a Partir do Código Fonte

### Pré-requisitos
- [Flutter SDK](https://flutter.dev) (3.13+) com suporte para Windows Desktop habilitado.
- [Visual Studio 2022](https://visualstudio.microsoft.com/) com a carga de trabalho "Desenvolvimento para desktop com C++".
- [Inno Setup 6](https://jrsoftware.org/isdl.php) (para compilar o instalador).

### Passos de Compilação

1. Clone o repositório:
   ```bash
   git clone https://github.com/Fepssss/papocall.git
   cd papocall
   ```

2. Instale as dependências:
   ```bash
   cd flutter_app
   flutter pub get
   ```

3. Execute em modo de desenvolvimento:
   ```bash
   flutter run -d windows
   ```

4. Para gerar o instalador de produção:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File installer/build_installer.ps1
   ```

---

## 🧪 Testes

Os três checks abaixo rodam em todo PR e são **obrigatórios** na `main`: PR com
qualquer um vermelho não entra sem que alguém passe por cima de propósito
(`gh pr merge --admin`, ou o botão correspondente na interface).

O `enforce_admins` está desligado de caso pensado: com ele ligado, o GitHub
passou a rejeitar também o **push direto** na `main` — e é por ali que o
instalador é publicado. Ligar de volta é um comando, se um dia o fluxo passar a
ser todo por PR.

```bash
# Aplicativo (analyze + widgets + criptografia do chat e dos servidores)
cd flutter_app
flutter pub get
flutter analyze
flutter test

# Backend (autenticação completa contra um Postgres descartável)
cd backend
docker compose -f docker-compose.test.yml up -d
export DATABASE_URL="postgresql://papocall:papocall@localhost:5433/papocall_test?schema=public"
export TEST_DATABASE_URL="$DATABASE_URL"
npm ci && npx prisma generate && npx prisma db push
npm test
```

As duas exportações não são decoração: sem elas o `prisma db push` lê o `.env`
local, que aponta para o Neon, e aplica o schema no banco operacional. No
PowerShell, troque `export X=...` por `$env:X = "..."`.

O passo a passo do backend, com as variáveis que precisam ser exportadas e o
motivo histórico de nunca rodar a suíte contra o banco de produção, está em
[`backend/README.md`](backend/README.md). Os workflows correspondentes estão em
[`.github/workflows/`](.github/workflows), e o Dependabot em
[`.github/dependabot.yml`](.github/dependabot.yml).

---

## 📜 Licença

Este projeto está licenciado sob os termos da licença [MIT](LICENSE).
