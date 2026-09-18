import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { JsonWebTokenError, TokenExpiredError } from 'jsonwebtoken';
import { env } from '../config/env';

/**
 * Classe padrão para erros operacionais conhecidos da aplicação.
 */
export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: string;
  public readonly details?: unknown;

  constructor(message: string, statusCode = 400, code = 'BAD_REQUEST', details?: unknown) {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

/**
 * Middleware central de tratamento e sanitização de erros.
 *
 * REGRA DE SEGURANÇA:
 * Em produção, NUNCA expor stack traces, mensagens internas de banco de dados
 * (ex: SQL/Prisma syntax errors) ou caminhos de arquivo do servidor.
 */
export function errorHandler(
  err: unknown,
  _req: Request,
  res: Response,
  _next: NextFunction
): void {
  // 1. Erros de validação Zod
  if (err instanceof ZodError) {
    const formattedErrors = err.errors.map((e) => ({
      field: e.path.join('.'),
      message: e.message,
    }));

    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: formattedErrors[0]?.message || 'Dados inválidos fornecidos.',
        details: { fields: formattedErrors },
      },
    });
    return;
  }

  // 2. Erros de negócio da aplicação (AppError)
  if (err instanceof AppError) {
    res.status(err.statusCode).json({
      success: false,
      error: {
        code: err.code,
        message: err.message,
        ...(err.details ? { details: err.details } : {}),
      },
    });
    return;
  }

  // 3. Erros de token JWT
  if (err instanceof TokenExpiredError) {
    res.status(401).json({
      success: false,
      error: {
        code: 'TOKEN_EXPIRED',
        message: 'Sua sessão expirou. Por favor, faça login novamente.',
      },
    });
    return;
  }

  if (err instanceof JsonWebTokenError) {
    res.status(401).json({
      success: false,
      error: {
        code: 'INVALID_TOKEN',
        message: 'Token de autenticação inválido ou corrompido.',
      },
    });
    return;
  }

  // 4. Erros não tratados (Internal Server Error)
  console.error('❌ [UNHANDLED ERROR]', err);

  const isDev = env.NODE_ENV === 'development';
  const errorMessage = err instanceof Error ? err.message : 'Erro interno desconhecido';

  res.status(500).json({
    success: false,
    error: {
      code: 'INTERNAL_SERVER_ERROR',
      message: 'Ocorreu um erro interno em nossos servidores. Tente novamente mais tarde.',
      // Stack traces e detalhes são omitidos estritamente em produção
      ...(isDev ? { debug: errorMessage, stack: err instanceof Error ? err.stack : undefined } : {}),
    },
  });
}
