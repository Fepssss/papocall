import { Request, Response, NextFunction } from 'express';
import { AccessToken } from 'livekit-server-sdk';
import { env } from '../../config/env';
import { LivekitTokenSchema } from '../auth/auth.schemas';

export class LivekitController {
  /**
   * POST /livekit/token
   *
   * GERAÇÃO SEGURA DE TOKEN RTC LIVEKIT:
   * 1. Rota obrigatoriamente protegida por authMiddleware.
   * 2. A identity no LiveKit é estritamente vinculada ao @username do usuário autenticado.
   * 3. NUNCA aceita 'identity' vinda do corpo da requisição (body) ou query string,
   *    impedindo ataques de personificação (impersonation) ou spoofing de identidade na chamada.
   */
  async generateToken(req: Request, res: Response, next: NextFunction): Promise<void> {
    try {
      const validatedBody = LivekitTokenSchema.parse(req.body || {});
      const room = validatedBody.room;

      // Identity garantida pelo JWT verificado:
      const authenticatedUser = req.user!;
      const identity = authenticatedUser.username; // Ex: '@joaosilva'
      const displayName = authenticatedUser.displayName;

      const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
        identity,
        name: displayName,
      });

      at.addGrant({
        room,
        roomJoin: true,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
      });

      const token = await at.toJwt();

      res.status(200).json({
        success: true,
        data: {
          serverUrl: env.LIVEKIT_URL,
          token,
          room,
          identity,
          displayName,
        },
      });
    } catch (error) {
      next(error);
    }
  }
}

export const livekitController = new LivekitController();
