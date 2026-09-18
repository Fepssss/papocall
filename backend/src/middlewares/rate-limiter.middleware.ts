import { Request, Response, NextFunction } from 'express';
import { logSecurityEvent } from '../utils/logger';

interface RateLimitRecord {
  count: number;
  resetTime: number;
}

/**
 * Cria um middleware de Rate Limiting baseado em IP com janela deslizante em memória.
 *
 * POR QUE RATE LIMITING?
 * Protege contra ataques de força bruta (brute-force) em senhas e tentativas de
 * enumeração de credenciais (credential stuffing), limitando o número de requisições
 * que um mesmo endereço IP pode executar em um determinado intervalo.
 */
export function createRateLimiter(options: {
  windowMs: number;       // Janela de tempo em milissegundos
  max: number;            // Máximo de requisições permitidas na janela
  message?: string;       // Mensagem retornada ao usuário
  keyPrefix?: string;     // Prefixo para diferenciar rotas no armazenamento
}) {
  const store = new Map<string, RateLimitRecord>();

  // Limpeza periódica de entradas expiradas a cada 5 minutos para evitar vazamento de memória
  setInterval(() => {
    const now = Date.now();
    for (const [key, record] of store.entries()) {
      if (now > record.resetTime) {
        store.delete(key);
      }
    }
  }, 5 * 60 * 1000).unref();

  return (req: Request, res: Response, next: NextFunction): void => {
    // Determina o IP do cliente (respeitando X-Forwarded-For se atrás de proxy)
    const clientIp =
      (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ||
      req.socket.remoteAddress ||
      'unknown_ip';

    const key = `${options.keyPrefix || 'rl'}:${clientIp}`;
    const now = Date.now();

    const record = store.get(key);

    if (!record || now > record.resetTime) {
      store.set(key, {
        count: 1,
        resetTime: now + options.windowMs,
      });
      return next();
    }

    if (record.count >= options.max) {
      const retryAfterSeconds = Math.ceil((record.resetTime - now) / 1000);
      res.setHeader('Retry-After', retryAfterSeconds);

      logSecurityEvent({
        event: 'RATE_LIMIT_EXCEEDED',
        ip: clientIp,
        details: { path: req.path, retryAfterSeconds },
      });

      res.status(429).json({
        success: false,
        error: {
          code: 'TOO_MANY_REQUESTS',
          message:
            options.message ||
            `Muitas tentativas. Por segurança, aguarde ${retryAfterSeconds} segundos antes de tentar novamente.`,
          details: {
            retryAfterSeconds,
          },
        },
      });
      return;
    }

    record.count += 1;
    next();
  };
}

/**
 * Limitador estrito para o endpoint de login:
 * Máximo 5 tentativas por IP a cada 15 minutos (900.000 ms).
 */
export const loginRateLimiter = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 5,
  keyPrefix: 'login',
  message: 'Limite de tentativas de login excedido. Aguarde 15 minutos antes de tentar novamente.',
});
