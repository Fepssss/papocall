import { Router } from 'express';
import { livekitController } from './livekit.controller';
import { authMiddleware } from '../../middlewares/auth.middleware';
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

/**
 * Endpoint protegido para geração de token LiveKit.
 *
 * Exige JWT válido e aplica rate-limit. A confirmação de e-mail NÃO é requisito
 * aqui: o envio do e-mail de verificação é feito em background e engolido pelo
 * próprio `catch` (auth.service.ts), e não existe rota nem botão de reenvio.
 * Com a guarda ativa, uma conta cujo e-mail não chegou fica sem voz e sem
 * nenhum caminho de recuperação dentro do aplicativo.
 */
router.post('/token', tokenRateLimiter, authMiddleware, (req, res, next) =>
  livekitController.generateToken(req, res, next)
);

export const livekitRoutes = router;
