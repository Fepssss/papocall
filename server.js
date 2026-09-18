const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT || 3456;
const PUBLIC_DIR = path.join(__dirname, 'public');

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

  // LiveKit Cloud Token API
  if (pathname === '/api/livekit/token' || pathname === '/api/livekit-token') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.writeHead(200);
      res.end();
      return;
    }

    if (!AccessToken) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'livekit-server-sdk não carregado' }));
      return;
    }

    const room = urlObj.searchParams.get('room') || 'v-geral';
    const identity = urlObj.searchParams.get('identity') || `user_${Math.random().toString(36).substring(2, 9)}`;
    const name = urlObj.searchParams.get('name') || identity;

    const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
      identity,
      name,
    });

    at.addGrant({
      room,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });

    at.toJwt().then((token) => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        serverUrl: LIVEKIT_URL,
        token,
        room,
        identity,
        name
      }));
    }).catch((err) => {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: err.message }));
    });
    return;
  }

  let reqUrl = pathname;
  if (reqUrl === '/' || reqUrl === '') {
    reqUrl = '/index.html';
  }

  const filePath = path.join(PUBLIC_DIR, reqUrl);
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
      res.writeHead(200, { 'Content-Type': contentType });
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
const wss = new WebSocketServer({ server });

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

wss.on('connection', (ws) => {
  const userId = 'u-' + Math.random().toString(36).substring(2, 9);
  const user = {
    id: userId,
    username: '',
    voiceChannelId: null,
    isSpeaking: false,
    isMuted: false,
    isDeafened: false,
    isScreenSharing: false
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

      switch (msg.type) {
        case 'user:login': {
          user.username = (msg.data.username || 'Usuário').trim();
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
          const { channelId, text } = msg.data;
          if (!channelId || !text || !text.trim()) return;

          const now = new Date();
          const hours = String(now.getHours()).padStart(2, '0');
          const minutes = String(now.getMinutes()).padStart(2, '0');
          const timestamp = `Hoje às ${hours}:${minutes}`;

          const newMsg = {
            id: 'm-' + Date.now() + '-' + Math.random().toString(36).substr(2, 4),
            author: user.username,
            authorId: user.id,
            text: text.trim(),
            timestamp
          };

          if (!state.messages[channelId]) {
            state.messages[channelId] = [];
          }
          state.messages[channelId].push(newMsg);
          if (state.messages[channelId].length > 150) {
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
          const { channelId } = msg.data;
          const previousChannel = user.voiceChannelId;
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
          const { to, data } = msg.data;
          sendToUser(to, {
            type: 'webrtc:signal',
            data: {
              from: user.id,
              data
            }
          });
          break;
        }

        case 'voice:speaking': {
          user.isSpeaking = Boolean(msg.data.isSpeaking) && !user.isMuted;
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
          user.isMuted = Boolean(msg.data.isMuted);
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
          user.isDeafened = Boolean(msg.data.isDeafened);
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
          user.isScreenSharing = Boolean(msg.data.isSharing);
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
          const { name, type } = msg.data;
          if (!name || !name.trim()) return;
          const cleanName = name.trim().toLowerCase().replace(/\s+/g, '-');
          const id = (type === 'voice' ? 'v-' : 'c-') + Date.now();
          const newChan = {
            id,
            name: cleanName,
            type: type === 'voice' ? 'voice' : 'text',
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

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[PapoCall] Servidor ativo em todas as interfaces na porta ${PORT}`);
});
