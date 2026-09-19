import { Router } from 'express';
import { authController } from './auth.controller';
import { authMiddleware } from '../../middlewares/auth.middleware';
import {
  loginRateLimiter,
  registerRateLimiter,
  passwordResetRateLimiter,
  lookupRateLimiter,
} from '../../middlewares/rate-limiter.middleware';

const router = Router();

// =============================================================================
// ROTAS PÚBLICAS
// =============================================================================

// Registro de novo usuário com validação de username único e Argon2id
router.post('/register', registerRateLimiter, (req, res, next) =>
  authController.register(req, res, next)
);

// Checagem de disponibilidade de username em tempo real
router.get('/username-available', lookupRateLimiter, (req, res, next) =>
  authController.checkUsernameAvailable(req, res, next)
);

// Login com e-mail OU @username + senha (com rate limiting rigoroso contra força bruta)
router.post('/login', loginRateLimiter, (req, res, next) =>
  authController.login(req, res, next)
);

// Rotação de Refresh Token com detecção de reuso
router.post('/refresh', lookupRateLimiter, (req, res, next) =>
  authController.refresh(req, res, next)
);

// Encerramento da sessão atual (logout)
router.post('/logout', (req, res, next) => authController.logout(req, res, next));

// Confirmação de e-mail via token recebido
router.post('/verify-email', lookupRateLimiter, (req, res, next) =>
  authController.verifyEmail(req, res, next)
);

// Solicitação de recuperação de senha (esqueci minha senha)
router.post('/forgot-password', passwordResetRateLimiter, (req, res, next) =>
  authController.forgotPassword(req, res, next)
);

// Redefinição de senha com token de uso único (invalida todas as sessões anteriores)
router.post('/reset-password', passwordResetRateLimiter, (req, res, next) =>
  authController.resetPassword(req, res, next)
);

// =============================================================================
// ROTAS PROTEGIDAS (Exigem Header Authorization: Bearer <access_token>)
// =============================================================================

// Consulta os dados do perfil do usuário autenticado
router.get('/me', authMiddleware, (req, res, next) =>
  authController.getMe(req, res, next)
);

// Encerra todas as sessões ativas do usuário em todos os dispositivos
router.post('/logout-all', authMiddleware, (req, res, next) =>
  authController.logoutAll(req, res, next)
);

// Alteração de @username (sujeita a limite de frequência de 30 dias)
router.patch('/username', authMiddleware, (req, res, next) =>
  authController.changeUsername(req, res, next)
);

export const authRoutes = router;
