# Backend de autenticação do PapoCall

Express 5 + Prisma 6 sobre PostgreSQL, com Argon2id, JWT RS256 e emissão do
`Access Token` da LiveKit. É o único lugar do projeto que guarda segredo:
o aplicativo Flutter recebe o token de voz desta API e nada além disso.

Em produção roda no Render, apontado para o Neon. `src/config/env.ts` aborta a
inicialização se uma credencial obrigatória vier com o valor de exemplo — por
isso os testes abaixo rodam com `NODE_ENV=test`, onde esses defaults são aceitos.

## Scripts

| Comando | O que faz |
| --- | --- |
| `npm run dev` | `tsx watch src/server.ts` |
| `npm run build` | `prisma generate && tsc` |
| `npm start` | `node dist/server.js` |
| `npm test` | `cross-env NODE_ENV=test tsx --test tests/**/*.test.ts` |
| `npm run prisma:generate` | gera o cliente Prisma |
| `npm run prisma:push` | `prisma db push` contra o `DATABASE_URL` do ambiente |

Não há `prisma migrate`: o schema é aplicado com `db push`, e é isso que o CI
faz também.

## Rodando a suíte de testes nesta máquina

Os testes sobem o `app` Express numa porta aleatória e falam HTTP com ele, então
precisam de um Postgres. Use o container descartável — não o banco de produção.

O motivo é histórico: até a v1.0.0q o `before`/`after` do `tests/auth.test.ts`
faziam `user.deleteMany()` sem filtro. Rodar `npm test` com o `.env` do
Render/Neon aberto apagava todas as contas cadastradas. Hoje a suíte só apaga
linhas do domínio reservado `@papocall.test` (RFC 2606) e o `after` falha se o
total de contas reais mudou — mas continuar apontando o `DATABASE_URL` para o
banco operacional é a última linha de defesa sendo a primeira.

### 1. Subir o banco

```bash
cd backend
docker compose -f docker-compose.test.yml up -d
```

### 2. Exportar as variáveis

O `dotenv` do `src/config/env.ts` não sobrescreve o que já está no ambiente,
então exportar aqui tem prioridade sobre o `.env` — que é justamente o que se
quer, porque o `.env` local aponta para o Neon. `backend/.env.test.example`
documenta cada campo e por que o resto fica de fora.

PowerShell:

```powershell
$env:NODE_ENV = "test"
$env:DATABASE_URL = "postgresql://papocall:papocall@localhost:5433/papocall_test?schema=public"
$env:TEST_DATABASE_URL = $env:DATABASE_URL
```

bash / zsh:

```bash
export NODE_ENV=test
export DATABASE_URL="postgresql://papocall:papocall@localhost:5433/papocall_test?schema=public"
export TEST_DATABASE_URL="$DATABASE_URL"
```

### 3. Aplicar o schema e rodar

```bash
npm ci
npx prisma generate
npx prisma db push   # com o DATABASE_URL exportado acima, nunca com o do .env
npm test
```

Para derrubar o banco e apagar os dados:

```bash
docker compose -f docker-compose.test.yml down -v
```

### O que a suíte cobre

- `tests/auth.test.ts` — registro e regras de `@username` (case-insensitive,
  sugestões de variação), disponibilidade em tempo real, login por e-mail **ou**
  `@username`, senha fraca rejeitada, rotação de refresh token, **detecção de
  reuso com revogação em cascata**, middleware de autenticação, `identity` do
  token LiveKit travada no usuário (tentativa de spoofing), throttle de 30 dias
  para troca de username, logout e logout-all.
- `tests/security.test.ts` — os `.env.example` da raiz e do backend não podem
  conter chave nem secret reais; os valores atribuídos passam por um corte de
  entropia de Shannon.
- `tests/mqtt-acl.test.ts` — a regra de autorização do broker, sem banco: os
  vetores de hash vêm da implementação Dart, e a tabela de verdade percorre caso
  a caso o que é permitido negado (ler a caixa alheia é o caso principal).
- `tests/mqtt-endpoints.test.ts` — `/mqtt/credentials` e `/mqtt/memberships`
  contra o banco: só hash da senha no disco, teto de credenciais vivas, substituição
  do conjunto de salas, revogação no logout-all e recálculo dos prefixos na troca
  de `@`.

O `npm test` roda com `--test-concurrency=1`. Não é detalhe de performance: o
`node --test` paraleliza **arquivos**, e as duas suítes que falam com o banco
compartilham o mesmo Postgres — a limpeza por domínio de uma apaga as contas que a
outra está usando no meio, e o resultado é um P2003 que não tem nada a ver com o
código testado.

## O que roda no CI

| Workflow | Quando | O que faz |
| --- | --- | --- |
| `.github/workflows/backend-tests.yml` | PR e push em `main` | o passo a passo acima, com `postgres:16-alpine` como serviço e par RSA gerado no próprio job |
| `.github/workflows/flutter-tests.yml` | PR e push em `main` | `flutter pub get`, `flutter analyze`, `flutter test` em `flutter_app/` |
| `.github/workflows/secret-scan.yml` | PR e push em `main` | gitleaks |

Nenhum dos dois usa credencial de produção. O job do Flutter, em particular, não
tem secret nenhum porque o aplicativo também não tem.

## Verificação do envio de e-mail

Fora de produção, sem `SMTP_HOST`, o `src/utils/email.ts` imprime o link no
console em vez de entregar — é o que faz a suíte de testes rodar sem SMTP.

Para conferir o transporte real, `scripts/verificar-envio-email.ts` chama o
`emailService` de verdade contra um servidor SMTP público de teste (Ethereal,
STARTTLS na 587) e ainda compõe os bytes RFC 822 que seriam entregues:

```bash
DATABASE_URL="postgresql://papocall:papocall@localhost:5433/papocall_test?schema=public" \
  npx tsx scripts/verificar-envio-email.ts
```

Ele imprime a resposta do servidor (`250 Accepted`) e confere assunto,
destinatário, rota e token na mensagem. Os tokens que ele usa são fictícios
(`DEADBEEF`/`CAFEBABE`), mas o output mostra links com token em texto puro: é um
script de desenvolvimento, rode assim com essa consciência.
