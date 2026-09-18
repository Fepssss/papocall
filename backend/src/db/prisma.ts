import { PrismaClient } from '@prisma/client';
import { env } from '../config/env';

/**
 * Instância Singleton do PrismaClient.
 * Em desenvolvimento, evita múltiplas instâncias criadas em hot-reloads.
 */
declare global {
  // eslint-disable-next-line no-var
  var prisma: PrismaClient | undefined;
}

export const prisma: PrismaClient =
  globalThis.prisma ||
  new PrismaClient({
    log: env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
  });

if (env.NODE_ENV !== 'production') {
  globalThis.prisma = prisma;
}
