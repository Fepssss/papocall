import { env } from '../config/env';

/**
 * Logger estruturado para eventos de auditoria e segurança.
 *
 * REGRA DE OURO DE SEGURANÇA:
 * NUNCA registrar em log: senhas, hashes de senha, tokens em texto puro,
 * chaves privadas ou dados de cartão/PII sensível.
 */
export type SecurityEventType =
  | 'USER_REGISTERED'
  | 'LOGIN_SUCCESS'
  | 'LOGIN_FAILED'
  | 'TOKEN_REFRESHED'
  | 'TOKEN_REUSE_DETECTED'
  | 'LOGOUT'
  | 'LOGOUT_ALL_SESSIONS'
  | 'PASSWORD_RESET_REQUESTED'
  | 'PASSWORD_RESET_COMPLETED'
  | 'EMAIL_VERIFIED'
  | 'USERNAME_CHANGED'
  | 'RATE_LIMIT_EXCEEDED';

export interface AuditLogData {
  event: SecurityEventType;
  userId?: string;
  username?: string;
  ip?: string;
  userAgent?: string;
  details?: Record<string, unknown>;
}

export function logSecurityEvent(data: AuditLogData): void {
  const timestamp = new Date().toISOString();
  const logPayload = {
    timestamp,
    level: data.event === 'TOKEN_REUSE_DETECTED' || data.event === 'RATE_LIMIT_EXCEEDED' ? 'WARN' : 'INFO',
    ...data,
  };

  if (env.NODE_ENV === 'production') {
    // Formato JSON estruturado para ingestão em SIEM / Datadog / CloudWatch
    console.log(JSON.stringify(logPayload));
  } else {
    const icon =
      data.event === 'TOKEN_REUSE_DETECTED'
        ? '🚨'
        : data.event === 'LOGIN_FAILED'
        ? '⚠️'
        : data.event === 'LOGIN_SUCCESS'
        ? '✅'
        : '🛡️';
    console.log(
      `[AUDIT ${timestamp}] ${icon} [${data.event}] User: ${data.username || data.userId || 'anonymous'} | IP: ${
        data.ip || 'unknown'
      }`,
      data.details ? JSON.stringify(data.details) : ''
    );
  }
}
