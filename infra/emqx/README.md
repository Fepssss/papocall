# Broker MQTT dedicado do PapoCall

O PapoCall saiu do broker público anônimo (`broker.emqx.io`) e passou a usar um
broker próprio, com autenticação por credencial de sessão e autorização lida do
mesmo Postgres do backend. Este arquivo é o procedimento: o que provisionar, em que
ordem, e como conferir que ficou de pé antes de mexer em quem usa.

A decisão e os trade-offs estão em [`DECISAO_BROKER_MQTT.md`](../../DECISAO_BROKER_MQTT.md).

## O que existe aqui

| Arquivo | Papel |
| --- | --- |
| `emqx.conf.template` | configuração do broker, com marcadores no lugar das consultas e das credenciais do banco |
| `authn.sql` | "esta credencial existe e ainda vale?" — executado no CONNECT |
| `acl.sql` | "esta credencial pode tocar este tópico?" — executado em cada publish/subscribe |
| `render.sh` | injeta os dois SQL e o banco no template e gera `etc/emqx.conf` (gitignored) |
| `docker-compose.yml` | sobe o EMQX 5.8.6 com TLS em 8883 e WSS em 8084 |

`acl.sql` **não é cópia** da regra da aplicação: é a mesma regra, escrita à mão em
dois lugares, e é por isso que `backend/tests/mqtt-sql.test.ts` roda as duas contra
um Postgres de verdade no CI e exige que os vereditos batam caso a caso. Foi esse
teste que pegou a primeira versão do SQL autorizando `.../inboxVIZINHO` como se
estivesse dentro de `.../inbox`.

## Pré-requisito que bloqueia tudo: certificado

Sem TLS não há broker. E TLS aqui tem uma pedra específica: **o produto hoje mora
em `papocall.vercel.app`, cujo DNS é da Vercel** — não dá para emitir um certificado
Let's Encrypt para um subdomínio que você não controla. Três caminhos, do mais
simples ao mais work-already:

1. **Domínio próprio** (recomendado): registre algo como `papocall.app` e aponte um
   subdomínio `broker.…` para o IP da VPS. Aí o cert é de rotina (`certbot` com
   desafio HTTP, ou o DNS-08 do provedor).
2. **Certificado por IP** do Let's Encrypt (perfis para endereço IPv4 existem desde
   2025): funciona sem domínio, mas exige validar se a pilha `dart:io` do
   `mqtt_client` aceita o hostname-numérico — é teste, não suposição.
3. **Certificado do provedor da VPS** quando houver.

Anote o resultado no passo 6 antes de seguir. Um certificado que o app não aceita
não gera erro bonito: gera "offline" no canto da tela.

## 1. Provisionar

Uma VPS pequena (1 vCPU / 1 GB já sobra no volume atual), na **mesma região** do
Render, para o `acl.sql` não atravessar um oceano a cada mensagem. Docker +
docker compose. Não precisa de nada além das portas 8883, 8084 e 22; o painel de
administração fica preso em `127.0.0.1:18083` e se abre por túnel SSH:

```bash
ssh -L 18083:127.0.0.1:18081 usuario@vps     # painel em http://localhost:18083
```

## 2. Banco

O broker lê `mqtt_sessions` e `mqtt_grants` do mesmo Postgres do backend. Crie um
papel de só-leitura para ele — o broker não escreve nada:

```sql
CREATE ROLE papocall_broker LOGIN PASSWORD '...';
GRANT USAGE ON SCHEMA public TO papocall_broker;
GRANT SELECT ON mqtt_sessions, mqtt_grants TO papocall_broker;
```

Com isso, um credencial do broker comprometida não apaga nem forja participação: no
máximo lê o que já é visível por assinatura.

## 3. Configurar

```bash
export BANCO_HOST=... BANCO_USUARIO=papocall_broker BANCO_SENHA=... BANCO_NOME=...
export DASHBOARD_SENHA='...'
./render.sh
docker run --rm -v "$PWD/etc/emqx.conf:/opt/emqx/etc/emqx.conf:ro" \
  emqx/emqx:5.8.6 emqx check /opt/emqx/etc/emqx.conf   # precisa dizer ok antes de subir
docker compose up -d
```

Duas coisas que o `emqx check` pode reclamar e você vai querer conferir de propósito:

- **`${username}` dentro da query.** O HOCON do EMQX também interpola `${VAR}` de
  ambiente, e os placeholders das consultas usam a mesma sintaxe. Se o broker vier a
  dizer que a consulta tem um buraco, escape como `$${username}` no `.sql` — mas
  então o teste do CI precisa da mesma forma, então ajuste os dois juntos e deixe o
  teste verde primeiro.
- Os nomes exatos de chave mudam entre 5.x. Se alguma não existir na versão
  pinada, o caminho definitivo é o painel (Administration → Authentication /
  Authorization), que escreve a configuração no formato daquela build; depois
  reporte os nomes corrigidos para o template.

## 4. O que fica ligado, e por quê

- **Nada anônimo.** Existe um autenticador, e um CONNECT sem credencial ou com
  credencial que não devolve linha é recusado. Sem este item a migração inteira não
  significa nada.
- **Autorização fechada por padrão** (`no_match = deny`). No broker antigo, publicar
  era possível por omissão; aqui, publicar é possível por linha retornada.
- **Sem 1883, sem WebSocket plano.** Os dois listeners aparecem explícitos como
  desligados no template, porque "não configuramos" e "não existe" são coisas
  diferentes num arquivo que alguém vai editar daqui a um ano.
- **Freio por `ClientID`**, não por IP: atrás do NAT de um escritório todo mundo sai
  do mesmo endereço, e limite por IP puniria gente inocente.
- **`expire_at` na consulta de autenticação.** É o que dá dente ao "curta duração":
  com a sessão vencida, o CONNECT é recusado ainda que ninguém tenha apagado a linha.
  Se a sua versão do EMQX não desconectar a sessão viva ao vencer, o efeito é só
  este: a conexão estabelecida segue até reconectar. Registrar isso no passo 6 vale
  mais do que fingir que expira.

## 5. O que o broker NÃO resolve (para ninguém acreditar no contrário)

A autorização é por *declaração*: quando o app entra num servidor por convite, ele
informa ao backend o `topicIdFor(convite)` e o backend autoriza aquele prefixo. Não
existe verificação criptográfica dessa declaração, e não pode existir no modelo
atual: verificar "este usuário conhece o convite" exigiria que o backend soubesse o
convite, e o convite **é** a chave AES-256 da sala.

O que a ACL tira do atacante é o **alcance**: publicar às cegas em qualquer tópico,
e grampear/ler a caixa de entrada alheia. O que continua protegendo o conteúdo é o
AES-256-GCM — uma mensagem forjada numa sala autorizada morre na verificação de MAC
de quem recebe. As duas camadas são complementares, e nenhuma das duas existe para
substituir a outra.

## 6. Verificação, antes de encostar em usuário

Rode os cinco testes do plano de migração e anote o resultado cru, não a
impressão:

```bash
cd flutter_app
# 1 e 2. CONNECT sem credencial recusado; credencial válida aceita; caixa alheia
#        negada para leitura, liberada para escrita de pedido.
dart run tool/verify_portao.dart \
  --host broker.SEUDOMINIO --port 8883 \
  --user <mqttUsername> --pass <mqttPassword> --inbox-de-outro <hash>
# 5. os dois caminhos de transporte, cada um numa rodada:
dart run tool/verify_sync.dart --host broker.SEUDOMINIO --port 8883 ...   # TLS nativo
dart run tool/verify_sync.dart --wss  wss://broker.SEUDOMINIO:8084/mqtt ... # WSS
```

E as checagens que nenhum script cobre:

```bash
openssl s_client -connect broker.SEUDOMINIO:8883 -servername broker.SEUDOMINIO </dev/null 2>&1 | grep -E "Verify return code|not after"
mosquitto_sub -h broker.SEUDOMINIO -p 8883 -t 'papocall/v2/#'      # tem de ser recusado: sem credencial
mosquitto_sub -h broker.SEUDOMINIO -p 1883 -t 'papocall/v2/#'      # tem de recusar conexão: porta não existe
```

3. **Criptografia sem regressão**: `flutter test` com a suíte existente
   (`server_crypto_test.dart`) — o envelope não mudou de forma nenhuma.
4. **Reconexão com credencial vencida**: entre no app, marque a sessão como expirada
   no banco (`UPDATE mqtt_sessions SET expires_at = now() - interval '1 minute'`),
   derrube a conexão no painel e confirme que o app rebusca credencial e volta
   sozinho, com o chat inteiro de volta.

## 7. Monitoramento e cópia de segurança

- **Viver ou não viver**: checagem externa de TCP em 8883 a cada minuto (qualquer
  Uptime Kuma/monitor do provedor serve). O alerta que importa é "nenhuma conexão
  nova há N minutos", não "o host responde ping".
- **No painel**: conexões simultâneas, taxa de mensagens, e — o que denuncia ataque
  e bug na mesma medida — a contagem de CONNECTs recusados.
- **Cópia de segurança**: `mqtt_grants` e `mqtt_sessions` estão no Postgres, então o
  dump de rotina do banco já cobre a autorização. O estado de conversa **não precisa
  de cópia do broker**: a estrutura de cada servidor, a presença e o histórico vivem
  como mensagens retidas, mas cada membro republica a sua cópia ao reconectar
  (`_restabelecerEstadoDoMqtt`), o que torna um broker perdido um incidente de
  disponibilidade e não de dados. Documentado aqui porque é contra-intuitivo e porque
  alguém vai querer disco.
- **Standby**: nesta fase, um segundo nó não se paga. O plano é (a) o diretório
  `etc/`+`certs/` reproduzível a partir deste repositório em minutos, e (b) o corte
  poder ser desfeito religando o `MQTT_HOST` no Render (ver §9). Se um dia o
  `cluster.static` do template virar dois nós, aí sim entra réplica do banco.

## 8. Ligar no produto

1. No Render, defina `MQTT_HOST`, `MQTT_PORT=8883` e `MQTT_WSS_URL=wss://broker.SEUDOMINIO:8084/mqtt`.
   Enquanto estas variáveis estiverem vazias, o aplicativo continua usando o que foi
   embutido no build — ou seja, nada quebra por publicar o backend primeiro.
2. Passe a exigir `MQTT_HOST` em produção no `backend/src/config/env.ts` (a chave já
   existe; o comentário lá diz exatamente quando ligar isto). Este passo é o ponto
   sem retorno suave do lado do servidor: sem ele, um deploy com a variável esquecida
   manda todo mundo para um broker vazio.
3. Publique o instalador com o endereço novo embutido (`--dart-define=PAPOCALL_MQTT_HOST=…`
   — ver `installer/build_installer.ps1`, que já repassa os defines).
4. Corte: `public/version.json` com **1.8.0 mínima obrigatória**. Os clientes antigos
   continuam funcionando contra o broker público até serem forçados a subir; o
   único dado que não se refaz sozinho na troca — pedido de amizade ainda pendente —
   é reenviado pelo próprio remetente no primeiro connect da versão nova.

## 9. Voltar atrás

Reverter `MQTT_HOST` no Render para vazio e republicar o instalador anterior. O
broker público é de terceiros e continua lá; nada neste plano depende de conseguir
voltar para ele, mas é bom que a porta exista.
