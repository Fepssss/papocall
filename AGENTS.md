# PapoCall - Diretrizes e Contexto para Antigravity IDE

Este arquivo é lido automaticamente pelo Antigravity IDE para orientar o agente em todas as tarefas, garantindo consistência com a arquitetura, regras de negócio e padrões técnicos do PapoCall.

---

## 1. Regras Obrigatórias e Imutáveis

1. **Idioma**: Sempre responder, documentar e interagir em **Português do Brasil (pt-BR)**.
2. **Nome do Projeto**: O aplicativo chama-se estritamente **PapoCall**. Nunca utilize termos legados (como *projetous*) e não faça referências a concorrentes (como *Discord*).
3. **Padrão de Versionamento**:
   - Versão atual do projeto: **`1.0.0c`**.
   - **Pequenas atualizações / fixes**: Incrementar a letra final sequencialmente (`1.0.0d`, `1.0.0e`, ..., até `1.0.0z`).
   - **Ao esgotar o alfabeto ('z')**: Avançar o patch com 'a' (`1.0.1a`, ..., `1.0.1z`, depois `1.0.2a`...).
   - **Grandes atualizações estruturais (Big Update)**: Avançar para a próxima versão maior (`2.0.0a`).
   - Todos os arquivos com versão devem ser mantidos estritamente sincronizados:
     - `flutter_app/lib/theme/hud_theme.dart` (`appVersion`)
     - `flutter_app/pubspec.yaml` (`version: 1.0.0+X`)
     - `installer/setup.iss` (`#define MyAppVersion` e `VersionInfoVersion`)
     - `package.json` (`"version"`)
     - `installer/build_installer.ps1`
4. **Segurança e Commits no Git**:
   - Nunca expor credenciais reais no histórico do Git.
   - O e-mail do autor dos commits Git DEVE ser sempre `fepsmiotti@gmail.com` e o nome `Feps` (para coincidir com o proprietário do plano Vercel e não travar deploys com `seatBlock: COMMIT_AUTHOR_REQUIRED`).
5. **Atualização do Instalador e do Site a Cada Atualização (Mandatório)**:
   - No final de toda e qualquer alteração ou atualização de código:
     - Sempre compilar o instalador oficial Windows executando `installer/build_installer.ps1`.
     - Atualizar o binário `public/downloads/PapoCall-Setup.exe`.
     - Fazer commit e push na branch `main` com autor `Feps <fepsmiotti@gmail.com>`, garantindo que o site e o instalador na Vercel (`https://papocall.vercel.app`) fiquem sempre atualizados na última versão.

---

## 2. Visão Geral da Arquitetura

O **PapoCall** é uma aplicação desktop nativa para Windows desenvolvida com **Flutter**, com backend leve na **Vercel** e infraestrutura em nuvem para conferências WebRTC e mensageria MQTT.

### Componentes Principais:
1. **Frontend Desktop (`flutter_app/`)**:
   - **Flutter 3.x para Windows**: Interface de usuário acelerada por hardware.
   - **Tema HUD Sóbrio (`flutter_app/lib/theme/hud_theme.dart`)**: Estética militar/tática moderna, paleta escura (slate/zinc, fundo `#0B0E14`, acentos verde neon `#22C55E` e `#4ADE80`).
   - **Gerenciamento de Estado (`flutter_app/lib/providers/app_state.dart`)**: Baseado em `Provider` (`ChangeNotifier`). Orquestra a sessão do usuário, lista de canais, mensagens, estado das conexões de voz e controle da visualização ativa (`isHomePageActive`).
   - **Chat em Tempo Real (`flutter_app/lib/services/mqtt_service.dart`)**:
     - Utiliza broker público EMQX (`broker.emqx.io`).
     - **Transporte Duplo Resiliente**: Conexão primária via TCP nativo na porta 1883, com fallback automático para WebSocket seguro (`wss://broker.emqx.io/mqtt:8084`).
     - Auto-reconexão e restauração automática de subscrições em tópicos.
     - Geração de `clientId` único (`papocall_${userId}_${sessionId}`) para impedir desconexão de clientes na mesma rede.
   - **Voz e Streaming RTC (`flutter_app/lib/services/voice_service.dart`)**:
     - Motor WebRTC via **LiveKit Cloud**.
     - Geração e validação de tokens em `livekit_token_service.dart`.
     - Evita desconexões acidentais por `DUPLICATE_IDENTITY` adicionando sufixo exclusivo à identidade da chamada.
     - **Otimização de Transmissão**: Ao minimizar ou tirar o foco da janela do aplicativo, o streamer tem a renderização local da própria live pausada (redução drástica de consumo de GPU/CPU), enquanto os espectadores continuam recebendo a transmissão normalmente.
   - **Página Inicial do App (`flutter_app/lib/widgets/home_page_view.dart`)**:
     - Visualização em tela cheia acionada pelo botão no canto superior esquerdo da barra de servidores (`ServerRail`).
     - Oferece acesso rápido de 1 clique a canais de voz/chat, lista de amigos online com atalho para entrar na sala do amigo, diagnósticos ao vivo (latência, motor LiveKit e MQTT) e controle de chamada ativa.

2. **Hospedagem & Distribuição (Vercel & Inno Setup)**:
   - **Domínio Oficial**: `https://papocall.vercel.app`
   - **Landing Page**: `public/index.html` com botão estilizado de download.
   - **Instalador Oficial**: `public/downloads/PapoCall-Setup.exe` (~17.7 MB) rastreado no Git para publicação estática na CDN da Vercel.
   - **Automação de Build**: `installer/build_installer.ps1` compila o Flutter em modo Release para Windows e gera o instalador via Inno Setup (`ISCC.exe`).

---

## 3. Comandos Operacionais Essenciais

- **Executar aplicação localmente**:
  ```powershell
  cd flutter_app
  flutter run -d windows
  ```

- **Verificar análise estática (Lint/Errors)**:
  ```powershell
  cd flutter_app
  flutter analyze
  ```

- **Compilar e gerar novo instalador Windows**:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File installer/build_installer.ps1
  ```

- **Publicar alterações e novo instalador**:
  ```powershell
  git add -A
  git commit -m "feat: descrição da alteração (v1.0.0X)"
  git push origin main
  ```
  *(O push no GitHub dispara automaticamente o deploy de produção na Vercel).*
