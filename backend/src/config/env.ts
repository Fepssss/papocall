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
  // Banco exclusivo para a suíte de testes. Quando ausente, os testes rodam
  // contra DATABASE_URL e ficam restritos ao domínio de fixture reservado.
  TEST_DATABASE_URL: z.string().optional(),
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
  // Origens permitidas explicitamente; ver validação de produção abaixo.
  // E-mail
  EMAIL_FROM: z.string().default('nao-responda@papocall.com'),
  FRONTEND_URL: z.string().default('https://papocall.vercel.app'),
  SMTP_HOST: z.string().optional(),
  SMTP_PORT: z.string().default('587').transform((v) => parseInt(v, 10)),
  SMTP_USER: z.string().optional(),
  SMTP_PASS: z.string().optional(),
  // Broker MQTT dedicado.
  //
  // A credencial é de sessão e expira: curta duração é o que limita o estrago de
  // uma senha arrancada de um aparelho emprestado, e o aplicativo renova junto do
  // access token, então doze horas é folga e não afrouxamento.
  MQTT_CREDENTIAL_TTL_MINUTES: z.string().default('720').transform((v) => parseInt(v, 10)),
  // Onde o broker fica. Entregar isto pela API — e não só pelo --dart-define do
  // build — é o que permite trocar de broker sem publicar versão nova.
  //
  // Diferente de SMTP_HOST, estes NÃO são obrigatórios em produção ainda: o
  // broker self-hosted só existe depois de provisionado, e uma validação nova que
  // abortasse a inicialização hoje derrubaria o login inteiro por um recurso que
  // ainda não foi ligado. Passam a ser exigidos no dia em que a versão do
  // aplicativo que exige credencial for a publicada — ver o runbook do broker.
  MQTT_HOST: z.string().default(''),
  MQTT_PORT: z.string().default('8883').transform((v) => parseInt(v, 10)),
  MQTT_WSS_URL: z.string().default(''),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error('❌ Falha crítica: Variáveis de ambiente inválidas:');
  console.error(JSON.stringify(parsed.error.format(), null, 2));
  process.exit(1);
}

export const env = parsed.data;

// =============================================================================
// VALIDAÇÃO ADICIONAL DE PRODUÇÃO
// =============================================================================
// Os defaults acima existem para o ambiente de desenvolvimento funcionar sem
// configuração. Em produção eles são perigosos: um deploy com a chave de
// exemplo aceitaria requisições e falharia apenas na hora da chamada de voz,
// ou pior, rodaria com um segredo previsível. Falhar na inicialização torna o
// problema visível imediatamente.
if (env.NODE_ENV === 'production') {
  const placeholders: string[] = [];

  if (env.LIVEKIT_API_KEY === 'your_api_key_here') placeholders.push('LIVEKIT_API_KEY');
  if (env.LIVEKIT_API_SECRET === 'your_api_secret_here') placeholders.push('LIVEKIT_API_SECRET');
  if (env.LIVEKIT_URL === 'wss://seu-projeto.livekit.cloud') placeholders.push('LIVEKIT_URL');
  if (!env.SMTP_HOST) placeholders.push('SMTP_HOST');

  if (placeholders.length > 0) {
    console.error(
      '❌ Falha crítica: variáveis obrigatórias em produção não configuradas ou com valor de exemplo:',
      placeholders.join(', ')
    );
    process.exit(1);
  }
}
