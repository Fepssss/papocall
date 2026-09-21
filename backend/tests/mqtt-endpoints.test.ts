import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { AddressInfo } from 'node:net';
import { app } from '../src/app';
import { prisma } from '../src/db/prisma';
import { canUseTopic, inboxPrefixFor, presenceTopicFor, roomPrefixFor } from '../src/utils/mqttTopics';

/**
 * As rotas de credencial e de participação, contra o banco — que é onde mora o
 * perigo silencioso desta migração: autorização é a tabela que o broker lê, então
 * uma linha a mais é alguém com acesso a mais, e uma linha a menos é chat mudo.
 *
 * Roda no CI com o Postgres efêmero do workflow `backend-tests.yml`. As duas
 * suítes puras (`mqtt-acl.test.ts`) não precisam de banco e rodam em qualquer
 * lugar.
 */
const DOMINIO_FIXTURE = '@papocall.test';

let server: http.Server;
let baseUrl: string;
let contasReaisAntes = 0;

async function limparFixtures(): Promise<void> {
  const fixtures = await prisma.user.findMany({
    where: { email: { endsWith: DOMINIO_FIXTURE } },
    select: { id: true },
  });
  // Sessões e grants pendem por `onDelete: Cascade` na relação com User.
  await prisma.user.deleteMany({ where: { id: { in: fixtures.map((u) => u.id) } } });
}

async function contarContasReais(): Promise<number> {
  return prisma.user.count({ where: { NOT: { email: { endsWith: DOMINIO_FIXTURE } } } });
}

async function chamar<T = any>(
  metodo: string,
  caminho: string,
  corpo?: unknown,
  token?: string
): Promise<{ status: number; body: T }> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const resposta = await fetch(`${baseUrl}${caminho}`, {
    method: metodo,
    headers,
    body: corpo ? JSON.stringify(corpo) : undefined,
  });
  return { status: resposta.status, body: (await resposta.json()) as T };
}

/** Registra uma conta de fixture e devolve o access token dela. */
async function novaConta(email: string, username: string): Promise<string> {
  const registro = await chamar('POST', '/auth/register', {
    email,
    username,
    displayName: 'Conta de Teste',
    password: 'Password123!',
  });
  assert.equal(registro.status, 201, JSON.stringify(registro.body));
  return registro.body.data.accessToken as string;
}

async function grantsDe(userId: string, kind?: string) {
  return prisma.mqttGrant.findMany({
    where: { user_id: userId, ...(kind ? { kind } : {}) },
    select: { topic_prefix: true, kind: true },
    orderBy: { topic_prefix: 'asc' },
  });
}

// O servidor e o banco vivem pelo arquivo inteiro, não por um describe: os três
// grupos abaixo falam todos com a mesma instância, e fechar a porta no `after` do
// primeiro cancelava os testes dos outros dois com
// "test did not finish before its parent and was cancelled".
before(async () => {
  server = app.listen(0);
  const endereco = server.address() as AddressInfo;
  baseUrl = `http://127.0.0.1:${endereco.port}`;

  contasReaisAntes = await contarContasReais();
  await limparFixtures();
});

after(async () => {
  const contasReaisDepois = await contarContasReais();
  await prisma.$disconnect();
  server.close();
  if (contasReaisDepois !== contasReaisAntes) {
    throw new Error(
      `Esta suíte alterou contas reais (${contasReaisAntes} -> ${contasReaisDepois}). ` +
        'Nada aqui pode tocar em linha fora do domínio de fixture.'
    );
  }
  await limparFixtures();
});

describe('11. POST /mqtt/credentials', () => {
  let token: string;
  let userId: string;
  let accessToken: string;
  let refreshToken: string;

  before(async () => {
    const registro = await chamar('POST', '/auth/register', {
      email: 'credencial@papocall.test',
      username: '@credencial_teste',
      displayName: 'Conta de Teste',
      password: 'Password123!',
    });
    assert.equal(registro.status, 201);
    token = registro.body.data.accessToken;
    refreshToken = registro.body.data.refreshToken;
    userId = registro.body.data.user.id as string;
    accessToken = token;
  });

  it('exige sessão autenticada', async () => {
    const semToken = await chamar('POST', '/mqtt/credentials');
    assert.equal(semToken.status, 401);
    assert.equal(semToken.body.error.code, 'UNAUTHORIZED');
  });

  it('emite usuário, senha aleatória e expiração', async () => {
    const res = await chamar('POST', '/mqtt/credentials', undefined, token);
    assert.equal(res.status, 200);

    const { mqttUsername, mqttPassword, expiresAt } = res.body.data;
    // O nome no broker é a credencial, não a conta: com mais de um aparelho aberto
    // a consulta do broker teria de escolher entre várias linhas se fosse o id do
    // usuário.
    assert.notEqual(mqttUsername, userId);
    const sessao = await prisma.mqttSession.findUnique({ where: { id: mqttUsername } });
    assert.ok(sessao, 'o nome entregue tem de existir como sessão');
    assert.equal(sessao!.user_id, userId);
    assert.match(mqttPassword, /^[0-9a-f]{64}$/, '256 bits em hex');
    assert.ok(Date.parse(expiresAt) > Date.now() + 60_000);
  });

  it('a senha do broker não é nem o access token nem o refresh token da sessão', async () => {
    const res = await chamar('POST', '/mqtt/credentials', undefined, token);
    const senha = res.body.data.mqttPassword as string;
    assert.notEqual(senha, accessToken);
    assert.notEqual(senha, refreshToken);
  });

  it('guarda apenas o hash da senha, nunca o texto puro', async () => {
    const res = await chamar('POST', '/mqtt/credentials', undefined, token);
    const senha = res.body.data.mqttPassword as string;

    const linha = await prisma.mqttSession.findFirst({ where: { user_id: userId } });
    assert.ok(linha);
    assert.notEqual(linha!.password_hash, senha);
    assert.match(linha!.password_hash, /^[0-9a-f]{64}$/);
  });

  it('renovação empilha no máximo cinco credenciais vivas', async () => {
    for (let i = 0; i < 7; i++) {
      const res = await chamar('POST', '/mqtt/credentials', undefined, token);
      assert.equal(res.status, 200);
    }
    const vivas = await prisma.mqttSession.count({
      where: { user_id: userId, expires_at: { gt: new Date() } },
    });
    assert.ok(vivas <= 5, `esperava no máximo 5 credenciais vivas, há ${vivas}`);
  });

  it('grava os prefixos próprios, derivados do username real da conta', async () => {
    // A emissão é o ponto em que o backend conhece o @ atual e pode derivar.
    const grants = await grantsDe(userId);
    const prefixes = grants.map((g) => g.topic_prefix);

    assert.deepEqual(
      [...prefixes].sort(),
      [inboxPrefixFor('credencial_teste'), presenceTopicFor('credencial_teste')].sort()
    );

    // O que o broker vai responder, lido da tabela que ele lê:
    assert.equal(canUseTopic('subscribe', `${inboxPrefixFor('credencial_teste')}/#`, prefixes), true);
    assert.equal(canUseTopic('subscribe', inboxPrefixFor('outra_pessoa'), prefixes), false);
  });
});

describe('12. POST /mqtt/memberships', () => {
  let token: string;
  let userId: string;

  before(async () => {
    token = await novaConta('salas@papocall.test', '@salas_teste');
    await chamar('POST', '/mqtt/credentials', undefined, token);
    const conta = await prisma.user.findUnique({ where: { email: 'salas@papocall.test' } });
    userId = conta!.id;
  });

  it('recusa identificador que não é um hash de 32 hex', async () => {
    for (const idRuim of ['MEU-CONVITE-SEGREDO', 'abc', 'Z'.repeat(32), 'A'.repeat(32)]) {
      const res = await chamar('POST', '/mqtt/memberships', { topicIds: [idRuim] }, token);
      assert.equal(res.status, 400, `aceitou ${idRuim}`);
      assert.equal(res.body.error.code, 'VALIDATION_ERROR');
    }
    assert.equal((await grantsDe(userId, 'servidor')).length, 0);
  });

  it('aceita o identificador derivado do convite sem nunca ver o convite', async () => {
    const sala = 'c481ddda3287b011e63fef7e763eeae9'; // topicIdFor('papo-1a2b3c4d')
    const res = await chamar('POST', '/mqtt/memberships', { topicIds: [sala] }, token);
    assert.equal(res.status, 200);
    assert.deepEqual(await grantsDe(userId, 'servidor'), [
      { topic_prefix: roomPrefixFor(sala), kind: 'servidor' },
    ]);
  });

  it('substitui o conjunto: sair de uma sala tira o acesso na mesma chamada', async () => {
    const A = 'a'.repeat(32);
    const B = 'b'.repeat(32);

    await chamar('POST', '/mqtt/memberships', { topicIds: [A, B] }, token);
    let prefixes = (await grantsDe(userId, 'servidor')).map((g) => g.topic_prefix);
    assert.equal(prefixes.length, 2);
    assert.equal(canUseTopic('publish', `${roomPrefixFor(A)}/chat`, prefixes), true);

    // O app manda a lista completa que ele tem; o que sumiu da lista some do acesso.
    await chamar('POST', '/mqtt/memberships', { topicIds: [B] }, token);
    prefixes = (await grantsDe(userId, 'servidor')).map((g) => g.topic_prefix);
    assert.deepEqual(prefixes, [roomPrefixFor(B)]);
    assert.equal(canUseTopic('publish', `${roomPrefixFor(A)}/chat`, prefixes), false);
    assert.equal(canUseTopic('publish', `${roomPrefixFor(B)}/chat`, prefixes), true);
  });

  it('não deixa uma conta enxergar a sala declarada por outra', async () => {
    const sala = 'c'.repeat(32);
    await chamar('POST', '/mqtt/memberships', { topicIds: [sala] }, token);

    const outra = await novaConta('intrusa@papocall.test', '@intrusa_teste');
    await chamar('POST', '/mqtt/credentials', undefined, outra);
    const daOutra = await prisma.user.findUnique({ where: { email: 'intrusa@papocall.test' } });
    const prefixesDaOutra = (await grantsDe(daOutra!.id)).map((g) => g.topic_prefix);

    assert.equal(
      canUseTopic('subscribe', `${roomPrefixFor(sala)}/chat`, prefixesDaOutra),
      false,
      'a intrusa recebeu a sala de outra conta'
    );
  });
});

describe('13. Revogação', () => {
  it('logout de todas as sessões derruba a credencial do broker', async () => {
    const token = await novaConta('derruba@papocall.test', '@derruba_teste');
    const emitida = await chamar('POST', '/mqtt/credentials', undefined, token);
    assert.equal(emitida.status, 200);

    await chamar('POST', '/auth/logout-all', undefined, token);
    const conta = await prisma.user.findUnique({ where: { email: 'derruba@papocall.test' } });
    assert.equal(
      await prisma.mqttSession.count({ where: { user_id: conta!.id } }),
      0,
      'sair de todos os aparelhos tem de matar a credencial do MQTT'
    );
  });

  it('renomear o @ recalcula os prefixos próprios, na mesma transação da troca', async () => {
    const token = await novaConta('renomeia@papocall.test', '@renomeia_teste');
    await chamar('POST', '/mqtt/credentials', undefined, token);
    const antes = await prisma.user.findUnique({ where: { email: 'renomeia@papocall.test' } });
    const prefixesAntes = (await grantsDe(antes!.id)).map((g) => g.topic_prefix);
    assert.ok(prefixesAntes.includes(inboxPrefixFor('renomeia_teste')));

    const troca = await chamar('PATCH', '/auth/username', { newUsername: '@renomeia_agora' }, token);
    assert.equal(troca.status, 200, JSON.stringify(troca.body));

    const prefixesDepois = (await grantsDe(antes!.id)).map((g) => g.topic_prefix);
    assert.equal(
      prefixesDepois.includes(inboxPrefixFor('renomeia_teste')),
      false,
      'sobrou prefixo do @ velho, que é uma caixa onde ninguém mais entra'
    );
    assert.ok(prefixesDepois.includes(inboxPrefixFor('renomeia_agora')));
    assert.ok(prefixesDepois.includes(presenceTopicFor('renomeia_agora')));
    assert.equal(prefixesDepois.length, 2, 'só inbox e presença próprios; sala é declarada à parte');
  });
});
