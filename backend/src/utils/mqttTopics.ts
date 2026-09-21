import crypto from 'node:crypto';

/**
 * Espelho exato do `topicIdFor` de `flutter_app/lib/services/server_crypto.dart`,
 * mais a tabela de verdade do que o broker pode autorizar.
 *
 * POR QUE ISTO MORA AQUI: o broker decide pub/sub pela tabela `mqtt_grants`, que
 * é preenchida por este módulo. Se o hash derivado aqui divergir do que o
 * aplicativo calcula, o usuário recebe credencial válida e ainda assim é negado
 * em tudo — o sintoma é chat mudo sem erro nenhum. Os vetores de
 * `tests/mqtt-acl.test.ts` amarram as duas implementações; a não-divergência é
 * medida lá, não conferida no olho.
 */
const TOPIC_DOMAIN = 'papocall/v2/topic';

/** `sha256("<domínio>:<semente>")` em hex, nos 32 primeiros caracteres. */
export function topicIdFor(seed: string): string {
  const normalized = seed.trim().toLowerCase();
  return crypto
    .createHash('sha256')
    .update(`${TOPIC_DOMAIN}:${normalized}`, 'utf8')
    .digest('hex')
    .slice(0, 32);
}

/** Prefixo da caixa de entrada própria — o único lugar onde o usuário lê. */
export function inboxPrefixFor(username: string): string {
  return `papocall/v2/u/${topicIdFor(`inbox:${username}`)}/inbox`;
}

/** Tópico de presença próprio. */
export function presenceTopicFor(username: string): string {
  return `papocall/v2/u/${topicIdFor(`presence:${username}`)}/presence`;
}

/** Prefixo de servidor a partir do identificador opaco que o cliente deriva do convite. */
export function roomPrefixFor(topicId: string): string {
  return `papocall/v2/r/${topicId}`;
}

export const TOPIC_ID_PATTERN = /^[0-9a-f]{32}$/;

const HEX32 = '[0-9a-f]{32}';
/** Um compartimento de caixa de entrada: `<hash>/inbox/<hash-do-remetente>`, sem nível extra. */
const INBOX_SLOT_RE = new RegExp(`^papocall/v2/u/${HEX32}/inbox/[^/]+$`);
/** O tópico de presença de alguém, exato: sem subníveis, sem curinga. */
const PRESENCE_RE = new RegExp(`^papocall/v2/u/${HEX32}/presence$`);

/**
 * Tabela de verdade da autorização — a referência contra a qual a configuração
 * do broker é escrita, e que `tests/mqtt-acl.test.ts` percorre caso a caso.
 *
 *   publicar e ler a própria caixa de entrada                        permitido
 *   LER a caixa de entrada de outra pessoa                          NEGADO
 *       Este é o ganho novo da migração. No broker público de hoje
 *       qualquer cliente assina qualquer tópico e recebe o que passar.
 *   publicar um compartimento da caixa de outra pessoa              permitido
 *       É o caminho de uma mensagem direta e de um pedido de amizade
 *       para quem ainda não é contato. Escrever não dá leitura: o
 *       destinatário descarta o que não passa no MAC do AES-GCM.
 *   publicar a própria presença                                     permitido
 *   assinar presença de outra pessoa                                permitido
 *       A lista de amigos precisa disto, e o conteúdo é cifrado.
 *   qualquer tópico de servidor sem grant daquela sala              NEGADO
 *
 * Não depende de segredo nenhum. Continuidade da confidencialidade é mérito do
 * AES-GCM; a ACL tira do atacante o alcance, não a leitura do que é dele.
 */
export function canUseTopic(
  action: 'publish' | 'subscribe',
  topic: string,
  grants: readonly string[]
): boolean {
  // 1. Qualquer coisa abaixo de um prefixo próprio. Cobre também a assinatura com
  //    curinga usada na reconexão (`.../inbox/#`), que é o único curinga do app.
  if (grants.some((prefix) => topic === prefix || topic.startsWith(`${prefix}/`))) return true;

  // 2. Caixa alheia: só a escrita, só num compartimento direto.
  if (action === 'publish' && INBOX_SLOT_RE.test(topic)) return true;

  // 3. Presença alheia: só a leitura.
  if (action === 'subscribe' && PRESENCE_RE.test(topic)) return true;

  return false;
}
