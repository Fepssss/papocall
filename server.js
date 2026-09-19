const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT || 3456;
// Escuta apenas no loopback por padrao. A versao anterior usava 0.0.0.0, o que
// expunha o chat sem autenticacao para toda a rede local.
const HOST = process.env.HOST || '127.0.0.1';
const PUBLIC_DIR = path.join(__dirname, 'public');

// Origens autorizadas a abrir o WebSocket. Sem essa checagem, qualquer site
// aberto no navegador do usuario conseguia conectar em ws://localhost:3456,
// ler todo o historico de mensagens e publicar mensagens forjadas (CSWSH).
const ALLOWED_WS_ORIGINS = (process.env.ALLOWED_WS_ORIGINS ||
  `http://localhost:${PORT},http://127.0.0.1:${PORT}`)
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

const LIMITS = {
  messageBytes: 4 * 1024,
  messageTextLength: 2000,
  usernameLength: 32,
  channelNameLength: 32,
  maxChannels: 100,
  messagesPerChannel: 150,
  // Janela deslizante simples por conexao
  rateWindowMs: 10 * 1000,
  rateMaxMessages: 40,
};

// MIME types for static files
const MIME_TYPES = {
  '.html': 'text/html; charset=UTF-8',
  '.css': 'text/css; charset=UTF-8',
  '.js': 'application/javascript; charset=UTF-8',
  '.json': 'application/json; charset=UTF-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon'
};

// Application State
const state = {
  channels: [
    { id: 'c-geral', name: 'geral', type: 'text', topic: 'Canal de texto principal para todos os membros' },
    { id: 'c-avisos', name: 'avisos', type: 'text', topic: 'Comunicados e novidades do PapoCall' },
    { id: 'c-memes', name: 'memes', type: 'text', topic: 'Compartilhe memes e coisas divertidas' },
    { id: 'v-geral', name: 'Sala Geral', type: 'voice', userLimit: 15 },
    { id: 'v-jogos', name: 'Sala de Jogos', type: 'voice', userLimit: 6 },
    { id: 'v-batepapo', name: 'Bate-Papo Livre', type: 'voice', userLimit: 10 }
  ],
  messages: {
    'c-geral': [
      {
        id: 'm-1',
        author: 'Sistema',
        isSystem: true,
        text: 'Bem-vindo ao servidor PapoCall! Voz e transmissão de tela WebRTC ativas.',
        timestamp: 'Hoje às 12:00'
      }
    ],
    'c-avisos': [
      {
        id: 'm-2',
        author: 'Sistema',
        isSystem: true,
        text: 'Agora você pode conversar por voz e transmitir tela/janelas em tempo real via WebRTC.',
        timestamp: 'Hoje às 12:05'
      }
    ],
    'c-memes': []
  },
  users: new Map(), // ws -> user
  userSocketMap: new Map() // userId -> ws
};

let AccessToken;
try {
  ({ AccessToken } = require('livekit-server-sdk'));
} catch (e) {
  // Optional fallback
}

const LIVEKIT_URL = process.env.LIVEKIT_URL || 'wss://seu-projeto.livekit.cloud';
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY || 'your_api_key_here';
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || 'your_api_secret_here';

// HTTP Server
const server = http.createServer((req, res) => {
  const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = urlObj.pathname;

  // O endpoint de token do LiveKit foi REMOVIDO deste servidor.
  //
  // Ele emitia tokens sem qualquer autenticacao, aceitava a identity pela query
  // string e respondia com Access-Control-Allow-Origin: *, permitindo que
  // qualquer um assumisse a identidade de outro usuario e entrasse em qualquer
  // sala. A emissao de token agora acontece exclusivamente no backend
  // autenticado (backend/src/modules/livekit) ou em api/livekit-token.js.

  let reqUrl = pathname;
  if (reqUrl === '/' || reqUrl === '') {
    reqUrl = '/index.html';
  }

  const filePath = path.join(PUBLIC_DIR, reqUrl);

  // Defesa em profundidade: o parser de URL ja normaliza '..', mas a checagem
  // explicita garante que nenhum caminho escape de PUBLIC_DIR.
  if (filePath !== PUBLIC_DIR && !filePath.startsWith(PUBLIC_DIR + path.sep)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=UTF-8' });
    res.end('403 Acesso negado');
    return;
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      if (err.code === 'ENOENT') {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=UTF-8' });
        res.end('404 Arquivo não encontrado');
      } else {
        res.writeHead(500, { 'Content-Type': 'text/plain; charset=UTF-8' });
        res.end('500 Erro Interno');
      }
    } else {
      res.writeHead(200, {
        'Content-Type': contentType,
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
        'Referrer-Policy': 'no-referrer',
        'Content-Security-Policy':
          "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; connect-src 'self' ws: wss:; object-src 'none'; frame-ancestors 'none'",
      });
      res.end(content);
    }
  });
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.log(`[PapoCall] Porta ${PORT} já em uso.`);
  } else {
    console.error('[PapoCall] Erro:', err);
  }
});

// WebSocket Server
const wss = new WebSocketServer({
  server,
  maxPayload: LIMITS.messageBytes,
  verifyClient: ({ origin, req }, done) => {
    // Clientes nativos (Flutter) nao enviam Origin; navegadores sempre enviam.
    // Portanto, quando ha Origin, ela precisa estar na lista autorizada.
    if (!origin) return done(true);
    if (ALLOWED_WS_ORIGINS.includes(origin)) return done(true);

    console.warn(`[PapoCall] Conexao WebSocket bloqueada pela origem: ${origin} (${req.socket.remoteAddress})`);
    done(false, 403, 'Origem nao autorizada');
  },
});

function broadcast(data, excludeWs = null) {
  const message = JSON.stringify(data);
  for (const client of wss.clients) {
    if (client !== excludeWs && client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  }
}

function sendToUser(targetUserId, data) {
  const targetWs = state.userSocketMap.get(targetUserId);
  if (targetWs && targetWs.readyState === WebSocket.OPEN) {
    targetWs.send(JSON.stringify(data));
  }
}

function getActiveUsersList() {
  const list = [];
  for (const [ws, user] of state.users.entries()) {
    if (user.username) {
      list.push({
        id: user.id,
        username: user.username,
        voiceChannelId: user.voiceChannelId,
        isSpeaking: user.isSpeaking,
        isMuted: user.isMuted,
        isDeafened: user.isDeafened,
        isScreenSharing: Boolean(user.isScreenSharing)
      });
    }
  }
  return list;
}

/**
 * Normaliza texto vindo do cliente: forca string, remove caracteres de controle
 * (que quebram a renderizacao no cliente) e aplica um teto de tamanho.
 */
function sanitizeText(value, maxLength) {
  if (typeof value !== 'string') return '';
  return value
    // eslint-disable-next-line no-control-regex
    .replace(/[\u0000-\u001F\u007F]/g, ' ')
    .trim()
    .slice(0, maxLength);
}

/**
 * Limitador por conexao: impede que um unico cliente inunde o servidor e todos
 * os outros participantes com mensagens.
 */
function allowMessage(user) {
  const now = Date.now();
  if (now - user.rateWindowStart > LIMITS.rateWindowMs) {
    user.rateWindowStart = now;
    user.rateCount = 0;
  }
  user.rateCount += 1;
  return user.rateCount <= LIMITS.rateMaxMessages;
}

wss.on('connection', (ws) => {
  const userId = 'u-' + crypto.randomBytes(9).toString('hex');
  const user = {
    id: userId,
    username: '',
    voiceChannelId: null,
    isSpeaking: false,
    isMuted: false,
    isDeafened: false,
    isScreenSharing: false,
    rateWindowStart: Date.now(),
    rateCount: 0
  };
  state.users.set(ws, user);
  state.userSocketMap.set(userId, ws);

  ws.send(JSON.stringify({
    type: 'init',
    data: {
      userId,
      channels: state.channels,
      messages: state.messages,
      users: getActiveUsersList()
    }
  }));

  ws.on('message', (raw) => {
    try {
      const msg = JSON.parse(raw.toString());
      if (!msg || typeof msg.type !== 'string') return;
      if (!allowMessage(user)) return;

      const data = msg.data && typeof msg.data === 'object' ? msg.data : {};

      switch (msg.type) {
        case 'user:login': {
          user.username = sanitizeText(data.username, LIMITS.usernameLength) || 'Usuário';
          broadcast({
            type: 'user:joined',
            data: {
              user: {
                id: user.id,
                username: user.username,
                voiceChannelId: user.voiceChannelId,
                isSpeaking: user.isSpeaking,
                isMuted: user.isMuted,
                isDeafened: user.isDeafened,
                isScreenSharing: user.isScreenSharing
              }
            }
          });
          break;
        }

        case 'chat:send': {
          if (!user.username) return;
          const channelId = typeof data.channelId === 'string' ? data.channelId : '';
          const text = sanitizeText(data.text, LIMITS.messageTextLength);

          // Só aceita canais que realmente existem. Antes, qualquer string
          // criava uma nova entrada em state.messages, permitindo a um cliente
          // inflar a memoria do servidor indefinidamente.
          const channelExists = state.channels.some(
            (c) => c.id === channelId && c.type === 'text'
          );
          if (!channelExists || !text) return;

          const now = new Date();
          const hours = String(now.getHours()).padStart(2, '0');
          const minutes = String(now.getMinutes()).padStart(2, '0');
          const timestamp = `Hoje às ${hours}:${minutes}`;

          const newMsg = {
            id: 'm-' + Date.now() + '-' + crypto.randomBytes(4).toString('hex'),
            author: user.username,
            authorId: user.id,
            text: text.trim(),
            timestamp
          };

          if (!state.messages[channelId]) {
            state.messages[channelId] = [];
          }
          state.messages[channelId].push(newMsg);
          if (state.messages[channelId].length > LIMITS.messagesPerChannel) {
            state.messages[channelId].shift();
          }

          broadcast({
            type: 'chat:message',
            data: {
              channelId,
              message: newMsg
            }
          });
          break;
        }

        case 'voice:join': {
          const channelId = typeof data.channelId === 'string' ? data.channelId : null;
          const voiceExists = state.channels.some((c) => c.id === channelId && c.type === 'voice');
          if (!voiceExists) return;

          user.voiceChannelId = channelId;
          user.isSpeaking = false;

          // Notify existing peers in the same voice room to initiate WebRTC
          for (const [otherWs, otherUser] of state.users.entries()) {
            if (otherUser.id !== user.id && otherUser.voiceChannelId === channelId) {
              // Tell other user that this user joined (they will send an offer)
              otherWs.send(JSON.stringify({
                type: 'webrtc:peer-joined',
                data: {
                  peerId: user.id,
                  username: user.username,
                  isInitiator: true // other user will initiate offer to new user
                }
              }));
              // Also tell new user about other user
              ws.send(JSON.stringify({
                type: 'webrtc:peer-joined',
                data: {
                  peerId: otherUser.id,
                  username: otherUser.username,
                  isInitiator: false
                }
              }));
            }
          }

          broadcast({
            type: 'voice:update',
            data: {
              userId: user.id,
              voiceChannelId: user.voiceChannelId,
              isSpeaking: user.isSpeaking,
              isMuted: user.isMuted,
              isDeafened: user.isDeafened,
              isScreenSharing: user.isScreenSharing
            }
          });
          break;
        }

        case 'voice:leave': {
          const leftChannelId = user.voiceChannelId;
          user.voiceChannelId = null;
          user.isSpeaking = false;
          user.isScreenSharing = false;

          // Tell peers in that room that this user left
          for (const [otherWs, otherUser] of state.users.entries()) {
            if (otherUser.id !== user.id && otherUser.voiceChannelId === leftChannelId) {
              otherWs.send(JSON.stringify({
                type: 'webrtc:peer-left',
                data: { peerId: user.id }
              }));
            }
          }

          broadcast({
            type: 'voice:update',
            data: {
              userId: user.id,
              voiceChannelId: null,
              isSpeaking: false,
              isMuted: user.isMuted,
              isDeafened: user.isDeafened,
              isScreenSharing: false
            }
          });
          break;
        }

        // WebRTC Signaling Relay (Offer, Answer, ICE Candidates)
        case 'webrtc:signal': {
          const to = typeof data.to === 'string' ? data.to : '';
          const target = state.users.get(state.userSocketMap.get(to));
          // So repassa sinalizacao entre usuarios que estao na MESMA sala de voz:
          // antes era possivel forcar uma negociacao WebRTC com qualquer usuario
          // conectado e assim descobrir o IP dele.
          if (!to || !target || !user.voiceChannelId || target.voiceChannelId !== user.voiceChannelId) return;
          sendToUser(to, {
            type: 'webrtc:signal',
            data: {
              from: user.id,
              data: data.data
            }
          });
          break;
        }

        case 'voice:speaking': {
          user.isSpeaking = Boolean(data.isSpeaking) && !user.isMuted;
          broadcast({
            type: 'voice:speaking',
            data: {
              userId: user.id,
              isSpeaking: user.isSpeaking
            }
          });
          break;
        }

        case 'voice:set-mute': {
          user.isMuted = Boolean(data.isMuted);
          if (user.isMuted) user.isSpeaking = false;
          broadcast({
            type: 'voice:state',
            data: {
              userId: user.id,
              isMuted: user.isMuted,
              isDeafened: user.isDeafened,
              isSpeaking: user.isSpeaking,
              isScreenSharing: user.isScreenSharing
            }
          });
          break;
        }

        case 'voice:set-deafen': {
          user.isDeafened = Boolean(data.isDeafened);
          if (user.isDeafened) {
            user.isMuted = true;
            user.isSpeaking = false;
          }
          broadcast({
            type: 'voice:state',
            data: {
              userId: user.id,
              isMuted: user.isMuted,
              isDeafened: user.isDeafened,
              isSpeaking: user.isSpeaking,
              isScreenSharing: user.isScreenSharing
            }
          });
          break;
        }

        case 'voice:screenshare': {
          user.isScreenSharing = Boolean(data.isSharing);
          broadcast({
            type: 'voice:screenshare',
            data: {
              userId: user.id,
              isScreenSharing: user.isScreenSharing,
              voiceChannelId: user.voiceChannelId
            }
          });
          break;
        }

        case 'channel:create': {
          if (!user.username) return;
          if (state.channels.length >= LIMITS.maxChannels) return;

          const name = sanitizeText(data.name, LIMITS.channelNameLength);
          const type = data.type === 'voice' ? 'voice' : 'text';
          if (!name) return;

          // Restringe o nome a um conjunto seguro de caracteres.
          const cleanName = name
            .toLowerCase()
            .replace(/\s+/g, '-')
            .replace(/[^a-z0-9\-_]/g, '');
          if (!cleanName) return;
          const id = (type === 'voice' ? 'v-' : 'c-') + Date.now() + '-' + crypto.randomBytes(3).toString('hex');
          const newChan = {
            id,
            name: cleanName,
            type,
            topic: type === 'voice' ? 'Sala de voz criada por usuário' : `Canal #${cleanName}`
          };
          state.channels.push(newChan);
          if (newChan.type === 'text') {
            state.messages[newChan.id] = [];
          }

          broadcast({
            type: 'channel:created',
            data: { channel: newChan }
          });
          break;
        }
      }
    } catch (e) {
      console.error('[PapoCall] Erro:', e);
    }
  });

  ws.on('close', () => {
    const exitedUser = state.users.get(ws);
    state.users.delete(ws);
    state.userSocketMap.delete(userId);

    if (exitedUser && exitedUser.voiceChannelId) {
      for (const [otherWs, otherUser] of state.users.entries()) {
        if (otherUser.voiceChannelId === exitedUser.voiceChannelId) {
          otherWs.send(JSON.stringify({
            type: 'webrtc:peer-left',
            data: { peerId: exitedUser.id }
          }));
        }
      }
    }

    if (exitedUser && exitedUser.username) {
      broadcast({
        type: 'user:left',
        data: { userId: exitedUser.id }
      });
    }
  });
});

server.listen(PORT, HOST, () => {
  console.log(`[PapoCall] Servidor ativo em http://${HOST}:${PORT}`);
  if (HOST !== '127.0.0.1') {
    console.warn('[PapoCall] ATENCAO: o servidor esta exposto na rede e NAO possui autenticacao.');
  }
});
