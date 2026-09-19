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
   - É um serviço Express + Prisma que hoje só roda local.
   - Precisa ficar acessível por HTTPS e responder em /auth/* e /livekit/token.
   - Definir as variáveis de ambiente conforme backend/.env.example.
   - Em produção o serviço se recusa a subir sem SMTP_HOST e com credenciais de
     exemplo — isso é intencional (ver backend/src/config/env.ts).
   - Trocar o provider do Prisma de sqlite para postgresql em produção
     (backend/prisma/schema.prisma ainda está fixo em sqlite).

3. Apontar o app para o backend publicado.
   - A URL vem do build: --dart-define=PAPOCALL_API_URL=<url-do-backend>
   - O installer/build_installer.ps1 lê PAPOCALL_API_URL do .env; basta definir
     lá e rodar o build.
   - NUNCA passe LIVEKIT_API_KEY ou LIVEKIT_API_SECRET para o build. O script
     aborta se encontrar credencial no pacote; não remova essa trava.

4. Configurar a função serverless de voz na Vercel.
   - Definir JWT_PUBLIC_KEY (a mesma chave pública do backend), LIVEKIT_URL,
     LIVEKIT_API_KEY, LIVEKIT_API_SECRET e CORS_ORIGINS nas variáveis do projeto.
   - api/livekit-token.js valida o JWT com essa chave pública.

5. Configurar SMTP de produção para verificação de e-mail e recuperação de senha.

6. Assinar o instalador (code signing). Continua sem assinatura: o SmartScreen
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
| Banco em produção | SQLite (deveria ser PostgreSQL) |
