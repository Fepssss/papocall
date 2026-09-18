const { AccessToken } = require('livekit-server-sdk');

const LIVEKIT_URL = process.env.LIVEKIT_URL || 'wss://seu-projeto.livekit.cloud';
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY || 'your_api_key_here';
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || 'your_api_secret_here';

module.exports = async (req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,PATCH,DELETE,POST,PUT');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version'
  );

  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  try {
    const room = req.query?.room || req.body?.room || 'v-geral';
    const identity = req.query?.identity || req.body?.identity || `user_${Math.random().toString(36).substring(2, 9)}`;
    const name = req.query?.name || req.body?.name || identity;

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

    const token = await at.toJwt();

    res.status(200).json({
      serverUrl: LIVEKIT_URL,
      token,
      room,
      identity,
      name,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
