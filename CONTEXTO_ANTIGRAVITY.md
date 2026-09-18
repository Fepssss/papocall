# Contexto Completo do Projeto: PapoCall

Este documento contém todas as informações, arquitetura, regras de desenvolvimento, histórico de decisões e instruções operacionais necessárias para que o **Antigravity IDE** e seus agentes compreendam e trabalhem no projeto com total autonomia e consistência.

---

## 1. Identificação do Projeto

- **Nome Oficial**: **PapoCall**
- **Versão Atual**: **`1.0.0c`**
- **Tipo de Aplicação**: Desktop Nativo para Windows (64-bit) construído em Flutter.
- **Proposta**: Aplicativo leve e sóbrio de comunicação em tempo real (voz em alta fidelidade, vídeo, compartilhamento de tela e chat por texto) com temática militar/tática HUD (Heads-Up Display).
- **Repositório Git**: `https://github.com/Fepssss/papocall.git` (Branch principal: `main`).
- **Deploy & Site Oficial**: `https://papocall.vercel.app`
- **Download do Instalador**: `https://papocall.vercel.app/downloads/PapoCall-Setup.exe`

---

## 2. Regras Imutáveis de Desenvolvimento

Ao trabalhar neste projeto no Antigravity, as seguintes regras devem ser rigorosamente respeitadas:

1. **Idioma Obrigatório**:
   - Sempre responda, crie mensagens e documente em **Português do Brasil (`pt-BR`)**.
2. **Nomenclatura do Produto**:
   - O projeto chama-se estritamente **PapoCall**.
   - Nunca utilize termos antigos ou de repositórios legados (ex: *projetous*).
   - Não faça comparações diretas ou menções nominais a aplicativos concorrentes (como *Discord*).
3. **Padrão Estrito de Versionamento**:
   - O projeto iniciou formalmente em `1.0.0a`, avançou para `1.0.0b` e atualmente está na **`1.0.0c`**.
   - **Atualizações pequenas / patches**: Incrementar a letra final sequencialmente (`1.0.0d`, `1.0.0e` ... até `1.0.0z`).
   - **Após a letra 'z'**: Avançar o patch com a letra 'a' (`1.0.1a` até `1.0.1z`, depois `1.0.2a` e assim sucessivamente).
   - **Big Updates (grandes marcos ou refatorações)**: Avançar para a próxima versão maior (`2.0.0a`).
   - **Sincronização de Versão**: Ao alterar a versão, sincronize obrigatoriamente os 5 arquivos:
     1. `flutter_app/lib/theme/hud_theme.dart` (`static const String appVersion = '...'`)
     2. `flutter_app/pubspec.yaml` (`version: 1.0.0+X`)
     3. `installer/setup.iss` (`#define MyAppVersion "..."` e `VersionInfoVersion=...`)
     4. `package.json` (`"version": "..."`)
     5. `installer/build_installer.ps1`
4. **Git e Deploys na Vercel**:
   - **Autor de Commits**: O autor dos commits Git DEVE ser configurado como:
     - `user.name`: `Feps`
     - `user.email`: `fepsmiotti@gmail.com`
     *(Motivo: A Vercel valida os autores de commits contra os membros da equipe. Usar qualquer e-mail diferente bloqueia os deploys automáticos com o erro `seatBlock: COMMIT_AUTHOR_REQUIRED`).*
   - **Segurança de Credenciais**: Nunca realize commit de segredos, chaves privadas ou tokens no repositório público do Git. O repositório possui pre-commit hook com **Gitleaks**.

---

## 3. Arquitetura do Sistema e Estrutura de Código

### A. Frontend Desktop (`flutter_app/`)
O aplicativo utiliza Flutter 3.x para desktop Windows com gerenciamento de janelas via `window_manager`.

- **Entrada do App (`flutter_app/lib/main.dart`)**:
  - Configura tamanho padrão e mínimo da janela (1280x720, mínimo 960x600).
  - Inicializa o `AppState` via `ChangeNotifierProvider`.
  - Alterna dinamicamente entre a tela de autenticação (`AuthScreen`) e a tela principal (`MainScreen`).
  - Renderiza o layout de 3 colunas ou a visualização em tela cheia da Página Inicial.

- **Gerenciamento de Estado (`flutter_app/lib/providers/app_state.dart`)**:
  - Estado global reativo que gerencia: usuário autenticado, servidores, canais de texto e voz, histórico de mensagens, conexão de voz ativa e a flag `isHomePageActive`.
  - Controla ações de entrada/saída de canais de voz e reconexões.

- **Chat em Tempo Real (`flutter_app/lib/services/mqtt_service.dart`)**:
  - Utiliza o broker público EMQX (`broker.emqx.io`).
  - **Estratégia de Transporte Duplo**: Conecta prioritariamente por TCP nativo na porta `1883`. Caso haja bloqueio por firewall ou rede corporativa, faz fallback automático para WebSocket seguro `wss://broker.emqx.io/mqtt:8084`.
  - Gera `clientId` exclusivo por sessão (`papocall_${userId}_${randomSuffix}`) para evitar desconexões mútuas quando usuários entram com dados semelhantes.
  - Possui reconexão automática e re-inscrição transparente em todos os tópicos de canais.

- **Chamadas de Voz e Vídeo RTC (`flutter_app/lib/services/voice_service.dart`)**:
  - Baseado na SDK oficial do **LiveKit**.
  - Gerencia faixas de áudio e vídeo de participantes locais e remotos.
  - **Otimização de Transmissão de Live**: Quando o streamer minimiza ou tira o foco da janela do aplicativo, a renderização local da sua própria live é suspensa para poupar GPU/CPU, continuando transmitindo para os espectadores. Transmissões de terceiros continuam sempre renderizando.

- **Autenticação e Tokens RTC (`flutter_app/lib/services/livekit_token_service.dart`)**:
  - Suporta geração de tokens LiveKit embutida (offline-first) e via API remota.
  - Gera identidades com sufixo de sessão exclusivo (`${username}_${userId}_${sessionSuffix}`) para evitar que conexões simultâneas caiam com erro `DUPLICATE_IDENTITY`.
  - As credenciais de produção do LiveKit Cloud são embutidas em tempo de compilação no executável via `--dart-define` e no arquivo de contingência local `data/livekit.json`.

- **Nova Página Inicial do App (`flutter_app/lib/widgets/home_page_view.dart`)**:
  - Visualização em tela cheia acessível a qualquer momento pelo botão Home no topo da barra de servidores (`ServerRail`).
  - Contém:
    - Card de boas-vindas com avatar, status online e versão do app.
    - Acesso rápido aos canais de voz e chat mais utilizados.
    - Lista de amigos online com indicação da sala onde estão e botão de 1 clique para entrar na mesma sala.
    - Banner de chamada ativa (permite mutar/desligar sem sair da home).
    - Painel de diagnósticos ao vivo (latência, motor LiveKit, broker MQTT e modo de economia de energia).

- **Identidade Visual (`flutter_app/lib/theme/hud_theme.dart`)**:
  - Paleta tática sóbria:
    - Fundo base: `#0B0E14`
    - Superfícies secundárias: `#111620`, `#171F2C`
    - Bordas táticas: `#1E293B`, `#334155`
    - Destaque primário (Neon Green): `#22C55E`
    - Acentos de alerta/perigo: `#EF4444`
    - Acentos de informação/voz: `#06B6D4`
  - Fontes: Segoe UI, Roboto e fontes monoespaçadas para métricas e indicadores.

---

### B. Distribuição & Instalador (`installer/`)
- **Script de Automação (`installer/build_installer.ps1`)**:
  - Executa a compilação do Flutter Windows em Release com os parâmetros de injeção de credenciais:
    `flutter build windows --release --dart-define=LIVEKIT_URL=... --dart-define=LIVEKIT_API_KEY=... --dart-define=LIVEKIT_API_SECRET=...`
  - Empacota o instalador usando o **Inno Setup 6** (`ISCC.exe`).
  - Gera o instalador final em:
    - `public/downloads/PapoCall-Setup.exe` (para distribuição web na Vercel)
    - `PapoCall-Setup.exe` (na raiz do projeto)
- **Script Inno Setup (`installer/setup.iss`)**:
  - Define ícones, atalhos na Área de Trabalho e Menu Iniciar, permissões administrativas e desinstalador limpo.

---

### C. Backend & Infraestrutura Vercel
- **Repositório GitHub**: Conectado à Vercel (`feps-developer/papocall`).
- **Deploy Automático**: Qualquer `git push origin main` compila e publica a nova versão na Vercel em ~11 segundos.
- **Roteamento (`vercel.json`)**:
  - Expõe as Serverless Functions em `/api/*` (`api/livekit-token.js`).
  - Entrega arquivos estáticos de `public/*` na raiz `/`.
- **Landing Page (`public/index.html`)**:
  - Página minimalista e moderna com tema escuro e botão direto para download do `PapoCall-Setup.exe`.

---

## 4. Guia de Comandos Frequentes

| Ação Desejada | Comando / Procedimento |
| :--- | :--- |
| **Rodar o App em Desenvolvimento** | `cd flutter_app; flutter run -d windows` |
| **Verificar Linter e Erros de Código** | `cd flutter_app; flutter analyze` |
| **Compilar e Gerar o Instalador** | `powershell -ExecutionPolicy Bypass -File installer/build_installer.ps1` |
| **Publicar Nova Atualização** | 1. Atualizar versão nos 5 arquivos<br>2. Gerar instalador<br>3. `git add -A`<br>4. `git commit -m "feat: sua alteração (v1.0.0X)"`<br>5. `git push origin main` |

---

## 5. Cuidados Técnicos e Solução de Problemas Conhecidos

1. **Erro `seatBlock: COMMIT_AUTHOR_REQUIRED` na Vercel**:
   - Se os deploys automáticos na Vercel ficarem em estado `UNKNOWN` ou falharem, verifique com `git config user.email`. Ele deve ser obrigatoriamente `fepsmiotti@gmail.com`. Se necessário, rode `git commit --amend --author="Feps <fepsmiotti@gmail.com>"` e faça `git push origin main --force`.

2. **Chat Não Entregando Mensagens**:
   - Verifique o log do `MqttService`. O transporte nativo TCP porta 1883 é o padrão. Se falhar, certifique-se de que a URL de WebSocket use o esquema correto: `wss://broker.emqx.io/mqtt` na porta 8084.

3. **Chamada de Voz Desconectando Imediatamente**:
   - Causado geralmente por colisão de identidade no LiveKit Cloud. O `livekit_token_service.dart` adiciona um sufixo aleatório único para cada sessão (`_${Random().nextInt(999999)}`), garantindo que duas instâncias não se derrubem mutuamente.

4. **Instalador Desatualizado no Site da Vercel**:
   - Certifique-se de que `public/downloads/PapoCall-Setup.exe` foi incluído no commit (`git status`). O arquivo `.gitignore` possui a exceção `!public/downloads/PapoCall-Setup.exe` para permitir o versionamento do executável compilado.
