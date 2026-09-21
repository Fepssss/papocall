import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import { env } from './config/env';
import { authRoutes } from './modules/auth/auth.routes';
import { livekitRoutes } from './modules/livekit/livekit.routes';
import { mqttRoutes } from './modules/mqtt/mqtt.routes';
import { errorHandler, AppError } from './middlewares/error.middleware';

export const app = express();

// =============================================================================
// CONFIANÇA EM PROXY REVERSO
// =============================================================================
// Necessário para que req.ip reflita o IP real do cliente atrás da Vercel/CDN.
// Confia em exatamente 1 salto: confiar na cadeia inteira permitiria ao cliente
// forjar X-Forwarded-For e escapar do rate limiting.
app.set('trust proxy', 1);

// =============================================================================
// CABEÇALHOS DE SEGURANÇA (HELMET)
// =============================================================================
// Configura Content Security Policy (CSP), esconde cabeçalho X-Powered-By,
// ativa HSTS, X-Content-Type-Options, X-Frame-Options contra clickjacking
app.use(
  helmet({
    contentSecurityPolicy: true,
    crossOriginEmbedderPolicy: false,
  })
);

// =============================================================================
// CORS RESTRITIVO COM WHITELIST
// =============================================================================
// NUNCA utilizar wildcard '*' em produção quando há autenticação e cookies/tokens
const allowedOrigins = env.CORS_ORIGINS.split(',').map((origin) => origin.trim());

app.use(
  cors({
    origin: (origin, callback) => {
      // Permite requisições sem 'Origin' (como apps mobile/desktop Flutter ou ferramentas como curl/Postman)
      if (!origin) {
        return callback(null, true);
      }

      if (allowedOrigins.includes(origin)) {
        return callback(null, true);
      }

      callback(new AppError('Acesso bloqueado por política de CORS.', 403, 'CORS_BLOCKED'));
    },
    credentials: true,
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
  })
);

// =============================================================================
// PARSERS E LIMITAÇÃO DE PAYLOAD (Mitigação de DoS por Payloads Gigantes)
// =============================================================================
app.use(express.json({ limit: '100kb' }));
app.use(express.urlencoded({ extended: true, limit: '100kb' }));

// Health Check
app.get('/health', (_req, res) => {
  res.status(200).json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    service: 'papocall-auth',
  });
});

// =============================================================================
// ROTAS DA APLICAÇÃO
// =============================================================================
app.use('/auth', authRoutes);
app.use('/livekit', livekitRoutes);
app.use('/mqtt', mqttRoutes);

// Tratamento de Rota Não Encontrada (404)
app.use((req, _res, next) => {
  next(new AppError(`Rota não encontrada: ${req.method} ${req.originalUrl}`, 404, 'NOT_FOUND'));
});

// =============================================================================
// TRATAMENTO CENTRALIZADO DE ERROS (Sem vazamento de stack trace em produção)
// =============================================================================
app.use(errorHandler);
