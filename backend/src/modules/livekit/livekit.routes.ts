import { Router } from 'express';
import { livekitController } from './livekit.controller';
import { authMiddleware } from '../../middlewares/auth.middleware';

const router = Router();

// Endpoint protegido para geração de token LiveKit
router.post('/token', authMiddleware, (req, res, next) =>
  livekitController.generateToken(req, res, next)
);

export const livekitRoutes = router;
