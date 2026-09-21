import { Router } from 'express';
import { authMiddleware } from '../../middlewares/auth.middleware';
import { createRateLimiter } from '../../middlewares/rate-limiter.middleware';
import { mqttController } from './mqtt.controller';

const router = Router();

/**
 * Emissão de credencial custa uma linha no banco e uma chave de 256 bits; o teto
 * abaixo é o mesmo padrão de /livekit/token: uma conta comprometida não pode
 * gerar credencial em massa.
 */
const credenciaisRateLimiter = createRateLimiter({
  windowMs: 60 * 1000,
  max: 12,
  keyPrefix: 'mqtt-cred',
  message: 'Renovações de credencial demais. Aguarde um instante.',
});

router.post(
  '/credentials',
  credenciaisRateLimiter,
  authMiddleware,
  (req, res, next) => mqttController.issueCredentials(req, res, next)
);

/**
 * Substituição do conjunto de salas do usuário. Barata e rara (login, troca de
 * servidor, reconexão depois do login), mas idem: sem teto, um cliente com
 * bug conseguiria martelar o banco.
 */
const salasRateLimiter = createRateLimiter({
  windowMs: 60 * 1000,
  max: 20,
  keyPrefix: 'mqtt-salas',
  message: 'Sincronizações demais. Aguarde um instante.',
});

router.post(
  '/memberships',
  salasRateLimiter,
  authMiddleware,
  (req, res, next) => mqttController.syncMemberships(req, res, next)
);

export const mqttRoutes = router;
