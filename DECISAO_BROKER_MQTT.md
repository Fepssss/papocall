# Decisão: broker MQTT dedicado em vez do `broker.emqx.io` público

Documento de comparação e recomendação, **prévito a provisionar qualquer coisa**.
Nada aqui foi implementado; as três escolhas no fim são do dono do projeto.

Base medida no código em 2026-09-21, não em suposição:

| Fato | Onde |
| --- | --- |
| Host público com dois hardcoded, sem credencial alguma no CONNECT | `flutter_app/lib/services/mqtt_service.dart:113` (TLS 8883) e `:150` (WSS 8084) |
| Tópico de sala é `sha256("papocall/v2/topic:" + convite)` truncado a 32 hex — **sem segredo no cálculo** | `server_crypto.dart:83-92` |
| Tópico da caixa de entrada é derivado do **nome de usuário em claro** (`"inbox:<username>"`) | `server_crypto.dart:140-141` |
| O estado do servidor mora em mensagens **retidas** (info do servidor, presença por membro, histórico por membro) e é **republicado por cada cliente ao reconectar** | `app_state.dart:1108-1119` |
| O backend tem 4 tabelas: `User`, `RefreshToken`, `EmailVerificationToken`, `PasswordResetToken` — **não existe servidor nem membro no banco** | `backend/prisma/schema.prisma` |

A última linha é a que muda o plano, e está detalhada em §3.

---

## 1. O problema real, em ordem de gravidade

1. **Disponibilidade.** `broker.emqx.io` é um broker de demonstração público: sem SLA, sem aviso quando cai, e compartilhado com qualquer pessoa da internet. Ontem ele ficou saturado e o app ficou mudo até reiniciar — é o motivo pelo qual o backoff próprio existe (`mqtt_service.dart:92-108`).
2. **Conexão anônima.** Qualquer cliente MQTT se conecta sem credencial e **pode publicar em qualquer tópico**. Hoje a defesa contra isso é (a) AES-256-GCM, cujo MAC descarta mensagem forjada, e (b) o teto de 256 KB por payload (`mqtt_service.dart:231`), que existe justamente para um estranho não inflar a memória do app. Ou seja: já se pagou para sobreviver à ausência de controle de acesso.
3. **Abuso não rastreado.** Sem identidade no broker, não há como rate-limitar *por usuário*, e um spammer trocando de `clientId` (que já é aleatório por sessão, `mqtt_service.dart:76-80`) fica invisível.

O que **não** está na lista: confidencialidade. O broker nunca viu texto em claro, e continua não precisando ver.

## 2. As duas opções de infraestrutura

### A. Broker gerenciado (EMQX Cloud Serverless, HiveMQ Cloud)

| | |
| --- | --- |
| Custo | EMQX Cloud Serverless: free tier com 1000 conexões simultâneas, ~1000 msg/s e **2000 mensagens retidas**. HiveMQ Cloud Free: 100 conexões, 10 GB/mês, WebSocket incluído. |
| Esforço | Tarde da noite: TLS, portas 8883/443-as-wss e auth por usuário/senha já vêm prontos. |
| Controle | O que a plataforma expõe. Auth via HTTP/webhook e ACL dinâmica são o item a **confirmar no plano gratuito antes de assinar** — é onde os provedores cortam recurso. |
| Risco | O teto de **retidas é o estado do produto**: cada servidor conta 1 `info` + 1 slot de presença + 1 slot de histórico **por membro**. Com ~50 servidores de 10 membros isso é ~1000 retidas, e os compartimentos de inbox de cada par de usuários somam em cima. O free tier acabaria em dezenas de servidores, não em milhares de usuários. |
| Latência | Região escolhida no cadastro; alinhar com a região do Render. |

### B. Self-hosted (EMQX OSS em VPS/container)

| | |
| --- | --- |
| Custo | ~€5–7/mês por uma VPS pequena; EMQX OSS é Apache-2.0. |
| Esforço | Provisionar, subir TLS, configurar auth HTTP + ACL, monitorar, atualizar, backupar. É infraestrutura sua para manter para sempre. |
| Controle | Total, e sem teto arbitrário: auth HTTP e ACL dinâmica são nativos do EMQX 5.x (fonte de dados HTTP respondendo `allow`/`deny` e `expire_at` por sessão). |
| Risco bloqueante | **Precisa de um domínio sob seu controle para o Let's Encrypt.** Hoje o produto vive em `papocall.vercel.app`, cujo DNS é da Vercel: não dá para emitir certificado para ele. Alternativas: registrar um domínio, ou usar certificado IP do Let's Encrypt (perfil para endereços IPv4/IPv6) e validar se a pilha `dart:io` do `mqtt_client` aceita — isso é teste, não suposição. |

**Mosquitto ficou fora por um motivo concreto:** ele não tem consulta HTTP nativa. Auth dinâmica ali se resolve com o `auth-plug` da comunidade (C, compilação, manutenção incerta) ou com arquivo de ACL estático reescrito pelo backend e recarregado a cada emissão de credencial — que funciona, mas é cola no lugar onde o EMQX tem recurso de produto. Para um projeto de uma pessoa, menos cola é menos risco.

### Recomendação

**Começar em A (EMQX Cloud Serverless), com B como plano declarado.** Razão: o ganho que motiva a migração inteira — sair de um broker público que cai sem aviso e que aceita anônimo — vem com o gerenciado sem custo recorrente hoje, sem VPS para acordar quebrada e sem depender de domínio que ainda não existe. O free tier é medido, não imaginado: 1000 conexões simultâneas é largo para um app desktop de nicho. E a troca para self-hosted depois é uma linha de configuração no cliente (o host já vai virar variável), não uma refatoração.

Condição para ir direto em B: se no cadastro do gerenciado a auth por usuário/senha ou a ACL não estiver no plano gratuito, ou se o teto de 2000 retidas parecer apertado demais para o crescimento esperado — nesse caso o domínio precisa ser resolvido antes, porque sem TLS não há B que valha.

## 3. O requisito de ACL por sala não fecha com a arquitetura atual

O pedido foi: *"o usuário só pode publicar/assinar tópicos de servidores dos quais é membro confirmado no banco (`Prisma`)"*. **Não existe mesa de servidor nem de membro no banco.** Um servidor do PapoCall hoje é uma chave AES derivada de um código de convite que nunca foi ao backend, mais um `server_info` retido no broker publicado pelo dono (`AGENTS.md:75`). O backend que emite JWT não sabe que servidores existem, e é deliberado: é o que permite a aba de privacidade dizer que o servidor guarda o mínimo (`settings_modal.dart`, aba Privacidade; política em `public/politica-de-privacidade.html`).

Então o broker não tem como consultar "este usuário é membro desta sala?" sem que alguém responda com dado que não existe. As três saídas honestas:

| Saída | O que o broker passa a impor | O que custa |
| --- | --- | --- |
| **A. Sem roster** (autenticação + namespace próprio) | Nada de conexão anônima; cada usuário só toca `papocall/v2/u/<hash-dele>/inbox/#`, que o backend calcula a partir do nome de usuário autenticado; rate-limit por usuário. Publicar em sala alheia continua *possível*, e continua *inútil*: sem a chave a mensagem morre no MAC do destinatário. | Nada de privacidade. Zero mudança no modelo atual. |
| **B. Roster por hash opaco** | ACL real por sala: ao entrar por convite, o app informa ao backend **só o `topicIdFor(convite)`**, e o backend grava `(usuário ↔ hash)` numa mesa nova. O broker pergunta ao backend em cada publish/subscribe. | O backend passa a guardar um grafo de participação, e por hash dá para correlacionar quem está no mesmo servidor e ligar isso ao nome de usuário real. Exige atualizar a política de privacidade e a aba do app **antes** de ativar, não depois. |
| **C. Roster com o convite** | Igual a B | **Não.** Mandar o código de convite ao backend entrega a chave AES-256 e desfaz a ponta a ponta inteira. Listada só para constar. |

Recomendação: **A agora, B decidido à parte.** A entrega 80% do que motiva a migração (adeus anônimo, adeus broker público, abuso rastreado) sem tocar no modelo de privacidade que o produto afirma ao usuário. B é uma decisão de produto, não de infraestrutura, e tem um custo de comunicação (política, UI, e a conversa com quem usa).

Nota técnica que sustenta A: o hash do inbox **não é segredo** — deriva do nome de usuário (`server_crypto.dart:140`), então qualquer um que saiba um @ calcula o tópico. O que torna A valiosa não é a opacidade, é o broker saber *qual* namespace pertence a *qual* usuário autenticado e negar o resto.

## 4. O que a migração não pode quebrar

- Estrutura de tópicos e a proibição de curinga na posição do identificador (`AGENTS.md:73-74`) — a falha da v1.0.0f foi `srv/+/chat`, e o único curinga permitido continua `papocall/v2/u/<hash>/inbox/#`.
- PBKDF2 210k, AES-256-GCM, formato do payload cifrado: intocados. ACL é camada *a mais*, não substituta — o broker continua não merecendo confiança (defesa em profundidade).
- TLS obrigatório, fallback WSS, nunca texto puro — inclusive o 1883 não deve existir na configuração do broker novo.
- Nenhum segredo estático no app: a credencial MQTT vem do backend, é por sessão e expira; o binário continua sem segredo nenhum (`AGENTS.md:34-38`).
- Reconexão com backoff, `clientId` aleatório, resubscrição e reconciliação de estado: preserved, não reescritos.

## 5. Corte: o estado se refaz sozinho, e isso decide

`app_state.dart:1108-1119` mostra que, ao voltar a conectar, cada cliente reassina os tópicos, reanuncia presença, **republica o `server_info`** e **republica o snapshot de histórico de cada servidor**. Ou seja: num broker novo e vazio, a estrutura dos servidores, os canais, a presença e o histórico reaparecem assim que os membros abrem o app — porque cada um deles é a fonte da própria cópia.

O que **não** se refaz sozinho é o retido da caixa de entrada: solicitação de amizade enviada e ainda não respondida existe como mensagem retida no broker antigo (`userInboxSlotTopic`, `server_crypto.dart:149`). Perde-se o pedido pendente, não a conversa.

**Recomendação: corte direto com versão mínima obrigatória**, não os dois brokers em paralelo. O update forçado já existe e funciona pelo `public/version.json` com SHA-256 (`update_service.dart`); publicar `1.8.0` como mínima derruba os clientes antigos em uma checagem de 8 segundos depois da abertura. Paralelo com feature flag custaria publicar em dois brokers ou manter uma ponte — superfície dobrada, estado dividido ao meio, e por um problema de uma semana. Antes do corte, uma tarefa manual: quem tem pedido de amizade pendente provavelmente reenvia sozinho, e é o único dado perdível.

Se ainda assim a janela de perda incomodar, o remédio é barato e não exige paralelo: na versão nova, o app reenvia os pedidos ainda pendentes no primeiro connect (o remetente sabe quais estão pendentes).

## 6. Escopo estimado depois de escolhidas as três decisões

1. Backend: `POST /mqtt/credentials` atrás do `authMiddleware` + `POST /mqtt/acl` (webhook do broker) na saída A; +1 mesa e +1 rota se a B for escolhida. Testes dos dois no `backend/tests/`, que agora rodam em CI com Postgres efêmero.
2. Broker: auth por usuário/senha temporária, ACL, rate-limit, TLS/WSS, sem anônimo.
3. Cliente: host/porta vindos de configuração pública no padrão `PAPOCALL_API_URL`; `authenticateAs` antes do `connect()`; renovação antes do `expiresAt` junto do refresh do JWT; `server_crypto.dart` intocado.
4. `AGENTS.md`: reescrever `:70-71` (o broker deixa de ser público) mantendo `:73-77` (tópicos, retidos, curinga) e a frase sobre criptografia como camada adicional. `mqtt_service.dart:10-13` e o comentário de `server_crypto.dart:10-13` ("broker público e anônimo") precisam da mesma correção — descrever o que não é mais verdade engana quem vier.
5. Versionamento: isso é mudança de protocolo de transporte → **MINOR** com versão mínima obrigatória (`1.8.0`), não MAJOR: o formato em disco e o contrato com os payloads não mudam.
6. Site: changelog e a política, se a B for escolhida.

## 7. O que fica sem resposta até você escolher

- Se o plano gratuito do gerenciado tem auth/ACL dinâmica: só se confirma no cadastro. Sem isso, a recomendação do §2 vira self-hosted por necessidade, e o domínio passa a ser pré-requisito.
- Se você aceita o grafo de participação no backend (B) ou se a ofuscação cifrada basta (A).
- Se o `broker.emqx.io` continua acessível a versões antigas do app depois do corte — tecnicamente sim, e é isso que faz a versão mínima obrigatória ser parte do plano, não um detalhe.

---

## 8. Decisão registrada (2026-09-21) e o que ela custou de verdade

As três escolhas, feitas por quem manda no projeto:

1. **Self-hosted (EMQX 5.8 numa VPS).** Não por preferência de controle: você
   confirmou na documentação que o EMQX Cloud Serverless não tem autenticação por
   HTTP nem por JWT — só senha e certificado — e que o HiveMQ Free não tem ACL por
   tópico de nenhum tipo. O gerenciado gratuito ficou restrito a autenticar, sem
   autorizar, o que quebra o requisito 2. Isto **revoga a recomendação do §2**, que
   estava condicionada justamente a esse ponto.
2. **Roster por hash opaco** (saída B do §3).
3. **Corte direto com reenvio dos pedidos de amizade pendentes** (variante do §5).

### O que a implementação revelou além do documento

**A ACL por sala é auto-declarada, e não poderia ser diferente neste modelo.** O §3
chamou a saída B de "autorização real"; escrito assim, foi generoso demais. Para o
backend conferir que o usuário conhece um convite, ele precisaria saber o convite —
e o convite **é** a chave AES-256 da sala. O que existe, então, é: o cliente declara
o `topicIdFor(convite)`, o backend autoriza aquele prefixo. Um membro que queira
continua podendo escrever naquela sala (e hoje já consegue, sem ACL nenhuma); o que
a migração fecha de fato é a **conexão anônima**, a **leitura da caixa de entrada
alheia** e o **escritório em qualquer tópico do mundo com uma única senha**. Isso é
defesa em profundidade, não controle de acesso discricionário, e está dito em
`AGENTS.md` e nos comentários de `acl.sql` para ninguém descobrir lendo o código
tarde demais.

**A autorização não passa por webhook.** O plano pedia auth por HTTP; o broker
consulta o Postgres direto. Motivo medido: cada publish/subscribe viraria uma ida a
um Render free que acorda frio, e o sintoma de backend frio já é conhecido da tarefa
#30 — o app parece morto. No caminho quente do chat isso seria indistinguível de
pane.

**Disponibilidade ficou melhor do que o documento previa de forma não óbvia**: o
estado retido (estrutura do servidor, presença, histórico) é republicado por cada
cliente ao conectar, então um broker perdido ou recém-criado se refaz sozinho — cópia
de segurança do broker não é cópia de conversa. Está no runbook porque alguém ia
perguntar.
