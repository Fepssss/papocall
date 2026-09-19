import { Router } from 'express';
import { livekitController } from './livekit.controller';
import { authMiddleware, requireVerifiedEmail } from '../../middlewares/auth.middleware';
import { createRateLimiter } from '../../middlewares/rate-limiter.middleware';

const router = Router();

/**
 * Cada token emitido autoriza uma conexão RTC faturada no LiveKit.
 * O limite evita que uma conta comprometida gere tokens em massa.
 */
const tokenRateLimiter = createRateLimiter({
  windowMs: 60 * 1000,
  max: 20,
  keyPrefix: 'lk-token',
  message: 'Muitas tentativas de conexão de voz. Aguarde um instante.',
});

// Endpoint protegido para geração de token LiveKit.
// requireVerifiedEmail impede que contas recém-criadas com e-mail de terceiros
// consumam recursos de voz antes da confirmação do endereço.
router.post('/token', tokenRateLimiter, authMiddleware, requireVerifiedEmail, (req, res, next) =>
  livekitController.generateToken(req, res, next)
);

export const livekitRoutes = router;
