# PapoCall - Diretrizes e Contexto para Antigravity IDE

Este arquivo é lido automaticamente pelo Antigravity IDE para orientar o agente em todas as tarefas, garantindo consistência com a arquitetura, regras de negócio e padrões técnicos do PapoCall.

---

## 1. Regras Obrigatórias e Imutáveis

1. **Idioma**: Sempre responder, documentar e interagir em **Português do Brasil (pt-BR)**.
2. **Nome do Projeto**: O aplicativo chama-se estritamente **PapoCall**. Nunca utilize termos legados (como *projetous*) e não faça referências a concorrentes (como *Discord*).
3. **Padrão de Versionamento**:
   - Versão atual do projeto: **`1.0.0s`**.
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
   - **NUNCA embutir segredo algum no aplicativo Flutter.** O binário entregue
     ao usuário é público: `--dart-define`, arquivos JSON ao lado do executável
     e `.env` empacotados são todos extraíveis. Somente configuração pública
     (ex.: `PAPOCALL_API_URL`) pode ir para o build. Segredo de servidor
     (`LIVEKIT_API_SECRET`, chaves JWT, SMTP) vive apenas no backend.
   - O `installer/build_installer.ps1` aborta o build se encontrar arquivo de
     credencial dentro do pacote. Não remova essa trava.
   - **Testes nunca apagam dados reais.** `npm test` no backend usa o mesmo
     `DATABASE_URL` do serviço no ar, e até a `1.0.0q` a limpeza da suíte era um
     `deleteMany()` sem filtro: rodar os testes registrava todas as contas como
     inexistentes e o usuário perdia o login. A limpeza é restrita ao domínio de
     fixture `@papocall.test` e a suíte falha se qualquer conta real mudar.
     Prefira `TEST_DATABASE_URL` apontando para um banco descartável.
   - O e-mail do autor dos commits Git DEVE ser sempre `fepsmiotti@gmail.com` e o nome `Feps` (para coincidir com o proprietário do plano Vercel e não travar deploys com `seatBlock: COMMIT_AUTHOR_REQUIRED`).
5. **Atualização do Instalador e do Site a Cada Atualização (Mandatório)**:
   - No final de toda e qualquer alteração ou atualização de código:
     - Sempre compilar o instalador oficial Windows executando `installer/build_installer.ps1`.
     - Atualizar o binário `public/downloads/PapoCall-Setup.exe`.
     - Fazer commit e push na branch `main` com autor `Feps <fepsmiotti@gmail.com>`, garantindo que o site e o instalador na Vercel (`https://papocall.vercel.app`) fiquem sempre atualizados na última versão.
6. **Divisão de Responsabilidades entre Agentes de IA**:
   - **Agente Principal (este agente)**: Responsável pelo código principal da aplicação (features, arquitetura Flutter, interfaces visuais, regras de negócio e fluxos operacionais).
   - **Agente de Segurança**: Responsável exclusivamente pela análise de vulnerabilidades, auditorias de segurança, validação de permissões e higienização de credenciais/tokens.
   - **Trabalho Sequencial (Não Simultâneo)**: Os agentes atuam em momentos distintos (nunca simultaneamente) para evitar colisões de versão, conflitos no Git e inconsistências no código.

---

## 2. Visão Geral da Arquitetura

O **PapoCall** é uma aplicação desktop nativa para Windows desenvolvida com **Flutter**, com backend leve na **Vercel** e infraestrutura em nuvem para conferências WebRTC e mensageria MQTT.

### Componentes Principais:
1. **Frontend Desktop (`flutter_app/`)**:
   - **Flutter 3.x para Windows**: Interface de usuário acelerada por hardware.
   - **Tema HUD Sóbrio (`flutter_app/lib/theme/hud_theme.dart`)**: Estética militar/tática moderna, paleta escura (slate/zinc, fundo `#0B0E14`, acentos verde neon `#22C55E` e `#4ADE80`).
   - **Gerenciamento de Estado (`flutter_app/lib/providers/app_state.dart`)**: Baseado em `Provider` (`ChangeNotifier`). Orquestra a sessão do usuário, lista de canais, mensagens, estado das conexões de voz e controle da visualização ativa (`isHomePageActive`).
   - **Chat em Tempo Real (`flutter_app/lib/services/mqtt_service.dart`)**:
     - Utiliza broker público EMQX (`broker.emqx.io`), tratado como **transporte hostil**.
     - **Transporte cifrado**: TLS na porta 8883, com fallback para WebSocket seguro (`wss://broker.emqx.io/mqtt:8084`). **Não existe fallback em texto puro (1883)**.
     - **Criptografia ponta a ponta (`server_crypto.dart`)**: o payload é cifrado com AES-256-GCM usando chave derivada do código de convite do servidor via PBKDF2 (210k iterações). O broker nunca vê conteúdo legível.
     - **Tópicos opacos**: `papocall/v2/r/<hash-do-convite>/{chat,presence,info}`, mais um compartimento retido por membro em `presence/<hash-do-membro>` e a caixa de entrada pessoal em `papocall/v2/u/<hash-do-usuário>/inbox/<hash-do-remetente>`.
     - **Curinga proibido na posição do identificador de servidor ou de usuário** — é ali que fica a fronteira de autorização, e foi essa a falha da v1.0.0f (`srv/+/chat`). O app assina apenas os servidores que o usuário integra, sempre pelo nome exato. Existe **um único** curinga em todo o app, inteiramente abaixo da fronteira: `papocall/v2/u/<hash-do-usuário>/inbox/#`, que percorre só os compartimentos de remetentes dentro da caixa do próprio usuário. Sem ele não há como receber uma solicitação de amizade de alguém ainda desconhecido enviada enquanto o destinatário estava offline. A presença não usa curinga algum.
     - **Estrutura do servidor replicada** (`action: server_info`, retida): só o dono publica. Quem entra por convite adota nome, cor e — principalmente — os IDs de canal reais. Como o nome da sala do LiveKit é o ID do canal, inventar canais localmente colocava cada membro numa sala de voz diferente. O payload carrega também o roster (`memberIds`), única forma de um recém-chegado saber de quem assinar presença e histórico.
     - **Histórico compartilhado** (`action: history_snapshot`, retido): cada membro publica no seu próprio compartimento um retrato das mensagens recentes que conhece (60 por canal, teto de 300 e de 160 KB); quem chega intercala os retratos de todos por `id` e ordena por `sentAt`. Um tópico único e compartilhado não serviria — o broker guarda só a última mensagem retida de cada tópico, então o último a publicar apagaria o histórico dos demais.
     - **Marcações** (`flutter_app/lib/utils/mentions.dart`): o `@fulano` vive no texto da mensagem, não numa lista paralela no envelope, para continuar funcionando no histórico alheio e em mensagens de versões anteriores. A regex exige fronteira dos dois lados — sem a da direita, um @ longo demais casaria pelos 20 primeiros caracteres e marcaria outra pessoa.
     - Auto-reconexão com backoff, restauração automática de subscrições e reconciliação de estado a cada reconexão (reassinar, reanunciar presença, reenviar a fila de saída).
     - `clientId` aleatório por sessão (não deriva do `userId`, que era rastreável no broker público).
   - **Voz e Streaming RTC (`flutter_app/lib/services/voice_service.dart`)**:
     - Motor WebRTC via **LiveKit Cloud**.
     - **O token é emitido pelo backend**, nunca assinado no cliente. `livekit_token_service.dart` apenas faz `POST /livekit/token` com o access token da sessão; a `identity` é derivada do JWT no servidor, impedindo personificação.
     - Evita desconexões acidentais por `DUPLICATE_IDENTITY` adicionando sufixo exclusivo à identidade da chamada.
     - **Otimização de Transmissão**: Ao minimizar ou tirar o foco da janela do aplicativo, o streamer tem a renderização local da própria live pausada (redução drástica de consumo de GPU/CPU), enquanto os espectadores continuam recebendo a transmissão normalmente.
   - **Sessão de login (`auth_service.dart` + `app_state.dart`) — invariante desde a v1.0.0s**:
     - Só o `AppState` renova o access token, por `renewSession()`, que é **single-flight**: no máximo uma renovação em andamento. O backend rotaciona o refresh token a cada uso e, se receber um token já consumido, trata como roubo e revoga **todas** as sessões da conta (`TOKEN_REUSE_DETECTED`). Duas renovações paralelas — inclusive duas janelas do app abertas na mesma máquina, que leem o mesmo `session.dat` — deslogam a conta inteira.
     - Nunca renovar por fora lendo o disco. `AuthService.loadSession()` é só para a inicialização; quem renova precisa atualizar `currentSession` em memória, senão disco e memória divergem e o próximo uso queima um token já consumido.
     - `clearSession()` só é chamado pelo `logout()`. Uma renovação pode apagar a sessão **somente** quando o backend responde `INVALID_REFRESH_TOKEN`, `TOKEN_REUSE_DETECTED` ou `REFRESH_TOKEN_EXPIRED` (4xx com `error.code` em JSON). Rede, timeout, cold start do Render, 5xx, 429 e corpo sem JSON são `transientFailure`: a sessão continua válida. A v1.0.0r e anteriores derrubavam o login nesses casos, e era isso que fazia a conta parecer sumir depois de sair e tentar entrar de novo.
     - O access token dura 15 min e o refresh 7 dias. Renova-se ao abrir o app e antes de entrar na call quando falta menos de 2 min (`AuthService.accessTokenValid`), sempre por `exp` do JWT (claim em **segundos**), sem decodificar nada — o payload do JWT é público por construção.
     - Diagnóstico: `AppLog.write(tag, msg)` anexa em `%APPDATA%\PapoCall\papocall.log` e **nunca** recebe token, senha ou chave; logar códigos HTTP, `error.code` e a hora de expiração é o que permitiu achar o defeito acima. `flutter test` define `FLUTTER_TEST`, e o AppLog se cala: teste não escreve no log da instalação real.
     - Toda escrita local passa por `AppPaths` (`lib/utils/app_paths.dart`). `AppState.dataRootOverride` é um alias de `AppPaths.rootOverride`: apontar a raiz para um diretório temporário no `setUp` é o que isola teste de dado real — ver a regra "Testes nunca apagam dados reais".
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
