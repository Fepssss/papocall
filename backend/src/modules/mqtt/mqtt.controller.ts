import { Request, Response, NextFunction } from 'express';
import { env } from '../../config/env';
import { prisma } from '../../db/prisma';
import { AppError } from '../../middlewares/error.middleware';
import { generateRandomToken, hashToken } from '../../utils/token';
import { roomPrefixFor } from '../../utils/mqttTopics';
import { syncOwnGrants } from './mqtt.grants';
import { MqttMembershipsSchema } from './mqtt.schemas';

/**
 * Teto de credenciais vivas por conta.
 *
 * O aplicativo renova a credencial juntos com o access token, então sem um teto
 * cada renovação deixaria uma senha válida para trás: uma conta comprometida
 * empilharia credenciais e o banco cresceria sem limite. Cinco cobre abrir o app
 * em mais de uma máquina e ainda renovar com folga.
 */
const MAX_SESSOES_VIVAS_POR_USUARIO = 5;

const KINDS_DERIVADOS = ['inbox', 'presenca'] as const;

export class MqttController {
  /**
   * POST /mqtt/credentials
   *
   * Emite a credencial de sessão do MQTT. A senha é aleatória de 256 bits e só o
   * hash dela vai para o banco — a mesma regra dos refresh tokens. O nome de
   * usuário do broker é o UUID interno, então o log do broker não expõe @ nem
   * e-mail de ninguém.
   *
   * Também é aqui que os prefixos próprios (caixa de entrada e presença) são
   * recalculados: eles derivam do username, e trocar de @ sem recalcular deixaria
   * o dono sem acesso à própria caixa, negado pelo broker, com o app parecendo
   * apenas "offline".
   */
  async issueCredentials(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const user = req.user!;
      const agora = new Date();
      const expiresAt = new Date(agora.getTime() + env.MQTT_CREDENTIAL_TTL_MINUTES * 60_000);
      const mqttPassword = generateRandomToken(32);

      const sessao = await prisma.$transaction(async (tx) => {
        const criada = await tx.mqttSession.create({
          data: { user_id: user.id, password_hash: hashToken(mqttPassword), expires_at: expiresAt },
        });
        await syncOwnGrants(tx, user.id, user.rawUsername);
        await tx.mqttSession.deleteMany({ where: { user_id: user.id, expires_at: { lt: agora } } });
        return criada;
      });

      // Mantém só as mais recentes. Sem isto, o teto acima não passa de comentário.
      const alemDoTeto = await prisma.mqttSession.findMany({
        where: { user_id: user.id, expires_at: { gt: agora } },
        orderBy: { created_at: 'desc' },
        skip: MAX_SESSOES_VIVAS_POR_USUARIO,
        select: { id: true },
      });
      if (alemDoTeto.length > 0) {
        await prisma.mqttSession.deleteMany({ where: { id: { in: alemDoTeto.map((s) => s.id) } } });
      }

      res.status(200).json({
        success: true,
        data: {
          // O nome no broker é o id da CREDENCIAL, não o da conta. Uma conta pode
          // ter várias credenciais vivas (mais de um aparelho aberto), e a consulta
          // do broker precisa voltar uma linha só. Ninguém fica identificável no
          // log do broker nem por conta nem por @.
          mqttUsername: sessao.id,
          mqttPassword,
          expiresAt: expiresAt.toISOString(),
          // Onde conectar. Chega do servidor para que trocar de broker seja uma
          // linha de configuração no Render, e não uma versão nova do aplicativo.
          host: env.MQTT_HOST,
          port: env.MQTT_PORT,
          wssUrl: env.MQTT_WSS_URL,
        },
      });
    } catch (error) {
      next(error);
    }
  }

  /**
   * POST /mqtt/memberships
   *
   * Substitui o conjunto de salas do usuário pelo que ele informa. É substituir,
   * não acrescentar: assim uma participação que deixou de existir (saí do
   * servidor, servidor apagado, expulsão) para de valer na próxima sincronização
   * em vez de apodrecer numa tabela que o broker lê como autorização.
   */
  async syncMemberships(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const user = req.user!;
      const { topicIds } = MqttMembershipsSchema.parse(req.body ?? {});

      const dados = topicIds.map((id) => ({
        user_id: user.id,
        topic_prefix: roomPrefixFor(id),
        kind: 'servidor' as const,
      }));

      const resultado = await prisma.$transaction([
        prisma.mqttGrant.deleteMany({ where: { user_id: user.id, kind: 'servidor' } }),
        prisma.mqttGrant.createMany({ data: dados, skipDuplicates: true }),
        prisma.mqttGrant.findMany({
          where: { user_id: user.id, kind: 'servidor' },
          select: { topic_prefix: true },
        }),
      ]);

      if (resultado[2].length !== dados.length) {
        throw new AppError(
          'A sincronização das salas não fechou com o que foi enviado.',
          500,
          'MEMBERSHIP_SYNC_FAILED'
        );
      }

      res.status(200).json({ success: true, data: { granted: resultado[2].length } });
    } catch (error) {
      next(error);
    }
  }
}

export const mqttController = new MqttController();
