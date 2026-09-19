# Atualização de Segurança — PapoCall v1.0.0g

> **Documento de handoff para outro agente.** Descreve o que foi auditado, o que
> mudou, por quê, o que **ainda precisa ser feito por uma pessoa**, e quais
> invariantes não podem ser quebradas em alterações futuras.

- **Versão anterior:** 1.0.0f
- **Versão desta atualização:** 1.0.0g
- **Data:** 2026-09-19
- **Escopo:** app Flutter (Windows), backend TypeScript, função serverless da Vercel, servidor Node de desenvolvimento, pipeline de build e distribuição.

---

## 1. AÇÃO MANUAL OBRIGATÓRIA E URGENTE

**Rotacionar as credenciais do LiveKit no painel da LiveKit Cloud.**

Nenhuma alteração de código resolve isto, porque o segredo já saiu.

O instalador `public/downloads/PapoCall-Setup.exe` publicado até a v1.0.0f foi
compilado por um script que gravava `LIVEKIT_API_KEY` e `LIVEKIT_API_SECRET` em
texto puro dentro de `{app}\data\livekit.json`, empacotado junto com o app. Esse
instalador estava versionado no Git (commit `628fc72`) e servido publicamente em
`https://papocall.vercel.app/downloads/PapoCall-Setup.exe`.

Ou seja: **qualquer pessoa que baixou o instalador tem a chave e o segredo.** Com
eles é possível entrar em qualquer sala, publicar áudio e vídeo, gravar sessões e
consumir a cota faturada do projeto.

Depois de rotacionar, atualizar as variáveis em:
- `.env` local (não versionado)
- variáveis de ambiente do projeto na Vercel
- `backend/.env` do serviço de autenticação

O histórico do Git foi verificado e **não contém** o segredo em texto — o
vazamento ocorreu exclusivamente pelo binário. Portanto não é necessário
reescrever o histórico.

---

## 2. Vulnerabilidades corrigidas

### 2.1 Segredo do LiveKit embutido no app distribuído — CRÍTICO

**Era:** `installer/build_installer.ps1` lia o `.env` e injetava o segredo no
binário por `--dart-define`, além de gravá-lo em `data/livekit.json`, empacotado
pelo `setup.iss` via `Source: ...\data\*`.

**Agora:** o build recebe apenas configuração pública (`PAPOCALL_API_URL`).
O script apaga qualquer `livekit.json` legado e **aborta** se encontrar arquivo
de credencial dentro do pacote. `.gitignore` bloqueia `**/livekit.json`.

**Verificação executada:** `grep` no `app.so` compilado não encontra a chave, o
segredo, nem o host real do LiveKit — apenas a URL pública da API.

### 2.2 Cliente assinava o próprio token de voz — CRÍTICO

**Era:** `livekit_token_service.dart` montava e assinava um JWT HS256 com o
segredo da API, em quatro caminhos de fallback (dart-define, JSON ao lado do
executável, `%APPDATA%`, `.env`). Esse desenho **exige** que o segredo esteja na
máquina do usuário, então não havia como distribuir o app com segurança.

**Agora:** o serviço só faz `POST /livekit/token` com `Authorization: Bearer
<access token>`. A `identity` é derivada do JWT **no servidor**. A dependência
`dart_jsonwebtoken` foi removida do `pubspec.yaml`.

### 2.3 Chat trafegava em claro por broker público anônimo — CRÍTICO

**Era:** `broker.emqx.io:1883`, sem TLS e sem autenticação, em tópicos
previsíveis (`papocall/v1/srv/+/chat`, `papocall/v1/global/presence`). Qualquer
pessoa com `mosquitto_sub -t 'papocall/v1/#'` lia todas as mensagens e a presença
de todos os usuários, e podia publicar mensagens forjadas em nome de qualquer um.
Pior: o app assinava com **curinga**, então todo cliente recebia o chat de todos
os servidores, inclusive os que nunca foi convidado.

**Agora** (`flutter_app/lib/services/server_crypto.dart`):
- Chave AES-256 derivada do código de convite do servidor por PBKDF2-HMAC-SHA256, 210.000 iterações.
- Payload cifrado com **AES-256-GCM** — dá confidencialidade e autenticidade: mensagem adulterada ou publicada por quem não tem a chave falha na verificação do MAC e é descartada.
- Tópicos opacos: `papocall/v2/r/<sha256(convite)[0:32]>/{chat,presence}`, com rótulo de domínio **diferente** do usado na derivação da chave.
- Curinga removido: o app assina apenas os servidores do usuário.
- Presença deixou de ser global; é publicada por servidor e cifrada.
- Transporte via TLS 8883, com fallback só para WSS 8084. **Sem fallback em texto puro.**
- Regenerar o convite rotaciona chave e tópico, cortando quem tinha o código antigo.

**Verificação executada:** 8 testes em `flutter_app/test/server_crypto_test.dart`
cobrem leitura por membro, opacidade do envelope, rejeição de quem não tem o
convite, rejeição de mensagem adulterada, rejeição de payload forjado, e
rotação de convite. Todos passam.

> **Limitação conhecida e aceita:** membros do mesmo servidor compartilham a
> chave, então um membro legítimo ainda consegue forjar mensagem de outro membro
> *daquele* servidor. Resolver isso exige assinatura por usuário (chave por
> conta). A correção fecha o acesso de terceiros, que era o problema real.

### 2.4 "Cofre local" anulava toda a autenticação — CRÍTICO

**Era:** `auth_service.dart` apontava para `http://localhost:3333`, endereço que
nunca existe na máquina de um usuário final. Toda tentativa de login caía num
fallback local onde a senha virava `sha256("papocall_salt_" + senha)` (salt
global fixo), o access token era a string previsível `local-token-<timestamp>`,
`emailVerified` era sempre `true`, e `users_vault.json` ficava em texto puro —
bastava editar o JSON para entrar como qualquer pessoa.

**Agora:**
- Todo o cofre local foi **removido**.
- A URL do backend vem de `PAPOCALL_API_URL` e usa HTTPS.
- A sessão é gravada cifrada com a **DPAPI do Windows** (`secure_storage.dart`, via FFI para `crypt32.dll`), com entropia específica do app. O arquivo virou `session.dat`; copiado para outra máquina ou lido por outro usuário do Windows, é inútil.
- Se a criptografia falhar, a sessão **não é persistida** — nunca há queda para texto puro.
- `purgeLegacyInsecureFiles()` roda na inicialização e apaga `session.json`, `users_vault.json` e `livekit.json` deixados pelas versões anteriores.

### 2.5 `server.js` — ALTO

| Correção | Detalhe |
|---|---|
| Endpoint de token do LiveKit **removido** | Era anônimo, aceitava `identity` pela query e respondia com `Access-Control-Allow-Origin: *` |
| Verificação de `Origin` no WebSocket | Sem ela, qualquer site aberto no navegador conectava em `ws://localhost:3456`, lia todo o histórico e injetava mensagens (CSWSH) |
| Bind em `127.0.0.1` | Era `0.0.0.0`, expondo um chat sem autenticação para toda a rede local |
| Validação de canal | `state.messages[channelId]` aceitava qualquer string, permitindo inflar a memória do servidor |
| Limite de taxa e de tamanho | 40 mensagens / 10 s por conexão; `maxPayload` de 4 KB; teto de 100 canais |
| Sanitização de entrada | Remove caracteres de controle e aplica limites de tamanho |
| Sinalização WebRTC restrita | Só repassa entre usuários na **mesma** sala de voz; antes dava para forçar negociação com qualquer usuário e descobrir o IP dele |
| IDs imprevisíveis | `crypto.randomBytes` no lugar de `Math.random()` |
| Cabeçalhos de segurança | CSP, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` |
| Checagem explícita de path traversal | Defesa em profundidade (o parser de URL já normalizava `..`) |

### 2.6 `api/livekit-token.js` — ALTO

**Era:** anônimo, `identity` pela query, `Access-Control-Allow-Origin: *` junto
com `Access-Control-Allow-Credentials: true`. Não estava implantado (retornava
404), então era risco **latente**, não explorado.

**Agora:** exige `Authorization: Bearer <JWT RS256>` validado com a chave pública
(`JWT_PUBLIC_KEY`), exige e-mail verificado, valida o formato da sala, deriva a
`identity` do JWT, restringe CORS a uma whitelist e só aceita POST.

### 2.7 Backend TypeScript — ALTO / MÉDIO

| Correção | Onde | Por quê |
|---|---|---|
| Rate limiter parou de confiar em `X-Forwarded-For` | `rate-limiter.middleware.ts` | O cabeçalho é controlado pelo cliente: bastava mudá-lo a cada tentativa para anular a proteção contra força bruta. Agora usa `req.ip` com `trust proxy: 1` |
| Envio real de e-mail (nodemailer) | `utils/email.ts` | O serviço era mock: em produção sem SMTP **imprimia o token de reset em texto puro no log** (tomada de conta por quem lê logs); com SMTP, não enviava nada |
| Falha de envio não altera a resposta | `auth.service.ts` | 500 no e-mail existente vs 200 no inexistente revelaria quais contas existem |
| Rate limit em register / forgot-password / reset / refresh / username-available | `auth.routes.ts` | Só o login tinha. Faltava barrar spam de contas e bombardeio de e-mail |
| `requireVerifiedEmail` aplicado à voz | `livekit.routes.ts` | Estava implementado e **nunca usado** |
| Rate limit na emissão de token de voz | `livekit.routes.ts` | Cada token é uma conexão RTC faturada |
| Sala validada por regex | `auth.schemas.ts` | Impede pedir nome de sala arbitrário |
| Senha com máximo de 128 caracteres | `auth.schemas.ts` | Argon2id aloca 19 MB por hash; senha gigante é DoS barato |
| Identificador de login não vai mais para o log | `auth.service.ts` | Usuários digitam a senha no campo de e-mail — isso gravava senha no log de auditoria |
| Falha na inicialização com credencial de exemplo | `config/env.ts` | Deploy com `your_api_key_here` rodava e falhava só na hora da chamada |

---

## 3. O que **não** era vulnerabilidade (verificado, não presumido)

- **Path traversal no servidor estático:** não explorável. O parser WHATWG de URL
  normaliza `..` antes do `path.join`, e `%2e%2e` não é decodificado. Testado com
  8 vetores, incluindo barra invertida do Windows e dupla codificação. A checagem
  explícita foi adicionada só como defesa em profundidade.
- **Histórico do Git:** limpo. Nenhum segredo real commitado.
- **`backend/src/config/keys.ts`:** implementação correta de RS256, sem segredo fixo.

---

## 4. O que já estava bem feito (não regredir)

O backend TypeScript é sólido e **não deve ser simplificado**:
Argon2id com parâmetros OWASP, RS256 com chaves assimétricas, rotação de refresh
token **com detecção de reuso e revogação em cascata da família**, refresh tokens
guardados apenas como hash SHA-256, helmet, CORS com whitelist, limite de
payload, error handler que não vaza stack em produção, mitigação de timing attack
no login, e gitleaks no pre-commit e na CI.

---

## 5. Pendências para uma pessoa resolver

1. **Rotacionar as credenciais do LiveKit** (seção 1). Bloqueante.
2. **Implantar o backend de autenticação.** O app agora exige um backend real:
   sem ele, login e voz não funcionam — e isso é intencional, já que o fallback
   inseguro foi removido. Hoje `https://papocall.vercel.app` serve apenas o site
   estático; as rotas `/auth/*` não existem. É preciso publicar o serviço de
   `backend/` e apontar `PAPOCALL_API_URL` para ele.
3. **Configurar SMTP em produção.** Sem `SMTP_HOST` o backend agora se recusa a
   subir, de propósito: verificação de e-mail e recuperação de senha dependem
   disso.
4. **Definir `JWT_PUBLIC_KEY` na Vercel** para a função `api/livekit-token.js`
   validar os tokens.
5. **Assinar o instalador** (code signing). Continua sem assinatura: o SmartScreen
   alerta e não há garantia de integridade na distribuição.
6. **Trocar SQLite por PostgreSQL** em produção. O `schema.prisma` fixa
   `provider = "sqlite"` apesar do comentário prometer Postgres.
7. **Avaliar sair do broker público.** A criptografia ponta a ponta resolve
   confidencialidade e autenticidade, mas o broker ainda vê metadados (quais
   tópicos, quando, de qual IP) e pode derrubar o serviço a qualquer momento.

---

## 6. Invariantes — não quebrar em mudanças futuras

1. **Nenhum segredo no app Flutter.** O binário é público. Só configuração
   pública pode ir para o build. A trava no `build_installer.ps1` existe para
   isso e não deve ser removida.
2. **O cliente nunca assina token do LiveKit.** Sempre pedir ao backend.
3. **Nada trafega em claro pelo MQTT.** Todo `publish` passa por
   `ServerCrypto.encryptPayload`; todo recebimento passa por `decryptPayload` e
   descarta o que falhar.
4. **Nunca assinar tópico MQTT com curinga na posição do identificador de
   servidor ou de usuário.** Foi essa a falha da v1.0.0f: `papocall/v1/srv/+/chat`
   punha o curinga exatamente onde fica a fronteira de autorização, e todo
   cliente recebia o chat de servidores dos quais nunca participou.

   Um curinga **inteiramente abaixo** dessa fronteira é permitido, porque não
   amplia o alcance de ninguém: o prefixo já é um segredo que só quem está
   autorizado consegue montar. Existe exatamente um no aplicativo, introduzido
   na v1.0.0n:

   `papocall/v2/u/<hash-da-caixa-do-usuário>/inbox/#`

   O prefixo é derivado do @ do próprio usuário; o `#` só percorre os
   compartimentos dos remetentes dentro da caixa dele, e não alcança a caixa de
   outro usuário nem nenhum servidor. Ele é necessário porque não há como
   assinar previamente o compartimento de um remetente ainda desconhecido — e é
   o que faz uma solicitação de amizade enviada com o destinatário offline estar
   esperando por ele quando o app abrir.

   A presença **não** usa curinga: o tópico compartilhado do servidor é assinado
   pelo nome exato (heartbeats ao vivo, que revelam membros novos) e o
   compartimento retido de cada membro já conhecido é assinado individualmente.
5. **Nunca gravar token ou senha em texto puro no disco.** Usar `SecureStorage`.
   Se a criptografia falhar, não persistir — não cair para texto puro.
6. **Nenhum fallback de autenticação local.** Sem backend, o login falha; é o
   comportamento correto.
7. **Rate limiter nunca lê `X-Forwarded-For` diretamente.** Usar `req.ip` com
   `trust proxy` configurado.
8. **Token de reset e de verificação jamais em log de produção.**
9. **`identity` do LiveKit sempre derivada do JWT**, nunca do corpo ou da query.

---

## 7. Como validar

```bash
cd backend && npm test
```

```bash
cd flutter_app && flutter analyze && flutter test
```

Conferir que o build não contém segredo:

```bash
grep -ac "APIdzjus\|apiSecret" flutter_app/build/windows/x64/runner/Release/data/app.so
```

---

## 8. Arquivos alterados

**Adicionados**
- `flutter_app/lib/services/server_crypto.dart` — criptografia ponta a ponta do MQTT
- `flutter_app/lib/services/secure_storage.dart` — DPAPI do Windows via FFI
- `flutter_app/test/server_crypto_test.dart` — testes das garantias criptográficas
- `SECURITY_UPDATE_v1.0.0g.md` — este documento

**Modificados**
- `installer/build_installer.ps1`, `installer/setup.iss`
- `flutter_app/lib/services/livekit_token_service.dart`, `auth_service.dart`, `mqtt_service.dart`, `voice_service.dart`
- `flutter_app/lib/providers/app_state.dart`
- `flutter_app/pubspec.yaml` (`+cryptography`, `−dart_jsonwebtoken`), `lib/theme/hud_theme.dart`
- `server.js`, `api/livekit-token.js`, `vercel.json`, `package.json`, `.gitignore`, `.env.example`
- `backend/src/`: `app.ts`, `config/env.ts`, `middlewares/rate-limiter.middleware.ts`, `modules/auth/auth.routes.ts`, `modules/auth/auth.schemas.ts`, `modules/auth/auth.service.ts`, `modules/livekit/livekit.routes.ts`, `utils/email.ts`
- `backend/package.json` (`+nodemailer`, `+cross-env`), `backend/.env.example`, `backend/tests/auth.test.ts`
- `AGENTS.md`

**Removido do versionamento**
- `public/downloads/PapoCall-Setup.exe` na versão comprometida, substituído por um build limpo
