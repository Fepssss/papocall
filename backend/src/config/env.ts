import dotenv from 'dotenv';
import { z } from 'zod';

// Carrega variáveis do arquivo .env antes da validação
dotenv.config();

/**
 * Schema de validação das variáveis de ambiente com Zod.
 * Garante falha rápida (fail-fast) na inicialização do servidor caso
 * alguma configuração crítica esteja ausente ou em formato inválido.
 */
const envSchema = z.object({
  PORT: z.string().default('3333').transform((v) => parseInt(v, 10)),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  DATABASE_URL: z.string().min(1, 'DATABASE_URL é obrigatória'),
  // Lista de origens CORS separadas por vírgula para controle rigoroso
  CORS_ORIGINS: z.string().default('http://localhost:3000,https://papocall.vercel.app'),
  // Chaves RSA para assinatura RS256
  JWT_PRIVATE_KEY: z.string().optional(),
  JWT_PUBLIC_KEY: z.string().optional(),
  JWT_ACCESS_EXPIRATION: z.string().default('15m'),
  JWT_REFRESH_EXPIRATION_DAYS: z.string().default('7').transform((v) => parseInt(v, 10)),
  // LiveKit Cloud
  LIVEKIT_URL: z.string().default('wss://seu-projeto.livekit.cloud'),
  LIVEKIT_API_KEY: z.string().default('your_api_key_here'),
  LIVEKIT_API_SECRET: z.string().default('your_api_secret_here'),
  // E-mail
  EMAIL_FROM: z.string().default('nao-responda@papocall.com'),
  FRONTEND_URL: z.string().default('https://papocall.vercel.app'),
  SMTP_HOST: z.string().optional(),
  SMTP_PORT: z.string().default('587').transform((v) => parseInt(v, 10)),
  SMTP_USER: z.string().optional(),
  SMTP_PASS: z.string().optional(),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error('❌ Falha crítica: Variáveis de ambiente inválidas:');
  console.error(JSON.stringify(parsed.error.format(), null, 2));
  process.exit(1);
}

export const env = parsed.data;
