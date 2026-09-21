import { Prisma } from '@prisma/client';
import { inboxPrefixFor, presenceTopicFor } from '../../utils/mqttTopics';

/** Os dois prefixos que o backend deriva sozinho, a partir do username real. */
export const KINDS_DERIVADOS = ['inbox', 'presenca'] as const;

/**
 * Reescreve os prefixos próprios de um usuário: a caixa de entrada e o tópico de
 * presença. Salas não passam por aqui — essas o aplicativo declara.
 *
 * Por que isto é uma função e não quatro linhas dentro de cada chamada: os dois
 * nomes derivam do `username`, e existe um caminho em que o username muda sem que
 * nenhuma credencial seja reemitida — o `PATCH /auth/username`. Sem reescrever
 * aqui, o dono continuaria autenticado no broker e seria negado na própria caixa,
 * com o aplicativo mostrando apenas "offline". Por isso a troca de @ e a
 * reescrita dos prefixos têm de acontecer no mesmo transação.
 */
export async function syncOwnGrants(
  tx: Prisma.TransactionClient,
  userId: string,
  username: string
): Promise<void> {
  await tx.mqttGrant.deleteMany({
    where: { user_id: userId, kind: { in: [...KINDS_DERIVADOS] } },
  });

  await tx.mqttGrant.createMany({
    data: [
      { user_id: userId, topic_prefix: inboxPrefixFor(username), kind: 'inbox' },
      { user_id: userId, topic_prefix: presenceTopicFor(username), kind: 'presenca' },
    ],
    skipDuplicates: true,
  });
}
