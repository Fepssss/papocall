import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { prisma } from '../src/db/prisma';
import {
  canUseTopic,
  inboxPrefixFor,
  presenceTopicFor,
  roomPrefixFor,
  topicIdFor,
} from '../src/utils/mqttTopics';
import { generateRandomToken, hashToken } from '../src/utils/token';

/**
 * O SQL que o broker executa, contra um Postgres de verdade.
 *
 * POR QUE TESTAR O ARQUIVO E NÃO UMA CÓPIA: `infra/emqx/acl.sql` é a regra que
 * decide quem publica e quem assina. A aplicação tem a regra correspondente em
 * `src/utils/mqttTopics.ts`. Duas transcrições à mão da mesma política divergem, e
 * a divergência de segurança aparece como o pior tipo de bug: silêncio. Então este
 * arquivo lê o SQL do disco, roda cada caso e exige que o veredito bata com a
 * predicate de referência — caso a diferença apareça, quem quebra é o teste, não o
 * chat de quem está online.
 *
 * Roda no CI, onde o Postgres existe. Sem banco, o arquivo inteiro é pulado.
 */

type Acao = 'publish' | 'subscribe';

function lerSql(nome: string): string {
  const caminho = path.resolve(__dirname, '..', '..', 'infra', 'emqx', nome);
  return fs.readFileSync(caminho, 'utf8');
}

/** Troca `${chave}` por `$n`, na ordem de aparecimento, e devolve os valores. */
function parametrizar(
  sql: string,
  valores: Record<string, unknown>
): { corpo: string; params: unknown[] } {
  const ordem: string[] = [];
  const corpo = sql.replace(/\$\{(\w+)\}/g, (_todo, chave: string) => {
    if (!(chave in valores)) throw new Error(`placeholder desconhecido: ${chave}`);
    if (!ordem.includes(chave)) ordem.push(chave);
    return `$${ordem.indexOf(chave) + 1}`;
  });
  return { corpo, params: ordem.map((chave) => valores[chave]) };
}

const dono = 'sql_acl_teste';
const outra = 'sql_intrusa';
const salaConhecida = topicIdFor('papo-1a2b3c4d');
const salaDesconhecida = 'f'.repeat(32);

function slotInbox(destinatario: string, remetente: string): string {
  return `${inboxPrefixFor(destinatario)}/${topicIdFor(`inboxslot:${remetente}`)}`;
}

const TOPICOS: string[] = [
  inboxPrefixFor(dono),
  `${inboxPrefixFor(dono)}/#`,
  slotInbox(dono, outra),
  `${inboxPrefixFor(dono)}vizinho`,
  presenceTopicFor(dono),
  inboxPrefixFor(outra),
  `${inboxPrefixFor(outra)}/#`,
  slotInbox(outra, dono),
  `${slotInbox(outra, dono)}/extra`,
  presenceTopicFor(outra),
  `${presenceTopicFor(outra)}/#`,
  roomPrefixFor(salaConhecida),
  `${roomPrefixFor(salaConhecida)}/chat`,
  `${roomPrefixFor(salaConhecida)}/history/${topicIdFor('slot')}`,
  `${roomPrefixFor(salaDesconhecida)}/chat`,
  '$SYS/broker/uptime',
  'papocall/v2/r/nao-e-hash/chat',
  '',
];

let userId: string;
let nomeDaCredencial: string;
let senhaDaCredencial: string;
let prefixosDoDono: string[] = [];

async function consultarAcl(acao: Acao, topico: string, username = nomeDaCredencial): Promise<boolean> {
  const { corpo, params } = parametrizar(lerSql('acl.sql'), { username, topic: topico, action: acao });
  const linhas = await prisma.$queryRawUnsafe<unknown[]>(corpo, ...params);
  return linhas.length > 0;
}

describe('14. O SQL do broker decide o mesmo que a aplicação', () => {
  before(async () => {
    const usuario = await prisma.user.create({
      data: {
        email: 'sqlacl@papocall.test',
        username: dono,
        display_name: 'Fixture do SQL',
        password_hash: 'nao-é-usado-aqui',
      },
    });
    userId = usuario.id;

    senhaDaCredencial = generateRandomToken(32);
    const sessao = await prisma.mqttSession.create({
      data: {
        user_id: userId,
        password_hash: hashToken(senhaDaCredencial),
        expires_at: new Date(Date.now() + 60 * 60 * 1000),
      },
    });
    nomeDaCredencial = sessao.id;

    await prisma.mqttGrant.createMany({
      data: [
        { user_id: userId, topic_prefix: inboxPrefixFor(dono), kind: 'inbox' },
        { user_id: userId, topic_prefix: presenceTopicFor(dono), kind: 'presenca' },
        { user_id: userId, topic_prefix: roomPrefixFor(salaConhecida), kind: 'servidor' },
      ],
    });

    prefixosDoDono = (
      await prisma.mqttGrant.findMany({ where: { user_id: userId }, select: { topic_prefix: true } })
    ).map((g) => g.topic_prefix);
  });

  after(async () => {
    // Só a fixture desta suíte; as contas reais não passam por aqui.
    if (userId) await prisma.user.delete({ where: { id: userId } });
    await prisma.$disconnect();
  });

  it('percorre cada tópico nos dois sentidos, com a credencial viva', async () => {
    const divergentes: string[] = [];

    for (const topico of TOPICOS) {
      for (const acao of ['publish', 'subscribe'] as Acao[]) {
        const peloSql = await consultarAcl(acao, topico);
        const pelaAplicacao = canUseTopic(acao, topico, prefixosDoDono);
        if (peloSql !== pelaAplicacao) {
          divergentes.push(`${acao} ${topico || '(vazio)'}: sql=${peloSql} app=${pelaAplicacao}`);
        }
      }
    }

    assert.deepEqual(divergentes, [], 'o SQL do broker e a regra da aplicação divergem');
  });

  it('nega tudo quando a credencial expirou, mesmo com os grants no lugar', async () => {
    await prisma.mqttSession.update({
      where: { id: nomeDaCredencial },
      data: { expires_at: new Date(Date.now() - 1000) },
    });

    // O caso que importa: a caixa própria, que estava liberada um teste acima.
    assert.equal(await consultarAcl('subscribe', `${inboxPrefixFor(dono)}/#`), false);
    assert.equal(await consultarAcl('publish', slotInbox(outra, dono)), false);
  });

  it('nega tudo para um nome de credencial que não existe', async () => {
    await prisma.mqttSession.update({
      where: { id: nomeDaCredencial },
      data: { expires_at: new Date(Date.now() + 60 * 60 * 1000) },
    });

    assert.equal(await consultarAcl('subscribe', `${inboxPrefixFor(dono)}/#`, 'credencial-inventada'), false);
    assert.equal(await consultarAcl('publish', slotInbox(outra, dono), 'credencial-inventada'), false);
  });

  it('uma segunda conta não recebe nada do que a primeira declarou', async () => {
    const intrusa = await prisma.user.create({
      data: {
        email: 'sqlintrusa@papocall.test',
        username: outra,
        display_name: 'Fixture Intrusa',
        password_hash: 'nao-é-usado-aqui',
      },
    });

    try {
      const senha = generateRandomToken(32);
      const sessao = await prisma.mqttSession.create({
        data: {
          user_id: intrusa.id,
          password_hash: hashToken(senha),
          expires_at: new Date(Date.now() + 60 * 60 * 1000),
        },
      });

      const grants = (
        await prisma.mqttGrant.findMany({ where: { user_id: intrusa.id }, select: { topic_prefix: true } })
      ).map((g) => g.topic_prefix);

      assert.equal(await consultarAcl('subscribe', `${inboxPrefixFor(dono)}/#`, sessao.id), false);
      assert.equal(await consultarAcl('subscribe', `${roomPrefixFor(salaConhecida)}/chat`, sessao.id), false);
      // mas continua podendo escrever na caixa do outro, que é o caminho do pedido
      assert.equal(await consultarAcl('publish', slotInbox(dono, outra), sessao.id), true);
      assert.equal(canUseTopic('publish', slotInbox(dono, outra), grants), true);
    } finally {
      await prisma.user.delete({ where: { id: intrusa.id } });
    }
  });

  describe('autenticação, com a mesma credencial viva', () => {
    it('devolve o hash guardado para a credencial certa', async () => {
      const { corpo, params } = parametrizar(lerSql('authn.sql'), { username: nomeDaCredencial });
      const linhas = await prisma.$queryRawUnsafe<Array<Record<string, unknown>>>(corpo, ...params);

      assert.equal(linhas.length, 1);
      assert.equal(linhas[0].password_hash, hashToken(senhaDaCredencial));
      assert.equal(linhas[0].salt, '');
    });

    it('não devolve linha nenhuma para nome de credencial desconhecido', async () => {
      const { corpo, params } = parametrizar(lerSql('authn.sql'), { username: 'nao-existe' });
      assert.equal((await prisma.$queryRawUnsafe<unknown[]>(corpo, ...params)).length, 0);
    });

    it('para de devolver linha quando a credencial venceu', async () => {
      await prisma.mqttSession.update({
        where: { id: nomeDaCredencial },
        data: { expires_at: new Date(Date.now() - 1000) },
      });

      const { corpo, params } = parametrizar(lerSql('authn.sql'), { username: nomeDaCredencial });
      assert.equal((await prisma.$queryRawUnsafe<unknown[]>(corpo, ...params)).length, 0);
    });
  });
});
