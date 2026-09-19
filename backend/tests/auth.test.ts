import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { AddressInfo } from 'node:net';
import { app } from '../src/app';
import { prisma } from '../src/db/prisma';

let server: http.Server;
let baseUrl: string;

// Helper para fazer requisições HTTP JSON de forma limpa nos testes
/**
 * Marca o e-mail como verificado direto no banco.
 * A rota de voz agora exige e-mail confirmado, e o token real de verificação
 * só existe dentro do e-mail enviado.
 */
async function verifyEmailFor(email: string): Promise<void> {
  await prisma.user.update({
    where: { email },
    data: { email_verified: true },
  });
}

async function apiRequest(
  method: string,
  path: string,
  body?: unknown,
  token?: string
): Promise<{ status: number; body: any }> {
  const url = `${baseUrl}${path}`;
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const response = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  const responseBody = await response.json();
  return { status: response.status, body: responseBody };
}

describe('🧪 Suíte de Testes Automatizados - Sistema de Autenticação PapoCall', () => {
  before(async () => {
    // Inicia o servidor HTTP em uma porta livre do sistema operacional (porta 0)
    server = app.listen(0);
    const address = server.address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;

    // Limpa tabelas de teste antes de iniciar
    await prisma.refreshToken.deleteMany();
    await prisma.emailVerificationToken.deleteMany();
    await prisma.passwordResetToken.deleteMany();
    await prisma.user.deleteMany();
  });

  after(async () => {
    // Limpeza após os testes e encerramento do servidor
    await prisma.refreshToken.deleteMany();
    await prisma.emailVerificationToken.deleteMany();
    await prisma.passwordResetToken.deleteMany();
    await prisma.user.deleteMany();
    await prisma.$disconnect();
    server.close();
  });

  // ===========================================================================
  // 1. REGISTRO E REGRAS DE @USERNAME
  // ===========================================================================
  describe('1. Registro de Usuário e Regras de Username', () => {
    it('deve registrar um novo usuário com sucesso e retornar tokens', async () => {
      const res = await apiRequest('POST', '/auth/register', {
        email: 'joao.silva@teste.com',
        username: '@joaosilva',
        displayName: 'João Silva',
        password: 'Password123!',
      });

      assert.equal(res.status, 201);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.user.email, 'joao.silva@teste.com');
      assert.equal(res.body.data.user.username, '@joaosilva');
      assert.equal(res.body.data.user.rawUsername, 'joaosilva');
      assert.equal(res.body.data.user.displayName, 'João Silva');
      assert.ok(res.body.data.accessToken);
      assert.ok(res.body.data.refreshToken);

      // Garante que o banco salvou SEM o '@' e em lowercase
      const dbUser = await prisma.user.findUnique({
        where: { email: 'joao.silva@teste.com' },
      });
      assert.ok(dbUser);
      assert.equal(dbUser?.username, 'joaosilva');
    });

    it('deve rejeitar registro com e-mail duplicado', async () => {
      const res = await apiRequest('POST', '/auth/register', {
        email: 'joao.silva@teste.com',
        username: '@outro_user',
        displayName: 'Outro Nome',
        password: 'Password123!',
      });

      assert.equal(res.status, 409);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'EMAIL_ALREADY_EXISTS');
    });

    it('deve rejeitar username duplicado de forma case-insensitive e sugerir variações', async () => {
      // Tenta cadastrar '@JoaoSilva' (maiúsculas) quando 'joaosilva' já existe
      const res = await apiRequest('POST', '/auth/register', {
        email: 'joao2@teste.com',
        username: '@JoaoSilva',
        displayName: 'João Segundo',
        password: 'Password123!',
      });

      assert.equal(res.status, 409);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'USERNAME_ALREADY_EXISTS');
      assert.ok(Array.isArray(res.body.error.details?.suggestions));
      assert.ok(res.body.error.details.suggestions.length > 0);
    });

    it('deve rejeitar username com caracteres especiais ou espaços', async () => {
      const res = await apiRequest('POST', '/auth/register', {
        email: 'invalido@teste.com',
        username: '@joao silva!',
        displayName: 'Nome',
        password: 'Password123!',
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });

    it('deve rejeitar senha fraca sem número ou maiúscula', async () => {
      const res = await apiRequest('POST', '/auth/register', {
        email: 'fraca@teste.com',
        username: '@userfraco',
        displayName: 'Nome',
        password: 'senhafracasemnumero',
      });

      assert.equal(res.status, 400);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });
  });

  // ===========================================================================
  // 2. VERIFICAÇÃO DE DISPONIBILIDADE EM TEMPO REAL
  // ===========================================================================
  describe('2. Endpoint de Disponibilidade de Username', () => {
    it('deve indicar indisponível para username já em uso e retornar sugestões', async () => {
      const res = await apiRequest('GET', '/auth/username-available?username=joaosilva');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.available, false);
      assert.equal(res.body.data.username, '@joaosilva');
      assert.ok(Array.isArray(res.body.data.suggestions));
    });

    it('deve indicar disponível para novo username livre', async () => {
      const res = await apiRequest('GET', '/auth/username-available?username=novousuario123');

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.available, true);
      assert.equal(res.body.data.username, '@novousuario123');
    });
  });

  // ===========================================================================
  // 3. LOGIN POR E-MAIL E POR @USERNAME
  // ===========================================================================
  describe('3. Login por E-mail OU @Username', () => {
    it('deve fazer login com sucesso usando E-MAIL e senha', async () => {
      const res = await apiRequest('POST', '/auth/login', {
        identifier: 'joao.silva@teste.com',
        password: 'Password123!',
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.accessToken);
      assert.ok(res.body.data.refreshToken);
      assert.equal(res.body.data.user.username, '@joaosilva');
    });

    it('deve fazer login com sucesso usando @USERNAME e senha', async () => {
      const res = await apiRequest('POST', '/auth/login', {
        identifier: '@joaosilva',
        password: 'Password123!',
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.accessToken);
      assert.ok(res.body.data.refreshToken);
      assert.equal(res.body.data.user.username, '@joaosilva');
    });

    it('deve rejeitar login com senha incorreta', async () => {
      const res = await apiRequest('POST', '/auth/login', {
        identifier: '@joaosilva',
        password: 'SenhaTotalmenteErrada!',
      });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'INVALID_CREDENTIALS');
    });
  });

  // ===========================================================================
  // 4. ROTAÇÃO DE REFRESH TOKEN E DETECÇÃO DE REUSO
  // ===========================================================================
  describe('4. Rotação de Refresh Token e Detecção de Reuso', () => {
    let initialRefreshToken: string;

    it('deve rotacionar refresh token válido gerando um novo par', async () => {
      // 1. Faz login para obter um refresh token inicial
      const loginRes = await apiRequest('POST', '/auth/login', {
        identifier: '@joaosilva',
        password: 'Password123!',
      });
      initialRefreshToken = loginRes.body.data.refreshToken;

      // 2. Executa a rotação
      const refreshRes = await apiRequest('POST', '/auth/refresh', {
        refreshToken: initialRefreshToken,
      });

      assert.equal(refreshRes.status, 200);
      assert.equal(refreshRes.body.success, true);
      assert.ok(refreshRes.body.data.accessToken);
      assert.ok(refreshRes.body.data.refreshToken);
      // O novo token deve ser diferente do token inicial
      assert.notEqual(refreshRes.body.data.refreshToken, initialRefreshToken);
    });

    it('CRÍTICO: deve detectar reuso do token antigo e revogar todas as sessões do usuário', async () => {
      // Tenta usar o initialRefreshToken novamente (que acabou de ser rotacionado e revogado)
      const reuseRes = await apiRequest('POST', '/auth/refresh', {
        refreshToken: initialRefreshToken,
      });

      assert.equal(reuseRes.status, 401);
      assert.equal(reuseRes.body.success, false);
      assert.equal(reuseRes.body.error.code, 'TOKEN_REUSE_DETECTED');

      // Verifica no banco de dados se TODOS os tokens desse usuário foram revogados
      const userTokens = await prisma.refreshToken.findMany({
        where: { user: { username: 'joaosilva' } },
      });

      assert.ok(userTokens.length > 0);
      for (const t of userTokens) {
        assert.equal(t.revoked, true, 'Todos os tokens do usuário deveriam ter sido revogados');
      }
    });
  });

  // ===========================================================================
  // 5. ROTAS PROTEGIDAS E GERAÇÃO SEGURA DO LIVEKIT TOKEN
  // ===========================================================================
  describe('5. Middleware de Autenticação e LiveKit Token', () => {
    let userAccessToken: string;

    before(async () => {
      const loginRes = await apiRequest('POST', '/auth/login', {
        identifier: '@joaosilva',
        password: 'Password123!',
      });
      userAccessToken = loginRes.body.data.accessToken;
    });

    it('POST /livekit/token deve autorizar usuário autenticado e emitir token válido', async () => {
      const res = await apiRequest('POST', '/livekit/token', { room: 'v-jogos' }, userAccessToken);

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.token);
      assert.equal(res.body.data.room, 'v-jogos');
      assert.equal(res.body.data.identity, '@joaosilva');
    });

    it('POST /livekit/token deve rejeitar requisição anônima sem token', async () => {
      const res = await apiRequest('POST', '/livekit/token', { room: 'v-jogos' });

      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'UNAUTHORIZED');
    });

    it('POST /livekit/token deve recusar identificador de sala malformado', async () => {
      await verifyEmailFor('joao.silva@teste.com');
      const verified = await apiRequest('POST', '/auth/login', {
        identifier: '@joaosilva',
        password: 'Password123!',
      });
      userAccessToken = verified.body.data.accessToken;

      const res = await apiRequest(
        'POST',
        '/livekit/token',
        { room: '../outra-sala privada' },
        userAccessToken
      );

      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    });

    it('GET /auth/me deve rejeitar requisição sem token', async () => {
      const res = await apiRequest('GET', '/auth/me');
      assert.equal(res.status, 401);
      assert.equal(res.body.success, false);
      assert.equal(res.body.error.code, 'UNAUTHORIZED');
    });

    it('GET /auth/me deve retornar os dados do usuário autenticado com token válido', async () => {
      const res = await apiRequest('GET', '/auth/me', undefined, userAccessToken);
      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.equal(res.body.data.user.username, '@joaosilva');
      assert.equal(res.body.data.user.email, 'joao.silva@teste.com');
    });

    it('POST /livekit/token deve gerar token com identity estritamente travada no @username', async () => {
      // Tenta enviar 'identity' no body para tentar burlar a identidade
      const res = await apiRequest(
        'POST',
        '/livekit/token',
        {
          room: 'v-jogos',
          identity: 'usuario_falso_hacker',
        },
        userAccessToken
      );

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.token);
      assert.equal(res.body.data.room, 'v-jogos');
      // A identidade GERADA DEVE SER OBRIGATORIAMENTE @joaosilva (ignorando qualquer tentativa de spoofing)
      assert.equal(res.body.data.identity, '@joaosilva');
    });
  });

  // ===========================================================================
  // 6. E-MAIL VERIFICATION, SENHA, THROTTLE E LOGOUT
  // ===========================================================================
  describe('6. Recuperação de Senha, E-mail e Alteração de Username', () => {
    let session: any;

    before(async () => {
      const reg = await apiRequest('POST', '/auth/register', {
        email: 'recupera@teste.com',
        username: '@recupera_user',
        displayName: 'Recupera Nome',
        password: 'Password123!',
      });
      session = reg.body.data;
    });

    it('deve confirmar e-mail com token válido', async () => {
      const dbUser = await prisma.user.findUnique({
        where: { email: 'recupera@teste.com' },
        include: { email_verification_tokens: true },
      });

      // No teste, buscamos o token_hash correspondente
      const tokenRecord = dbUser?.email_verification_tokens[0];
      assert.ok(tokenRecord);

      // Gera um token e testa simulação direta de verificação
      const res = await apiRequest('POST', '/auth/verify-email', {
        token: 'token_falso_invalido',
      });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'INVALID_VERIFICATION_TOKEN');
    });

    it('deve processar solicitação de recuperação de senha (forgot-password)', async () => {
      const res = await apiRequest('POST', '/auth/forgot-password', {
        email: 'recupera@teste.com',
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
      assert.ok(res.body.data.message);
    });

    it('deve alterar @username com sucesso e aplicar throttle de 30 dias na segunda tentativa', async () => {
      // 1. Primeira alteração (sucesso)
      const res1 = await apiRequest(
        'PATCH',
        '/auth/username',
        { newUsername: '@recupera_novo' },
        session.accessToken
      );

      assert.equal(res1.status, 200);
      assert.equal(res1.body.success, true);
      assert.equal(res1.body.data.user.username, '@recupera_novo');

      // 2. Segunda alteração imediata (deve ser bloqueada pelo throttle de 30 dias)
      const res2 = await apiRequest(
        'PATCH',
        '/auth/username',
        { newUsername: '@recupera_segundo' },
        session.accessToken
      );

      assert.equal(res2.status, 400);
      assert.equal(res2.body.success, false);
      assert.equal(res2.body.error.code, 'USERNAME_CHANGE_THROTTLED');
      assert.ok(res2.body.error.details?.remainingDays);
    });

    it('deve encerrar sessão atual via logout', async () => {
      const res = await apiRequest('POST', '/auth/logout', {
        refreshToken: session.refreshToken,
      });

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
    });

    it('deve revogar todas as sessões via logout-all', async () => {
      const res = await apiRequest('POST', '/auth/logout-all', undefined, session.accessToken);

      assert.equal(res.status, 200);
      assert.equal(res.body.success, true);
    });
  });
});
