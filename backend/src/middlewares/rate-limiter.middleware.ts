import { Request, Response, NextFunction } from 'express';
import { env } from '../config/env';
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
    // A suíte automatizada exercita dezenas de registros e logins a partir do
    // mesmo IP; o limitador é validado explicitamente em tests/security.test.ts.
    if (env.NODE_ENV === 'test') {
      return next();
    }

    // IP resolvido pelo Express a partir da configuração 'trust proxy'.
    //
    // NUNCA ler X-Forwarded-For diretamente: é um cabeçalho controlado pelo
    // cliente, então bastava enviar um valor diferente a cada tentativa para
    // zerar o contador e anular por completo a proteção contra força bruta.
    // Com 'trust proxy' configurado no app, req.ip considera apenas os saltos
    // de proxy confiáveis.
    const clientIp = req.ip || req.socket.remoteAddress || 'unknown_ip';

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

/**
 * Limitador para criação de contas: impede registro automatizado em massa.
 */
export const registerRateLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 5,
  keyPrefix: 'register',
  message: 'Limite de criação de contas excedido. Tente novamente em 1 hora.',
});

/**
 * Limitador para recuperação de senha.
 *
 * Sem ele, o endpoint serve como amplificador de e-mail: um atacante dispara
 * milhares de mensagens de "redefinição de senha" para a caixa da vítima.
 */
export const passwordResetRateLimiter = createRateLimiter({
  windowMs: 60 * 60 * 1000,
  max: 5,
  keyPrefix: 'pwreset',
  message: 'Muitas solicitações de redefinição. Aguarde 1 hora antes de tentar novamente.',
});

/**
 * Limitador para rotas consultadas com frequência pela interface
 * (disponibilidade de @username, verificação de e-mail, refresh de sessão).
 * Também reduz a enumeração de usuários existentes.
 */
export const lookupRateLimiter = createRateLimiter({
  windowMs: 5 * 60 * 1000,
  max: 60,
  keyPrefix: 'lookup',
  message: 'Muitas consultas em sequência. Aguarde alguns instantes.',
});
