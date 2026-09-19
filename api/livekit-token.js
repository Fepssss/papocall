const { AccessToken } = require('livekit-server-sdk');
const jwt = require('jsonwebtoken');

const LIVEKIT_URL = process.env.LIVEKIT_URL;
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;
const JWT_PUBLIC_KEY = process.env.JWT_PUBLIC_KEY;

const TOKEN_ISSUER = 'papocall-auth';
const ROOM_PATTERN = /^[a-zA-Z0-9_-]{1,64}$/;

// Origens autorizadas a chamar este endpoint pelo navegador.
const ALLOWED_ORIGINS = (process.env.CORS_ORIGINS || 'https://papocall.vercel.app')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

function normalizePem(key) {
  if (!key) return null;
  let clean = key.trim();
  if (!clean.includes('-----BEGIN')) {
    try {
      clean = Buffer.from(clean, 'base64').toString('utf8');
    } catch {
      return null;
    }
  }
  return clean.replace(/\\n/g, '\n');
}

/**
 * Emissão de token de voz do LiveKit.
 *
 * MODELO DE SEGURANÇA:
 * Até a v1.0.0f este endpoint era anônimo, aceitava `identity` pela query e
 * respondia com `Access-Control-Allow-Origin: *`. Qualquer pessoa na internet
 * podia emitir um token com a identidade de outro usuário, entrar em qualquer
 * sala e consumir a cota do projeto.
 *
 * Agora ele exige o access token JWT (RS256) emitido pelo serviço de
 * autenticação e deriva a identity exclusivamente desse token.
 */
module.exports = async (req, res) => {
  const origin = req.headers.origin;
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ success: false, error: { code: 'METHOD_NOT_ALLOWED', message: 'Use POST.' } });
    return;
  }

  if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET || !LIVEKIT_URL || !JWT_PUBLIC_KEY) {
    // Redundância / Proxy transparente: repassa para o backend oficial no Render
    const backendUrl = process.env.PAPOCALL_BACKEND_URL || 'https://papocall.onrender.com';
    try {
      const forwardRes = await fetch(`${backendUrl}/livekit/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(req.headers.authorization ? { Authorization: req.headers.authorization } : {}),
        },
        body: JSON.stringify(req.body || {}),
      });

      const forwardData = await forwardRes.json();
      res.status(forwardRes.status).json(forwardData);
      return;
    } catch (proxyError) {
      console.error('[livekit-token] Erro ao repassar requisição ao backend:', proxyError);
      res.status(500).json({
        success: false,
        error: { code: 'SERVER_MISCONFIGURED', message: 'Serviço de voz indisponível.' },
      });
      return;
    }
  }

  const authHeader = req.headers.authorization || '';
  const [scheme, bearerToken] = authHeader.split(' ');

  if (scheme?.toLowerCase() !== 'bearer' || !bearerToken) {
    res.status(401).json({
      success: false,
      error: { code: 'UNAUTHORIZED', message: 'Autenticação obrigatória para entrar na sala de voz.' },
    });
    return;
  }

  let claims;
  try {
    claims = jwt.verify(bearerToken, normalizePem(JWT_PUBLIC_KEY), {
      algorithms: ['RS256'],
      issuer: TOKEN_ISSUER,
    });
  } catch {
    res.status(401).json({
      success: false,
      error: { code: 'INVALID_TOKEN', message: 'Sessão inválida ou expirada. Faça login novamente.' },
    });
    return;
  }

  if (!claims.emailVerified) {
    res.status(403).json({
      success: false,
      error: { code: 'EMAIL_NOT_VERIFIED', message: 'Confirme seu e-mail para usar a voz.' },
    });
    return;
  }

  const room = (req.body && req.body.room) || 'v-geral';
  if (!ROOM_PATTERN.test(room)) {
    res.status(400).json({
      success: false,
      error: { code: 'INVALID_ROOM', message: 'Identificador de sala inválido.' },
    });
    return;
  }

  try {
    // A identity vem do JWT verificado, nunca do corpo da requisição.
    const identity = `@${claims.username}`;

    const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
      identity,
      name: claims.displayName,
      ttl: '2h',
    });

    at.addGrant({
      room,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });

    const token = await at.toJwt();

    res.status(200).json({
      success: true,
      data: {
        serverUrl: LIVEKIT_URL,
        token,
        room,
        identity,
        displayName: claims.displayName,
      },
    });
  } catch (error) {
    console.error('[livekit-token] Falha ao emitir token:', error);
    res.status(500).json({
      success: false,
      error: { code: 'TOKEN_ISSUE_FAILED', message: 'Não foi possível autorizar a entrada na sala.' },
    });
  }
};
