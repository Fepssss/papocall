import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  canUseTopic,
  inboxPrefixFor,
  presenceTopicFor,
  roomPrefixFor,
  topicIdFor,
} from '../src/utils/mqttTopics';

/**
 * Testes sem banco: a regra de autorização em si.
 *
 * Este arquivo roda onde qualquer teste roda, inclusive sem Postgres por perto,
 * porque a tabela de verdade não depende de infraestrutura. A parte que fala com
 * o banco está em `mqtt-endpoints.test.ts`.
 */

/**
 * Vetores calculados pela implementação Dart, com um script de uma linha contra o
 * mesmo `package:crypto` que `server_crypto.dart` usa:
 *
 *   sha256("papocall/v2/topic:" + semente).hex.substring(0, 32)
 *
 * Estão aqui porque é a divergência que ninguém veria: se o hash do backend e o
 * do aplicativo deixarem de bater, o usuário autentica no broker e continua
 * negado em todos os tópicos, e o sintoma é chat mudo sem erro em lugar nenhum.
 */
const VETORES: Array<[string, string]> = [
  ['inbox:feps', 'db274d01288b28fde61a3b1094550b53'],
  ['presence:feps', '7e9697d340f6ff22389947d98b1878bc'],
  ['papo-1a2b3c4d', 'c481ddda3287b011e63fef7e763eeae9'],
  ['inboxslot:feps', 'b7a666f5da1b5706fbd496de296a623e'],
  // A forma normalizada: o Dart aplica trim+lowercase na semente inteira.
  ['INBOX:Feps', 'db274d01288b28fde61a3b1094550b53'],
  ['  inBoX:Feps  ', 'db274d01288b28fde61a3b1094550b53'],
];

describe('9. Derivação de tópico bate com a do aplicativo', () => {
  for (const [semente, esperado] of VETORES) {
    it(`topicIdFor(${JSON.stringify(semente)}) == ${esperado}`, () => {
      assert.equal(topicIdFor(semente), esperado);
    });
  }

  it('os prefixes montam exatamente o tópico que o app assina', () => {
    // Copiado da forma construída em server_crypto.dart:141 e :183.
    assert.equal(inboxPrefixFor('feps'), `papocall/v2/u/${VETORES[0][1]}/inbox`);
    assert.equal(presenceTopicFor('feps'), `papocall/v2/u/${VETORES[1][1]}/presence`);
    assert.equal(roomPrefixFor(VETORES[2][1]), `papocall/v2/r/${VETORES[2][1]}`);
  });
});

describe('10. Tabela de verdade da autorização do broker', () => {
  const dono = 'feps';
  const outra = 'maria';
  const sala = roomPrefixFor(topicIdFor('papo-1a2b3c4d'));
  const grants = [inboxPrefixFor(dono), presenceTopicFor(dono)];

  /** Compartimento de caixa de entrada do destinatário, escrito por `remetente`. */
  function slotInbox(destinatario: string, remetente: string): string {
    return `${inboxPrefixFor(destinatario)}/${topicIdFor(`inboxslot:${remetente}`)}`;
  }

  const casos: Array<[string, 'publish' | 'subscribe', string, boolean]> = [
    ['ler a própria caixa', 'subscribe', inboxPrefixFor(dono), true],
    ['ler um compartimento da própria caixa', 'subscribe', slotInbox(dono, outra), true],
    [
      'assinar a própria caixa com o curinga de reconexão',
      'subscribe',
      `${inboxPrefixFor(dono)}/#`,
      true,
    ],
    ['escrever na própria caixa', 'publish', slotInbox(dono, dono), true],

    // O ganho da migração: no broker anônimo de hoje, tudo isto abaixo é permitido.
    ['LER a caixa de outra pessoa', 'subscribe', slotInbox(outra, dono), false],
    ['assinar a caixa alheia com curinga', 'subscribe', `${inboxPrefixFor(outra)}/#`, false],
    ['assinar o nó da caixa alheia', 'subscribe', inboxPrefixFor(outra), false],

    ['escrever num compartimento da caixa alheia', 'publish', slotInbox(outra, dono), true],
    ['escrever no nó da caixa alheia, sem compartimento', 'publish', inboxPrefixFor(outra), false],
    [
      'escrever dois níveis abaixo na caixa alheia',
      'publish',
      `${inboxPrefixFor(outra)}/${topicIdFor('x')}/extra`,
      false,
    ],

    ['publicar a própria presença', 'publish', presenceTopicFor(dono), true],
    ['assinar presença alheia', 'subscribe', presenceTopicFor(outra), true],
    ['publicar presença alheia', 'publish', presenceTopicFor(outra), false],
    ['assinar presença alheia com curinga', 'subscribe', `${presenceTopicFor(outra)}/#`, false],

    ['sala sem grant, publicar', 'publish', `${sala}/chat`, false],
    ['sala sem grant, assinar', 'subscribe', `${sala}/chat`, false],
    ['nó da sala sem grant', 'subscribe', sala, false],
  ];

  for (const [nome, acao, topico, permitido] of casos) {
    it(`${nome}: ${acao} ${permitido ? 'permitido' : 'negado'}`, () => {
      assert.equal(canUseTopic(acao, topico, grants), permitido);
    });
  }

  it('com o grant da sala, tudo abaixo dela passa a ser permitido', () => {
    const comSala = [...grants, sala];
    assert.equal(canUseTopic('publish', `${sala}/chat`, comSala), true);
    assert.equal(canUseTopic('subscribe', `${sala}/chat`, comSala), true);
    assert.equal(canUseTopic('subscribe', `${sala}/history/${topicIdFor('slot')}`, comSala), true);
    assert.equal(canUseTopic('subscribe', `${sala}/presence/${topicIdFor('x')}`, comSala), true);
    // E não vazam para a sala de ninguém.
    assert.equal(canUseTopic('subscribe', `${sala}/chat`, [inboxPrefixFor(dono)]), false);
  });

  it('nada fora do vocabulário de tópicos do produto passa', () => {
    const estranhos = [
      'papocall/v2/r/nao-e-um-hash/chat',
      'papocall/v1/r/qualquer/coisa',
      '$SYS/broker/uptime',
      '#',
      'papocall/v2/u/zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz/inbox',
      '',
    ];
    for (const topico of estranhos) {
      assert.equal(canUseTopic('subscribe', topico, [...grants, sala]), false, topico);
      assert.equal(canUseTopic('publish', topico, [...grants, sala]), false, topico);
    }
  });

  it('prefixo próprio não casa com um nível vizinho que começa igual', () => {
    // `startsWith` puro deixaria `.../inboxX` passar como se estivesse dentro de
    // `.../inbox`. A fronteira é o separador de nível, não o começo do texto.
    assert.equal(canUseTopic('subscribe', `${inboxPrefixFor(dono)}vizinho`, grants), false);
    assert.equal(canUseTopic('publish', `${presenceTopicFor(dono)}vizinho`, grants), false);
  });
});
