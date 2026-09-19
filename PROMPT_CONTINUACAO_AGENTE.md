# Prompt de Continuação — Finalizar a Atualização de Segurança v1.0.0g

> Cole o bloco abaixo como primeira mensagem para o próximo agente.
> Contexto completo do que já foi feito: `SECURITY_UPDATE_v1.0.0g.md`.

---

## PROMPT

```
Você está continuando o trabalho no PapoCall (C:\Users\User\Documents\Projeto 1).

Leia PRIMEIRO estes dois arquivos, nesta ordem:
1. AGENTS.md — regras obrigatórias do projeto (versionamento, idioma pt-BR,
   autor dos commits, e as novas invariantes de segurança).
2. SECURITY_UPDATE_v1.0.0g.md — o que foi corrigido na auditoria de segurança
   e por quê. A seção 6 lista invariantes que NÃO podem ser quebradas.

CONTEXTO
A v1.0.0g foi publicada (commit 7bd51d8) e corrigiu 4 vulnerabilidades críticas
e várias altas. Nessa correção, dois fallbacks inseguros foram REMOVIDOS de
propósito:
- o "cofre local" que autenticava o usuário dentro do próprio app;
- a assinatura do token do LiveKit feita no cliente com o segredo da API.

Consequência esperada e conhecida: o aplicativo agora DEPENDE de um backend real.
Enquanto o backend não estiver publicado, login e voz não funcionam. Isso não é
um bug a ser "consertado" reintroduzindo fallback — é o comportamento correto.

SEU TRABALHO (nesta ordem de prioridade)

1. BLOQUEANTE — Confirmar com o dono do projeto se as credenciais do LiveKit já
   foram rotacionadas no painel da LiveKit Cloud. O segredo antigo vazou dentro
   do instalador publicado até a v1.0.0f e deve ser considerado comprometido.
   Não prossiga com nada de voz antes disso.

2. Publicar o backend de autenticação (pasta backend/).

   DECISÃO JÁ TOMADA PELO DONO DO PROJETO — ambiente de TESTE, opção gratuita:
     - Aplicação: Render, Web Service no plano free.
     - Banco: Neon, PostgreSQL no plano free.
   Não troque essa stack por conta própria. Se precisar mudar, pergunte antes.

   POR QUE NÃO SERVERLESS (Vercel/Lambda) — não "simplifique" movendo para lá:
     - O rate limiter é um Map na memória do processo
       (backend/src/middlewares/rate-limiter.middleware.ts). Em serverless cada
       instância tem o seu e elas nascem e morrem o tempo todo, então o limite
       de 5 tentativas de login por IP deixa de existir na prática e a proteção
       contra força bruta some.
     - O Argon2id usa @node-rs/argon2, que é módulo NATIVO e aloca 19 MB por
       hash. Isso briga com cold start, limite de tempo e empacotamento de
       função serverless.
     - O Render free roda um container real e de instância única, então os dois
       pontos acima continuam funcionando como projetado.

   POR QUE NEON E NÃO O POSTGRES DO PRÓPRIO RENDER:
     - O banco gratuito do Render expira depois de alguns meses e forçaria uma
       migração no meio dos testes. O free do Neon persiste.

   PASSO A PASSO:
   a) Criar o projeto no Neon e copiar a connection string (formato
      postgresql://user:senha@host/db?sslmode=require).
   b) Em backend/prisma/schema.prisma, trocar o provider do datasource de
      "sqlite" para "postgresql". O comentário no topo do arquivo já promete
      suporte a Postgres; hoje o provider está fixo em sqlite.
   c) Rodar as migrations contra o Neon (npx prisma migrate deploy, ou
      prisma db push se ainda não houver migrations versionadas).
   d) Criar o Web Service no Render apontando para este repositório:
        Root Directory: backend
        Build Command:  npm install && npx prisma generate && npm run build
        Start Command:  npm start
   e) Definir as variáveis de ambiente no Render, conforme backend/.env.example:
        NODE_ENV=production
        DATABASE_URL=<connection string do Neon>
        JWT_PRIVATE_KEY / JWT_PUBLIC_KEY  (par RSA 2048, gerar com openssl)
        LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET  (após a rotação)
        SMTP_HOST / SMTP_PORT / SMTP_USER / SMTP_PASS
        CORS_ORIGINS=https://papocall.vercel.app
        FRONTEND_URL=https://papocall.vercel.app
      Em produção o serviço ABORTA na inicialização se SMTP_HOST estiver vazio
      ou se as credenciais do LiveKit forem os valores de exemplo. Isso é
      intencional (backend/src/config/env.ts) — não remova essa validação,
      configure as variáveis.
   f) Confirmar que https://<servico>.onrender.com/health responde 200.

3. Tratar a hibernação do plano gratuito no cliente.

   DECISÃO JÁ TOMADA: aquecer o backend na tela de login. NÃO aumentar o
   timeout do cliente.

   PROBLEMA: o Web Service free do Render hiberna após ~15 minutos ocioso e leva
   perto de 50 segundos para voltar. O cliente tem timeout de 15 segundos em
   login e registro (flutter_app/lib/services/auth_service.dart), então o
   primeiro login depois de um período parado FALHA por timeout e parece bug do
   app quando é só o servidor acordando.

   POR QUE NÃO SIMPLESMENTE AUMENTAR O TIMEOUT PARA 60s: isso degradaria a
   experiência real em produção, onde esperar 60 segundos por um login não
   deveria ser aceitável. O timeout de 15s é o valor correto para o produto.

   O QUE FAZER:
   - Ao abrir a tela de login (flutter_app/lib/screens/auth_screen.dart), disparar
     AuthService.isBackendReachable(), que já existe e chama /health.
   - Enquanto não responder, mostrar um estado visível de "conectando ao
     servidor..." e manter o botão de entrar desabilitado, para o usuário
     entender que a espera é do servidor acordando e não travamento do app.
   - Se o /health falhar, exibir mensagem clara de servidor indisponível em vez
     de deixar o usuário tentar logar e tomar erro de timeout.
   - O timeout de isBackendReachable() hoje é 5s; para cobrir o cold start ele
     precisa ser maior (algo em torno de 60s) OU ser repetido em tentativas
     sucessivas. Ajuste APENAS o health check — os timeouts de login e registro
     continuam em 15s.

4. Apontar o app para o backend publicado.
   - A URL vem do build: --dart-define=PAPOCALL_API_URL=https://<servico>.onrender.com
   - O installer/build_installer.ps1 lê PAPOCALL_API_URL do .env; basta definir
     lá e rodar o build.
   - NUNCA passe LIVEKIT_API_KEY ou LIVEKIT_API_SECRET para o build. O script
     aborta se encontrar credencial no pacote; não remova essa trava.

5. Configurar a função serverless de voz na Vercel.
   - Definir JWT_PUBLIC_KEY (a MESMA chave pública usada no backend do Render),
     LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET e CORS_ORIGINS nas
     variáveis do projeto.
   - api/livekit-token.js valida o JWT com essa chave pública. Se as chaves não
     baterem, todo pedido de voz responde 401.

6. Configurar SMTP de produção para verificação de e-mail e recuperação de senha.
   Obrigatório: sem isso o backend não sobe.

7. Assinar o instalador (code signing). Continua sem assinatura: o SmartScreen
   alerta o usuário e não há garantia de integridade na distribuição.

TESTE DE ACEITE
Depois de publicar o backend, validar de ponta a ponta:
- registrar uma conta pelo app e receber o e-mail de verificação;
- fazer login e reabrir o app confirmando que a sessão persiste
  (%APPDATA%\PapoCall\session.dat deve existir e NÃO ser legível como texto);
- confirmar o e-mail e entrar em uma sala de voz;
- verificar que entrar na voz SEM e-mail confirmado retorna EMAIL_NOT_VERIFIED;
- trocar mensagens entre dois clientes no mesmo servidor;
- confirmar que um cliente em outro servidor NÃO recebe essas mensagens.

TESTE ESPECÍFICO DO COLD START (não pule, é o ponto fraco do plano gratuito):
- deixar o backend ocioso por mais de 15 minutos até hibernar;
- abrir o app e conferir que a tela de login mostra "conectando ao servidor",
  espera o serviço acordar e SÓ ENTÃO libera o botão de entrar;
- confirmar que o login seguinte funciona na primeira tentativa, sem erro de
  timeout e sem o usuário precisar tentar duas vezes.

ANTES DE TERMINAR
Rodar e deixar tudo verde:
  cd backend && npm test
  cd flutter_app && flutter analyze && flutter test

Observação: flutter_app/test/widget_test.dart já falhava antes desta auditoria
(o smoke test monta PapoCallApp sem o Provider<AppState> acima dele). Não é
regressão da v1.0.0g. Corrija envolvendo o widget no provider, ou remova o teste
se ele não agrega.

Seguir as regras do AGENTS.md ao final: sincronizar a versão em todos os
arquivos, regerar o instalador, e commitar/pushar como Feps <fepsmiotti@gmail.com>.

O QUE NÃO FAZER
- Não reintroduzir autenticação local, "modo offline" ou qualquer fallback que
  aceite login sem o backend.
- Não voltar a assinar token do LiveKit no cliente.
- Não embutir segredo algum no binário Flutter.
- Não publicar nada em texto puro no MQTT nem assinar tópico com curinga.
- Não gravar token ou senha em texto puro no disco.
- Não mover o backend para função serverless (o rate limiter e o Argon2id
  dependem de processo persistente e instância única).
- Não aumentar os timeouts de login e registro para mascarar o cold start.
- Não commitar a connection string do Neon nem as chaves RSA. Elas vivem nas
  variáveis de ambiente do Render; o .env é ignorado pelo Git e há gitleaks no
  pre-commit e na CI.
```

---

## Referência rápida do estado atual

| Item | Situação |
|---|---|
| Credenciais do LiveKit | **Comprometidas** — aguardando rotação manual |
| Instalador publicado | Limpo (v1.0.0g), sem segredos |
| App Flutter | Publicado, depende de backend |
| Backend de autenticação | **Não publicado** — bloqueia login e voz |
| Função `api/livekit-token.js` | Publicada, aguardando `JWT_PUBLIC_KEY` |
| SMTP | Não configurado |
| Assinatura do instalador | Ausente |
| Banco | SQLite no código; migrar para PostgreSQL no Neon |

## Decisões de infraestrutura já tomadas

Registradas aqui para o próximo agente não reabrir a discussão:

| Decisão | Escolha | Motivo |
|---|---|---|
| Hospedagem do backend (teste) | **Render — Web Service free** | Container real e de instância única: o módulo nativo do Argon2id funciona e o rate limiter em memória continua válido |
| Banco (teste) | **Neon — PostgreSQL free** | O Postgres gratuito do Render expira e forçaria migração no meio dos testes |
| Serverless para o backend | **Descartado** | Quebraria o rate limiter de força bruta e é hostil ao Argon2id |
| Hibernação do plano free | **Aquecer via `/health` na tela de login** | Mantém o timeout de 15s correto para produção em vez de degradá-lo para 60s |

Se o projeto sair de teste para uso real, reavaliar: Railway ou Fly.io (que tem
região em São Paulo) eliminam a hibernação por poucos dólares ao mês.
