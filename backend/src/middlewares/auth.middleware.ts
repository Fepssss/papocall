import { Request, Response, NextFunction } from 'express';
import { verifyAccessToken } from '../utils/token';
import { AppError } from './error.middleware';

/**
 * Extensão da interface de Request do Express para tipagem estrita
 * dos dados do usuário autenticado no contexto da requisição.
 */
declare global {
  namespace Express {
    interface Request {
      userId?: string;
      user?: {
        id: string;
        email: string;
        username: string; // Sempre formatado com prefixo '@' no objeto de request para consistência
        rawUsername: string; // Sem '@'
        displayName: string;
        emailVerified: boolean;
      };
    }
  }
}

/**
 * Middleware de Autenticação JWT (RS256).
 *
 * COMO FUNCIONA:
 * 1. Extrai o cabeçalho Authorization: Bearer <token>.
 * 2. Valida a integridade e expiração usando a Chave Pública RSA (RS256).
 * 3. Popula req.userId e req.user para os controllers downstream.
 */
export function authMiddleware(req: Request, _res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;

  if (!authHeader) {
    return next(new AppError('Cabeçalho de autorização não fornecido.', 401, 'UNAUTHORIZED'));
  }

  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0].toLowerCase() !== 'bearer') {
    return next(
      new AppError('Formato de autorização inválido. Use "Bearer <token>".', 401, 'INVALID_TOKEN_FORMAT')
    );
  }

  const token = parts[1];

  try {
    const decoded = verifyAccessToken(token);

    req.userId = decoded.sub;
    req.user = {
      id: decoded.sub,
      email: decoded.email,
      username: `@${decoded.username}`,
      rawUsername: decoded.username,
      displayName: decoded.displayName,
      emailVerified: decoded.emailVerified,
    };

    next();
  } catch (error) {
    next(error);
  }
}
