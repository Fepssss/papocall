import { z } from 'zod';
import { TOPIC_ID_PATTERN } from '../../utils/mqttTopics';

/**
 * POST /mqtt/memberships
 *
 * O corpo traz identificadores de sala já derivados no cliente
 * (`topicIdFor(convite)`), nunca o código de convite. Receber o convite aqui
 * equivaleria a guardar a chave AES-256 de cada servidor no banco, e é exatamente
 * o que a criptografia ponta a ponta existe para evitar.
 */
export const MqttMembershipsSchema = z.object({
  topicIds: z
    .array(z.string().regex(TOPIC_ID_PATTERN, 'Identificador de sala deve ter 32 caracteres hex lowercase'))
    .max(200, 'Limite de salas sincronizadas por requisição'),
});

export type MqttMembershipsInput = z.infer<typeof MqttMembershipsSchema>;
