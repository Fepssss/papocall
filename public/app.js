/**
 * ProjetoUS - Client 100% Online na Nuvem 24/7 (WebRTC + Cloud Pub/Sub)
 * Suporte a múltiplos servidores estilo HUD, links próprios de convite,
 * avatares e fotos personalizadas, e persistência permanente de mensagens.
 */

const DEFAULT_SERVER_ID = 'server-default';
const DEFAULT_SERVER = {
  id: DEFAULT_SERVER_ID,
  name: 'ProjetoUS',
  icon: '',
  inviteCode: 'projetous-oficial',
  channels: [
    { id: 'c-geral', name: 'geral', type: 'text', topic: 'Canal de texto principal' },
    { id: 'c-avisos', name: 'avisos', type: 'text', topic: 'Novidades e comunicados' },
    { id: 'c-memes', name: 'memes', type: 'text', topic: 'Memes e imagens' },
    { id: 'v-geral', name: 'Sala Geral', type: 'voice', userLimit: 15 },
    { id: 'v-jogos', name: 'Sala de Jogos', type: 'voice', userLimit: 6 },
    { id: 'v-batepapo', name: 'Bate-Papo Livre', type: 'voice', userLimit: 10 }
  ]
};

const GIF_CATEGORIES = [
  { id: 'all', name: 'Todos' },
  { id: 'alta', name: '🔥 Em Alta' },
  { id: 'risada', name: '😂 Risada' },
  { id: 'reacao', name: '😲 Reações' },
  { id: 'danca', name: '💃 Dança' },
  { id: 'jogos', name: '🎮 Jogos' },
  { id: 'anime', name: '✨ Anime' },
  { id: 'gatos', name: '🐱 Gatos' }
];

const GIF_DATABASE = [
  // Em Alta
  { title: 'Popcat', category: 'alta', url: 'https://media.giphy.com/media/jpbnoe3UIa8TU8LM13/giphy.gif' },
  { title: 'High Five', category: 'alta', url: 'https://media.giphy.com/media/artj92V8o75VPL7AeQ/giphy.gif' },
  { title: 'Thumbs Up', category: 'alta', url: 'https://media.giphy.com/media/111ebonMs90YLu/giphy.gif' },
  { title: 'Mind Blown', category: 'alta', url: 'https://media.giphy.com/media/26ufdipQqU2lhNA4g/giphy.gif' },
  { title: 'Clap Clap', category: 'alta', url: 'https://media.giphy.com/media/nbvFVPiEiJH6JOGIok/giphy.gif' },
  { title: 'Excited', category: 'alta', url: 'https://media.giphy.com/media/5GoVLqeAOo6PK/giphy.gif' },

  // Risada / Memes
  { title: 'Chorando de Rir', category: 'risada', url: 'https://media.giphy.com/media/10JhviFuU2gWD6/giphy.gif' },
  { title: 'Gato Rindo', category: 'risada', url: 'https://media.giphy.com/media/ICOgUNjpvO0PC/giphy.gif' },
  { title: 'Rindo Muito', category: 'risada', url: 'https://media.giphy.com/media/3oEjHAUOqG3lSS0f1C/giphy.gif' },
  { title: 'Risada Cão', category: 'risada', url: 'https://media.giphy.com/media/ZqlvCTNHpqrio/giphy.gif' },
  { title: 'Lol Kermit', category: 'risada', url: 'https://media.giphy.com/media/9MFsKQ8A6HCN2/giphy.gif' },
  { title: 'Risada Maligna', category: 'risada', url: 'https://media.giphy.com/media/XVbQsIjdXDNysqqxN6/giphy.gif' },

  // Reações
  { title: 'Pikachu Chocado', category: 'reacao', url: 'https://media.giphy.com/media/6nWhy3ulBL7GSCvKw6/giphy.gif' },
  { title: 'Facepalm', category: 'reacao', url: 'https://media.giphy.com/media/3og0INyCmHlNylks9O/giphy.gif' },
  { title: 'John Travolta Confuso', category: 'reacao', url: 'https://media.giphy.com/media/g01ZnwAUvutuK8GIQn/giphy.gif' },
  { title: 'Pensando', category: 'reacao', url: 'https://media.giphy.com/media/d3mlE7uhX8KFgEmY/giphy.gif' },
  { title: 'Uau Impressionado', category: 'reacao', url: 'https://media.giphy.com/media/5VKbvrjxpVJCM/giphy.gif' },
  { title: 'Nervoso Suando', category: 'reacao', url: 'https://media.giphy.com/media/32mC2kXYWCsg0/giphy.gif' },
  { title: 'Não Acredito', category: 'reacao', url: 'https://media.giphy.com/media/l4Ho0At2UD2d7WyD6/giphy.gif' },

  // Dança
  { title: 'Gato Dançando', category: 'danca', url: 'https://media.giphy.com/media/GeimqsH0TLDt4tScGw/giphy.gif' },
  { title: 'Carlton Dança', category: 'danca', url: 'https://media.giphy.com/media/pa37AAGzKXoek/giphy.gif' },
  { title: 'Papagaio Rave', category: 'danca', url: 'https://media.giphy.com/media/l3q2wJsC23ikJg9xe/giphy.gif' },
  { title: 'Cachorro Dançando', category: 'danca', url: 'https://media.giphy.com/media/blSTtZehjAZ8I/giphy.gif' },
  { title: 'Snoop Dogg Dançando', category: 'danca', url: 'https://media.giphy.com/media/bC9czlgCMtw4cj8RgH/giphy.gif' },
  { title: 'Dança da Vitória', category: 'danca', url: 'https://media.giphy.com/media/3o7abKhOpu0NwenH3O/giphy.gif' },

  // Jogos
  { title: 'GG Good Game', category: 'jogos', url: 'https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif' },
  { title: 'Gamer Rage', category: 'jogos', url: 'https://media.giphy.com/media/11tTNkNy1SdXGg/giphy.gif' },
  { title: 'Among Us Dançando', category: 'jogos', url: 'https://media.giphy.com/media/RtdRhc7TxBxB0YAsK6/giphy.gif' },
  { title: 'Minecraft Vitória', category: 'jogos', url: 'https://media.giphy.com/media/cuHjncTuHW40g/giphy.gif' },
  { title: 'Pro Gamer Move', category: 'jogos', url: 'https://media.giphy.com/media/7k2LoEykY5i1hfeWQB/giphy.gif' },
  { title: 'Game Over', category: 'jogos', url: 'https://media.giphy.com/media/10h8Cd3DKddZDO/giphy.gif' },

  // Anime
  { title: 'Anime Wow', category: 'anime', url: 'https://media.giphy.com/media/11ISwbgCxEzMyY/giphy.gif' },
  { title: 'Anime Feliz', category: 'anime', url: 'https://media.giphy.com/media/slVWEctHZKvWU/giphy.gif' },
  { title: 'Anime Palmas', category: 'anime', url: 'https://media.giphy.com/media/aLdiZJmmx4OVW/giphy.gif' },
  { title: 'Anime Correndo', category: 'anime', url: 'https://media.giphy.com/media/f9jxYYRVPHtKs/giphy.gif' },
  { title: 'Anime Choque', category: 'anime', url: 'https://media.giphy.com/media/b1hyv7kZ7hXvUe102P/giphy.gif' },

  // Gatos
  { title: 'Gato Digitador', category: 'gatos', url: 'https://media.giphy.com/media/ule4akeEDWAY8/giphy.gif' },
  { title: 'Gato Cabeçada', category: 'gatos', url: 'https://media.giphy.com/media/BzyTuYCmvSORqs1ABM/giphy.gif' },
  { title: 'Gato Abraço', category: 'gatos', url: 'https://media.giphy.com/media/VbAmVUETR8cA6d20UM/giphy.gif' },
  { title: 'Gatinho Dormindo', category: 'gatos', url: 'https://media.giphy.com/media/3o6Zt481isNVuQI1l6/giphy.gif' }
];

const state = {
  currentUser: {
    id: 'u-' + Math.random().toString(36).substring(2, 9),
    username: '',
    avatar: '',
    status: 'online'
  },
  userStatusPreference: 'online',
  servers: [ DEFAULT_SERVER ],
  activeServerId: DEFAULT_SERVER_ID,
  // messages: { [serverId]: { [channelId]: [ ... ] } }
  messages: {},
  users: [], // users in active server
  globalUsers: new Map(), // userId -> { id, username, avatar, servers: [], activeServerId, voiceServerId, voiceChannelId, isSpeaking, isMuted, isDeafened, isScreenSharing, lastSeen }
  knownUsers: {}, // userId -> { id, username, avatar, updatedAt }
  activeChannel: null,
  connectedVoiceChannel: null,
  pendingMoveUser: null,
  tempServerIcon: '',
  tempUserAvatar: '',
  tempEditServerIcon: '',
  activeGifCategory: 'all',
  isMuted: false,
  isDeafened: false,
  isSharingScreen: false,
  screenStream: null,
  screenshareSettings: {
    targetSurface: 'window',
    selectedSourceId: 'window-app',
    resolution: '720p',
    fps: 30,
    shareAudio: true
  },
  isCameraOn: false,
  cameraStream: null,
  isLoungeFullscreen: false,
  userVolumes: {}, // userId -> volume percentage (default 100)
  localAudioStream: null,
  seenMessageIds: new Set(['m-init']),
  unreadCounts: {}, // channelId -> unread count
  lastViewedUnreadCount: 0,
  replyingTo: null, // { id, author, text, authorId }
  mqtt: null
};

// WebRTC State
const rtc = {
  config: {
    iceServers: [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:stun1.l.google.com:19302' },
      { urls: 'stun:stun2.l.google.com:19302' }
    ]
  },
  peers: new Map(), // peerId -> RTCPeerConnection
  remoteAudios: new Map(), // peerId -> HTMLAudioElement
  remoteGains: new Map(), // peerId -> GainNode (Web Audio API volume amplification 0-200%)
  iceCandidateQueues: new Map(), // peerId -> Array of RTCIceCandidateInit
  screenSenders: new Map() // peerId -> RTCRtpSender
};

// DOM Elements Cache
const dom = {
  // Server Header & Rail
  serverRail: document.getElementById('server-rail'),
  appLeftPanel: document.querySelector('.app-left-panel'),
  serverIconsList: document.getElementById('server-icons-list'),
  btnAddServer: document.getElementById('btn-add-server'),
  btnMaximizeServers: document.getElementById('btn-maximize-servers'),
  btnCollapseServerRail: document.getElementById('btn-collapse-server-rail'),
  btnExpandServerRail: document.getElementById('btn-expand-server-rail'),
  serverHeader: document.getElementById('server-header'),
  currentServerName: document.getElementById('current-server-name'),
  serverHeaderAvatar: document.getElementById('server-header-avatar'),
  btnOpenInvite: document.getElementById('btn-open-invite'),
  sidebarServerStatus: document.getElementById('sidebar-server-status'),
  btnServerMenu: document.getElementById('btn-server-menu'),
  serverDropdownMenu: document.getElementById('server-dropdown-menu'),
  menuItemInvite: document.getElementById('menu-item-invite'),
  menuItemSettings: document.getElementById('menu-item-settings'),
  menuItemLeave: document.getElementById('menu-item-leave'),

  // Login
  loginModal: document.getElementById('login-modal'),
  loginForm: document.getElementById('login-form'),
  usernameInput: document.getElementById('username-input'),

  // Create / Join Server Modal
  createServerModal: document.getElementById('create-server-modal'),
  serverModalTitle: document.getElementById('server-modal-title'),
  tabBtnCreateServer: document.getElementById('tab-btn-create-server'),
  tabBtnJoinServer: document.getElementById('tab-btn-join-server'),
  viewCreateServer: document.getElementById('view-create-server'),
  viewJoinServer: document.getElementById('view-join-server'),
  createServerForm: document.getElementById('create-server-form'),
  newServerNameInput: document.getElementById('new-server-name-input'),
  serverIconFile: document.getElementById('server-icon-file'),
  serverIconUrl: document.getElementById('server-icon-url'),
  serverIconPreview: document.getElementById('server-icon-preview'),
  btnCancelCreateServer: document.getElementById('btn-cancel-create-server'),
  btnCloseCreateServerX: document.getElementById('btn-close-create-server-x'),
  joinServerForm: document.getElementById('join-server-form'),
  joinServerInput: document.getElementById('join-server-input'),
  btnCancelJoinServer: document.getElementById('btn-cancel-join-server'),

  // Invite Modal
  inviteModal: document.getElementById('invite-modal'),
  inviteModalTitle: document.getElementById('invite-modal-title'),
  inviteLinkInput: document.getElementById('invite-link-input'),
  btnCopyInvite: document.getElementById('btn-copy-invite'),
  btnCancelInvite: document.getElementById('btn-cancel-invite'),
  btnCloseInviteX: document.getElementById('btn-close-invite-x'),

  // Channel Creation Modal
  channelModal: document.getElementById('channel-modal'),
  channelForm: document.getElementById('channel-form'),
  channelNameInput: document.getElementById('channel-name-input'),
  btnCancelChannel: document.getElementById('btn-cancel-channel'),
  btnAddTextChannel: document.getElementById('btn-add-text-channel'),
  btnAddVoiceChannel: document.getElementById('btn-add-voice-channel'),
  optionTextChan: document.getElementById('option-text-chan'),
  optionVoiceChan: document.getElementById('option-voice-chan'),

  // Channel Categories & Lists
  categoryText: document.getElementById('category-text'),
  categoryHeaderText: document.getElementById('category-header-text'),
  textChannelsList: document.getElementById('text-channels-list'),
  categoryVoice: document.getElementById('category-voice'),
  categoryHeaderVoice: document.getElementById('category-header-voice'),
  voiceChannelsList: document.getElementById('voice-channels-list'),

  // Topbar
  btnRefreshApp: document.getElementById('btn-refresh-app'),
  topbarChannelIcon: document.getElementById('topbar-channel-icon'),
  topbarChannelName: document.getElementById('topbar-channel-name'),
  topbarChannelTopic: document.getElementById('topbar-channel-topic'),
  topbarVoiceBadge: document.getElementById('topbar-voice-badge'),
  topbarVoiceBadgeText: document.getElementById('topbar-voice-badge-text'),

  // Chat Section
  chatSection: document.getElementById('chat-section'),
  messagesContainer: document.getElementById('messages-container'),
  messagesFeed: document.getElementById('messages-feed'),
  channelWelcomeBanner: document.getElementById('channel-welcome-banner'),
  welcomeTitle: document.getElementById('welcome-title'),
  welcomeDesc: document.getElementById('welcome-desc'),
  chatInput: document.getElementById('chat-input'),
  chatBtnGif: document.getElementById('chat-btn-gif'),
  chatBtnEmoji: document.getElementById('chat-btn-emoji'),
  chatSendBtn: document.getElementById('chat-send-btn'),
  emojiPickerPopover: document.getElementById('emoji-picker-popover'),
  emojiSearchInput: document.getElementById('emoji-search-input'),
  emojiPickerScroll: document.getElementById('emoji-picker-scroll'),
  btnCloseEmojiPicker: document.getElementById('btn-close-emoji-picker'),
  chatReplyBar: document.getElementById('chat-reply-bar'),
  replyBarAuthor: document.getElementById('reply-bar-author'),
  replyBarSnippet: document.getElementById('reply-bar-snippet'),
  btnCancelReply: document.getElementById('btn-cancel-reply'),

  // Voice Lounge Section (Voice Stage)
  voiceLoungeSection: document.getElementById('voice-lounge-section'),
  loungeRoomTitle: document.getElementById('lounge-room-title'),
  loungeStage: document.getElementById('lounge-stage'),
  loungeRtcBadge: document.getElementById('lounge-rtc-badge'),
  loungeRtcStatusText: document.getElementById('lounge-rtc-status-text'),
  loungeMembersBadge: document.getElementById('lounge-members-badge'),
  loungeMembersCount: document.getElementById('lounge-members-count'),
  loungeBtnFullscreen: document.getElementById('lounge-btn-fullscreen'),
  loungeMembersGrid: document.getElementById('lounge-members-grid'),
  loungeEmptyState: document.getElementById('lounge-empty-state'),
  loungeBtnEmptyJoin: document.getElementById('lounge-btn-empty-join'),
  meterBarFill: document.getElementById('meter-bar-fill'),
  meterLevelValue: document.getElementById('meter-level-value'),
  meterThresholdMarker: document.getElementById('meter-threshold-marker'),
  meterSlider: document.getElementById('meter-slider'),
  loungeMeterPopover: document.getElementById('lounge-meter-popover'),
  btnCloseMeterPopover: document.getElementById('btn-close-meter-popover'),
  loungeFloatingDock: document.getElementById('lounge-floating-dock'),
  loungeDockMic: document.getElementById('lounge-dock-mic'),
  loungeDockDeafen: document.getElementById('lounge-dock-deafen'),
  loungeDockScreenshare: document.getElementById('lounge-dock-screenshare'),
  loungeDockCamera: document.getElementById('lounge-dock-camera'),
  loungeDockMeterBtn: document.getElementById('lounge-dock-meter-btn'),
  loungeDockFullscreen: document.getElementById('lounge-dock-fullscreen'),
  loungeDockDisconnect: document.getElementById('lounge-dock-disconnect'),
  loungeDisconnectBtn: document.getElementById('lounge-disconnect-btn'),
  loungeBtnScreenshare: document.getElementById('lounge-btn-screenshare'),
  loungeBtnScreenshareSettings: document.getElementById('lounge-btn-screenshare-settings'),
  loungeScreenshareText: document.getElementById('lounge-screenshare-text'),

  // Screen Share View
  screenshareDisplayContainer: document.getElementById('screenshare-display-container'),
  screenshareStreamerName: document.getElementById('screenshare-streamer-name'),
  screenshareVideo: document.getElementById('screenshare-video'),
  screenshareQualityTag: document.getElementById('screenshare-quality-tag'),
  btnVideoQuality: document.getElementById('btn-video-quality'),
  btnVideoFullscreen: document.getElementById('btn-video-fullscreen'),
  btnVideoStop: document.getElementById('btn-video-stop'),

  // Screen Share Modal & Quality Controls
  screenshareModal: document.getElementById('screenshare-modal'),
  screenshareModalTitle: document.getElementById('screenshare-modal-title'),
  screenshareModalSubtitle: document.getElementById('screenshare-modal-subtitle'),
  btnCloseScreenshareX: document.getElementById('btn-close-screenshare-x'),
  btnCancelScreenshare: document.getElementById('btn-cancel-screenshare'),
  btnStopFromModal: document.getElementById('btn-stop-from-modal'),
  btnConfirmScreenshare: document.getElementById('btn-confirm-screenshare'),
  btnConfirmScreenshareText: document.getElementById('btn-confirm-screenshare-text'),
  tabBtnScreenshareWindows: document.getElementById('tab-btn-screenshare-windows'),
  tabBtnScreenshareScreens: document.getElementById('tab-btn-screenshare-screens'),
  screenshareHintText: document.getElementById('screenshare-hint-text'),
  viewScreenshareWindows: document.getElementById('view-screenshare-windows'),
  viewScreenshareScreens: document.getElementById('view-screenshare-screens'),
  screenshareWindowsGrid: document.getElementById('screenshare-windows-grid'),
  screenshareScreensGrid: document.getElementById('screenshare-screens-grid'),
  pillsResolution: document.getElementById('pills-resolution'),
  pillsFps: document.getElementById('pills-fps'),
  valCurrentResolution: document.getElementById('val-current-resolution'),
  valCurrentFps: document.getElementById('val-current-fps'),
  screenshareQualitySummary: document.getElementById('screenshare-quality-summary'),
  screenshareAudioCheckbox: document.getElementById('screenshare-audio-checkbox'),

  // Voice Status Panel
  voiceStatusPanel: document.getElementById('voice-status-panel'),
  voiceStatusRoomName: document.getElementById('voice-status-room-name'),
  btnScreenshareVoice: document.getElementById('btn-screenshare-voice'),
  btnDisconnectVoice: document.getElementById('btn-disconnect-voice'),

  // User Profile Bar
  userProfileTrigger: document.getElementById('user-profile-trigger'),
  myAvatar: document.getElementById('my-avatar'),
  myStatusIndicator: document.getElementById('my-status-indicator'),
  myUsername: document.getElementById('my-username'),
  myStatusText: document.getElementById('my-status-text'),
  btnToggleMute: document.getElementById('btn-toggle-mute'),
  btnToggleDeafen: document.getElementById('btn-toggle-deafen'),
  btnSettings: document.getElementById('btn-settings'),
  btnLogout: document.getElementById('btn-logout'),

  // Status Popover
  userStatusPopover: document.getElementById('user-status-popover'),
  popoverAvatar: document.getElementById('popover-avatar'),
  popoverStatusIndicator: document.getElementById('popover-status-indicator'),
  popoverUsername: document.getElementById('popover-username'),
  popoverBtnSettings: document.getElementById('popover-btn-settings'),

  // Settings Modal
  settingsModal: document.getElementById('settings-modal'),
  settingsForm: document.getElementById('settings-form'),
  settingsUsernameInput: document.getElementById('settings-username-input'),
  settingsAvatarFile: document.getElementById('settings-avatar-file'),
  settingsAvatarUrl: document.getElementById('settings-avatar-url'),
  btnRemoveAvatar: document.getElementById('btn-remove-avatar'),
  settingsPreviewAvatar: document.getElementById('settings-preview-avatar'),
  settingsPreviewStatusIndicator: document.getElementById('settings-preview-status-indicator'),
  settingsPreviewName: document.getElementById('settings-preview-name'),
  settingsPreviewStatus: document.getElementById('settings-preview-status'),
  settingsStatusGrid: document.getElementById('settings-status-grid'),
  btnCancelSettings: document.getElementById('btn-cancel-settings'),
  btnCloseSettingsX: document.getElementById('btn-close-settings-x'),
  tabBtnSettingsProfile: document.getElementById('tab-btn-settings-profile'),
  tabBtnSettingsTheme: document.getElementById('tab-btn-settings-theme'),
  viewSettingsProfile: document.getElementById('view-settings-profile'),
  viewSettingsTheme: document.getElementById('view-settings-theme'),
  btnCloseThemeTab: document.getElementById('btn-close-theme-tab'),

  // Move User Modal
  moveModal: document.getElementById('move-modal'),
  moveModalTitle: document.getElementById('move-modal-title'),
  moveModalSubtitle: document.getElementById('move-modal-subtitle'),
  moveChannelsList: document.getElementById('move-channels-list'),
  btnCancelMove: document.getElementById('btn-cancel-move'),
  btnCloseMoveX: document.getElementById('btn-close-move-x'),

  // Toast Container
  toastContainer: document.getElementById('toast-container'),

  // Members Sidebar (Right Side - Online Members Only)
  membersSidebar: document.getElementById('members-sidebar'),
  onlineMembersList: document.getElementById('online-members-list'),
  membersOnlineCount: document.getElementById('members-online-count'),
  btnToggleMembersSidebar: document.getElementById('btn-toggle-members-sidebar'),

  // Server Settings Modal (Gear button beside server name)
  btnServerSettings: document.getElementById('btn-server-settings'),
  serverSettingsModal: document.getElementById('server-settings-modal'),
  serverSettingsTitle: document.getElementById('server-settings-title'),
  serverSettingsSubtitle: document.getElementById('server-settings-subtitle'),
  serverSettingsForm: document.getElementById('server-settings-form'),
  editServerIconFile: document.getElementById('edit-server-icon-file'),
  editServerIconUrl: document.getElementById('edit-server-icon-url'),
  editServerIconPreview: document.getElementById('edit-server-icon-preview'),
  btnRemoveServerIcon: document.getElementById('btn-remove-server-icon'),
  editServerNameInput: document.getElementById('edit-server-name-input'),
  editServerInviteInput: document.getElementById('edit-server-invite-input'),
  btnCopyEditInvite: document.getElementById('btn-copy-edit-invite'),
  serverDangerZone: document.getElementById('server-danger-zone'),
  btnDeleteServer: document.getElementById('btn-delete-server'),
  btnCancelServerSettings: document.getElementById('btn-cancel-server-settings'),
  btnCloseServerSettingsX: document.getElementById('btn-close-server-settings-x'),

  // GIF Picker Modal & Chat GIF Button
  chatBtnGif: document.getElementById('chat-btn-gif'),
  gifPickerModal: document.getElementById('gif-picker-modal'),
  btnCloseGifX: document.getElementById('btn-close-gif-x'),
  gifSearchInput: document.getElementById('gif-search-input'),
  btnClearGifSearch: document.getElementById('btn-clear-gif-search'),
  gifCategoryChips: document.getElementById('gif-category-chips'),
  gifGrid: document.getElementById('gif-grid'),
  gifCustomUrlInput: document.getElementById('gif-custom-url-input'),
  btnSendCustomGif: document.getElementById('btn-send-custom-gif'),

  // Full-Window Server Hub
  serverHubModal: document.getElementById('server-hub-modal'),
  serverHubGrid: document.getElementById('server-hub-grid'),
  serverHubSearchInput: document.getElementById('server-hub-search-input'),
  btnClearHubSearch: document.getElementById('btn-clear-hub-search'),
  serverHubSubtitle: document.getElementById('server-hub-subtitle'),
  serverHubCountBadge: document.getElementById('server-hub-count-badge'),
  serverHubEmpty: document.getElementById('server-hub-empty'),
  serverHubEmptyDesc: document.getElementById('server-hub-empty-desc'),
  btnHubCreateServer: document.getElementById('btn-hub-create-server'),
  btnCloseServerHub: document.getElementById('btn-close-server-hub'),

  // Universal Context Menu
  appContextMenu: document.getElementById('app-context-menu')
};

const audioContainer = document.createElement('div');
audioContainer.id = 'remote-audios-container';
audioContainer.style.display = 'none';
document.body.appendChild(audioContainer);

// --- Toast System ---
function showToast(message, type = 'info', duration = 3500) {
  if (!dom.toastContainer) return;
  const toast = document.createElement('div');
  toast.className = 'toast-item ' + type;
  const icon = type === 'success' ? '✓' : (type === 'warning' ? '⚠' : 'ℹ');
  toast.innerHTML = '<span>' + icon + '</span><span>' + escapeHtml(message) + '</span>';
  dom.toastContainer.appendChild(toast);

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateX(100%)';
    setTimeout(() => toast.remove(), 300);
  }, duration);
}

// --- Active Server & Channels Helpers ---
function getActiveServer() {
  return state.servers.find(s => s.id === state.activeServerId) || state.servers[0];
}

function getActiveServerChannels() {
  const srv = getActiveServer();
  return srv ? srv.channels : [];
}

// --- App Initialization ---
function initApp() {
  loadStoredTheme();
  loadStoredServers();
  loadStoredMessages();
  loadCategoryCollapseState();
  setupEventListeners();
  setupAudioCallbacks();

  // Load Saved User Profile
  let savedUserId = localStorage.getItem('projetous_user_id');
  if (!savedUserId) {
    savedUserId = 'u-' + Math.random().toString(36).substring(2, 9);
    localStorage.setItem('projetous_user_id', savedUserId);
  }
  state.currentUser.id = savedUserId;

  const savedUsername = localStorage.getItem('projetous_username');
  const savedAvatar = localStorage.getItem('projetous_avatar');
  if (savedAvatar) state.currentUser.avatar = savedAvatar;

  const savedStatus = localStorage.getItem('projetous_user_status');
  if (savedStatus && ['online', 'idle', 'dnd'].includes(savedStatus)) {
    state.currentUser.status = savedStatus;
    state.userStatusPreference = savedStatus;
  } else {
    state.currentUser.status = 'online';
    state.userStatusPreference = 'online';
  }

  loadStoredKnownUsers();

  if (savedUsername) {
    state.knownUsers[savedUserId] = {
      id: savedUserId,
      username: savedUsername,
      avatar: savedAvatar || '',
      updatedAt: Date.now()
    };
    saveStoredKnownUsers();
  }

  renderServerRail();
  selectServer(state.activeServerId, false);
  collapseServerRail(false);

  if (savedUsername) {
    login(savedUsername);
  } else {
    dom.loginModal.classList.remove('hidden');
    dom.usernameInput.focus();
  }

  // Handle URL Invite Link (?invite=... or ?server=...)
  checkUrlInvite();
}

function loadStoredServers() {
  try {
    const raw = localStorage.getItem('projetous_servers_v3')
             || localStorage.getItem('projetous_servers_v2')
             || localStorage.getItem('projetous_servers_v1')
             || localStorage.getItem('projetous_servers')
             || localStorage.getItem('papocall_servers_fallback');
    if (raw) {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed) && parsed.length > 0) {
        state.servers = parsed;
        if (!state.servers.some(s => s.id === DEFAULT_SERVER_ID)) {
          state.servers.unshift(DEFAULT_SERVER);
        }
      }
    }
  } catch (e) {
    console.warn('[ProjetoUS] Erro ao carregar servidores locais:', e);
  }
}

function saveStoredServers() {
  try {
    const data = JSON.stringify(state.servers);
    localStorage.setItem('projetous_servers_v3', data);
    localStorage.setItem('projetous_servers_v2', data);
    localStorage.setItem('projetous_servers', data);
  } catch (e) {
    console.warn('[ProjetoUS] Erro ao salvar servidores:', e);
  }
}

// --- Category Collapsing Handling ---
let categoryCollapseState = {
  text: false,
  voice: false
};

function loadCategoryCollapseState() {
  try {
    const raw = localStorage.getItem('projetous_collapsed_categories');
    if (raw) {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object') {
        categoryCollapseState = Object.assign(categoryCollapseState, parsed);
      }
    }
  } catch (e) {
    console.warn('[ProjetoUS] Erro ao carregar categorias recolhidas:', e);
  }
  applyCategoryCollapseState();
}

function saveCategoryCollapseState() {
  try {
    localStorage.setItem('projetous_collapsed_categories', JSON.stringify(categoryCollapseState));
  } catch (e) {
    console.warn('[ProjetoUS] Erro ao salvar categorias recolhidas:', e);
  }
}

function applyCategoryCollapseState() {
  const catText = dom.categoryText || document.getElementById('category-text');
  const catVoice = dom.categoryVoice || document.getElementById('category-voice');
  if (catText) {
    catText.classList.toggle('collapsed', !!categoryCollapseState.text);
  }
  if (catVoice) {
    catVoice.classList.toggle('collapsed', !!categoryCollapseState.voice);
  }
}

function toggleCategoryCollapse(type) {
  if (type === 'text') {
    categoryCollapseState.text = !categoryCollapseState.text;
  } else if (type === 'voice') {
    categoryCollapseState.voice = !categoryCollapseState.voice;
  }
  saveCategoryCollapseState();
  applyCategoryCollapseState();
}

// --- Color Themes Management ---
function loadStoredTheme() {
  const savedTheme = localStorage.getItem('projetous_theme') || 'soft';
  applyTheme(savedTheme, false);
}

function applyTheme(themeId, notify = true) {
  const cleanId = themeId || 'soft';
  document.body.setAttribute('data-theme', cleanId);
  localStorage.setItem('projetous_theme', cleanId);

  // Update active state in modal cards
  const cards = document.querySelectorAll('.theme-card');
  cards.forEach(card => {
    const cardVal = card.getAttribute('data-theme-value');
    card.classList.toggle('active', cardVal === cleanId);
  });

  if (notify) {
    const names = {
      'soft': 'Suave (Novo Padrão)',
      'classic': 'Grafite Sóbrio',
      'midnight': 'Meia-Noite AMOLED',
      'mint': 'Floresta Suave'
    };
    showToast('Tema alterado para ' + (names[cleanId] || cleanId) + '!', 'success');
  }
}

function switchSettingsTab(tab) {
  if (tab === 'profile') {
    if (dom.tabBtnSettingsProfile) dom.tabBtnSettingsProfile.classList.add('active');
    if (dom.tabBtnSettingsTheme) dom.tabBtnSettingsTheme.classList.remove('active');
    if (dom.viewSettingsProfile) dom.viewSettingsProfile.classList.remove('hidden');
    if (dom.viewSettingsTheme) dom.viewSettingsTheme.classList.add('hidden');
  } else if (tab === 'theme') {
    if (dom.tabBtnSettingsTheme) dom.tabBtnSettingsTheme.classList.add('active');
    if (dom.tabBtnSettingsProfile) dom.tabBtnSettingsProfile.classList.remove('active');
    if (dom.viewSettingsTheme) dom.viewSettingsTheme.classList.remove('hidden');
    if (dom.viewSettingsProfile) dom.viewSettingsProfile.classList.add('hidden');

    // Ensure active card is highlighted
    const currentTheme = localStorage.getItem('projetous_theme') || 'soft';
    const cards = document.querySelectorAll('.theme-card');
    cards.forEach(card => {
      card.classList.toggle('active', card.getAttribute('data-theme-value') === currentTheme);
    });
  }
}

function loadStoredMessages() {
  try {
    const raw = localStorage.getItem('projetous_chat_history_v3');
    if (raw) {
      state.messages = JSON.parse(raw);
    }
  } catch (e) {
    console.warn('[ProjetoUS] Erro ao restaurar mensagens locais:', e);
  }

  if (!state.messages[DEFAULT_SERVER_ID]) {
    state.messages[DEFAULT_SERVER_ID] = {
      'c-geral': [
        {
          id: 'm-init',
          author: 'Sistema',
          authorAvatar: '',
          isSystem: true,
          text: 'Bem-vindo ao ProjetoUS! O sistema está conectado 24/7 na nuvem. Crie novos servidores no botão +, convide seus amigos pelo link próprio e converse por voz e texto sem perder mensagens!',
          timestamp: 'Hoje às 12:00'
        }
      ],
      'c-avisos': [],
      'c-memes': []
    };
  }

  // Seed seenMessageIds from all loaded messages to prevent network duplicates
  for (const srvId in state.messages) {
    for (const chanId in state.messages[srvId]) {
      const arr = state.messages[srvId][chanId];
      if (Array.isArray(arr)) {
        arr.forEach(m => { if (m.id) state.seenMessageIds.add(m.id); });
      }
    }
  }
}

function saveStoredMessages() {
  try {
    localStorage.setItem('projetous_chat_history_v3', JSON.stringify(state.messages));
  } catch (e) {
    console.warn('[ProjetoUS] Erro ao salvar mensagens:', e);
  }
}

function loadStoredKnownUsers() {
  try {
    const raw = localStorage.getItem('projetous_known_users_v1');
    if (raw) {
      state.knownUsers = JSON.parse(raw) || {};
    }
  } catch (e) {
    state.knownUsers = {};
  }
}

function saveStoredKnownUsers() {
  try {
    localStorage.setItem('projetous_known_users_v1', JSON.stringify(state.knownUsers));
  } catch (e) {}
}

function login(username) {
  state.currentUser.username = username.trim();
  localStorage.setItem('projetous_username', state.currentUser.username);

  state.knownUsers[state.currentUser.id] = {
    id: state.currentUser.id,
    username: state.currentUser.username,
    avatar: state.currentUser.avatar || '',
    updatedAt: Date.now()
  };
  saveStoredKnownUsers();

  dom.loginModal.classList.add('hidden');
  updateUserProfileUI();
  updateUserInStoredMessages(state.currentUser.id, state.currentUser.username, state.currentUser.avatar);

  // Connect to 24/7 Cloud Broker
  connectCloudNetwork();
}

function logout() {
  if (state.isSharingScreen) stopScreenShare();
  if (state.connectedVoiceChannel) disconnectVoice();

  if (state.mqtt) {
    publishPresence('leave');
    state.mqtt.end(true);
  }

  localStorage.removeItem('projetous_username');
  state.currentUser.username = '';
  dom.usernameInput.value = '';
  dom.loginModal.classList.remove('hidden');
  dom.usernameInput.focus();
  renderOnlineMembersList();
}

function getStatusLabel(status) {
  switch (status) {
    case 'idle': return 'Ausente';
    case 'dnd': return 'Não Perturbe';
    case 'online':
    default: return 'Online';
  }
}

function getStatusTitle(status) {
  switch (status) {
    case 'idle': return 'Ausente 🟡';
    case 'dnd': return 'Não Perturbe 🔴 (Silencia sons)';
    case 'online':
    default: return 'Online 🟢';
  }
}

function setUserStatus(status, isAuto = false) {
  const validStatuses = ['online', 'idle', 'dnd'];
  if (!validStatuses.includes(status)) status = 'online';

  state.currentUser.status = status;
  if (!isAuto) {
    state.userStatusPreference = status;
    try {
      localStorage.setItem('projetous_user_status', status);
    } catch (e) {}
  }

  updateLocalUserStatusUI();

  // Broadcast presence state to all servers and global peers
  publishPresence('state');

  // Re-render online members list to update current user's dot immediately
  renderOnlineMembersList();

  if (!isAuto) {
    showToast('Status alterado para ' + getStatusLabel(status), 'info');
  }
}

function updateLocalUserStatusUI() {
  const status = state.currentUser.status || 'online';
  const label = getStatusLabel(status);

  // 1. Bottom Bar Status Indicator & Text
  if (dom.myStatusIndicator) {
    dom.myStatusIndicator.className = 'status-indicator ' + status;
  }
  if (dom.myStatusText) {
    dom.myStatusText.textContent = status === 'online' ? 'Online (Nuvem 24/7)' : (label + (status === 'idle' ? ' 🟡' : ' 🔴'));
  }

  // 2. Popover items active class & header
  if (dom.popoverStatusIndicator) {
    dom.popoverStatusIndicator.className = 'status-indicator ' + status;
  }
  document.querySelectorAll('.status-popover-item').forEach(item => {
    const s = item.getAttribute('data-status');
    item.classList.toggle('active', s === status);
  });

  // 3. Settings Modal Preview & Cards
  if (dom.settingsPreviewStatusIndicator) {
    dom.settingsPreviewStatusIndicator.className = 'status-indicator ' + status;
  }
  if (dom.settingsPreviewStatus) {
    dom.settingsPreviewStatus.textContent = status === 'online' ? 'Online (Nuvem 24/7)' : label;
  }
  document.querySelectorAll('.settings-status-card').forEach(card => {
    const s = card.getAttribute('data-status');
    card.classList.toggle('active', s === status);
  });
}

function toggleUserStatusPopover(e) {
  if (e) e.stopPropagation();
  if (!dom.userStatusPopover) return;
  const isHidden = dom.userStatusPopover.classList.contains('hidden');
  if (isHidden) {
    openUserStatusPopover();
  } else {
    closeUserStatusPopover();
  }
}

function openUserStatusPopover() {
  if (!dom.userStatusPopover) return;
  if (dom.popoverUsername) dom.popoverUsername.textContent = state.currentUser.username || 'Usuário';
  if (dom.popoverAvatar) {
    if (state.currentUser.avatar) {
      dom.popoverAvatar.innerHTML = '<img src="' + escapeHtml(state.currentUser.avatar) + '" alt="Avatar">';
    } else {
      dom.popoverAvatar.textContent = (state.currentUser.username || 'U').substring(0, 2).toUpperCase();
    }
  }
  updateLocalUserStatusUI();
  dom.userStatusPopover.classList.remove('hidden');
}

function closeUserStatusPopover() {
  if (dom.userStatusPopover) {
    dom.userStatusPopover.classList.add('hidden');
  }
}

function updateUserProfileUI() {
  const name = state.currentUser.username || 'Usuário';
  dom.myUsername.textContent = name;

  if (state.currentUser.avatar) {
    dom.myAvatar.innerHTML = '<img src="' + state.currentUser.avatar + '" alt="Avatar">';
  } else {
    dom.myAvatar.textContent = name.substring(0, 2).toUpperCase();
  }
  updateLocalUserStatusUI();
  renderOnlineMembersList();
}

// --- 24/7 Cloud MQTT Pub-Sub Network ---
const TOPICS = {
  globalPresence: 'projetous/v3/global/presence',
  presence: (srvId) => 'projetous/v3/srv/' + srvId + '/presence',
  chat: (srvId) => 'projetous/v3/srv/' + srvId + '/chat',
  voice: (srvId) => 'projetous/v3/srv/' + srvId + '/voice',
  channels: (srvId) => 'projetous/v3/srv/' + srvId + '/channels',
  signal: (userId) => 'projetous/v3/signal/' + userId,
  discovery: 'projetous/v3/discovery'
};

function connectCloudNetwork() {
  if (dom.sidebarServerStatus) {
    dom.sidebarServerStatus.innerHTML = '<span class="server-status-dot connecting"></span>';
    dom.sidebarServerStatus.title = 'Conectando à nuvem 24/7...';
  }

  // Terminate any previous instance
  if (state.mqtt) {
    try { state.mqtt.end(true); } catch (e) {}
    state.mqtt = null;
  }

  const brokerUrl = 'wss://broker.emqx.io:8084/mqtt';
  const willPayload = JSON.stringify({
    action: 'leave',
    user: {
      id: state.currentUser.id,
      username: state.currentUser.username
    }
  });

  state.mqtt = mqtt.connect(brokerUrl, {
    clientId: 'pus_' + state.currentUser.id,
    clean: true,
    keepalive: 15,
    will: {
      topic: TOPICS.globalPresence,
      payload: willPayload,
      qos: 1,
      retain: false
    }
  });

  state.mqtt.on('connect', () => {
    console.log('[ProjetoUS] Conectado à rede em nuvem 24/7!');
    if (dom.sidebarServerStatus) {
      dom.sidebarServerStatus.innerHTML = '<span class="server-status-dot online"></span>';
      dom.sidebarServerStatus.title = 'Conectado à nuvem 24/7 (Online)';
    }

    subscribeToServerTopics(state.activeServerId);
    startHeartbeatWatchdog();
  });

  state.mqtt.on('message', async (topic, payload) => {
    try {
      const data = JSON.parse(payload.toString());

      if (topic === TOPICS.globalPresence) {
        handleGlobalPresenceMessage(data);
      } else if (topic === TOPICS.signal(state.currentUser.id)) {
        await handleSignalMessage(data);
      } else if (topic === TOPICS.discovery) {
        handleDiscoveryMessage(data);
      } else {
        // Dynamic routing for server topics: projetous/v3/srv/:srvId/:category
        const match = topic.match(/^projetous\/v3\/srv\/([^/]+)\/([^/]+)$/);
        if (match) {
          const srvId = match[1];
          const category = match[2];

          // Only process for servers the user participates in
          if (state.servers.some(s => s.id === srvId)) {
            if (category === 'chat') {
              handleChatMessage(data, srvId);
            } else if (category === 'presence') {
              handlePresenceMessage(data, srvId);
            } else if (category === 'voice') {
              handleVoiceMessage(data, srvId);
            } else if (category === 'channels') {
              handleChannelsMessage(data, srvId);
            }
          }
        }
      }
    } catch (e) {
      console.error('[ProjetoUS] Erro ao ler pacote da nuvem:', e);
    }
  });

  state.mqtt.on('close', () => {
    if (dom.sidebarServerStatus) {
      dom.sidebarServerStatus.innerHTML = '<span class="server-status-dot offline"></span>';
      dom.sidebarServerStatus.title = 'Reconectando à nuvem...';
    }
  });
}

function subscribeToServerTopics(srvId) {
  if (!state.mqtt) return;

  state.mqtt.subscribe([
    TOPICS.globalPresence,
    'projetous/v3/srv/+/chat',
    'projetous/v3/srv/+/presence',
    'projetous/v3/srv/+/voice',
    'projetous/v3/srv/+/channels',
    TOPICS.signal(state.currentUser.id),
    TOPICS.discovery
  ], { qos: 1 }, (err) => {
    if (!err) {
      publishPresence('join');
      publishPresence('whois');
      broadcastServerChannelsSync();
      requestAllChannelsHistory(state.activeServerId);
    }
  });
}

function requestChannelHistory(channelId, srvId) {
  if (!state.mqtt || !channelId || !srvId) return;
  state.mqtt.publish(TOPICS.chat(srvId), JSON.stringify({
    action: 'request_history',
    channelId: channelId,
    requesterId: state.currentUser.id
  }));
}

function requestAllChannelsHistory(srvId) {
  const srv = state.servers.find(s => s.id === srvId) || getActiveServer();
  if (srv && Array.isArray(srv.channels)) {
    srv.channels.filter(c => c.type === 'text').forEach(c => {
      requestChannelHistory(c.id, srvId);
    });
  }
}

function broadcastServerChannelsSync() {
  if (!state.mqtt) return;
  const srv = getActiveServer();
  if (srv && srv.channels) {
    state.mqtt.publish(TOPICS.channels(srv.id), JSON.stringify({
      action: 'sync',
      channels: srv.channels
    }));
  }
}

// --- Heartbeat Watchdog & Clean Disconnect ---
let heartbeatInterval = null;

function startHeartbeatWatchdog() {
  if (heartbeatInterval) clearInterval(heartbeatInterval);
  heartbeatInterval = setInterval(() => {
    if (state.mqtt && state.currentUser.username) {
      publishPresence('heartbeat');

      // If connected to a voice channel, send a lightweight voice ping to room
      if (state.connectedVoiceChannel) {
        state.mqtt.publish(TOPICS.voice(state.activeServerId), JSON.stringify({
          action: 'voice_ping',
          userId: state.currentUser.id,
          voiceChannelId: state.connectedVoiceChannel.id,
          voiceServerId: state.activeServerId
        }));
      }
    }

    const now = Date.now();
    let hasChanges = false;

    // Prune stale users in global presence (> 25s)
    for (const [uid, u] of state.globalUsers.entries()) {
      if (uid !== state.currentUser.id) {
        if (!u.lastSeen || (now - u.lastSeen > 25000)) {
          state.globalUsers.delete(uid);
          state.users = state.users.filter(x => x.id !== uid);
          closePeerConnection(uid);
          hasChanges = true;
        } else if (u.voiceChannelId && (now - u.lastSeen > 18000)) {
          // Voice presence stale (> 18s without voice ping or state update)
          u.voiceChannelId = null;
          u.voiceServerId = null;
          u.isSpeaking = false;
          u.isScreenSharing = false;
          closePeerConnection(uid);
          hasChanges = true;
        }
      }
    }

    // Prune stale users in local server list
    const staleUsers = state.users.filter(u => u.id !== state.currentUser.id && (!u.lastSeen || (now - u.lastSeen > 25000)));
    if (staleUsers.length > 0) {
      staleUsers.forEach(u => closePeerConnection(u.id));
      state.users = state.users.filter(u => !staleUsers.some(s => s.id === u.id));
      hasChanges = true;
    }

    // If local user is disconnected, ensure local user has no voiceChannelId in state.users
    if (!state.connectedVoiceChannel) {
      state.users.forEach(u => {
        if (u.id === state.currentUser.id && u.voiceChannelId) {
          u.voiceChannelId = null;
          u.voiceServerId = null;
          hasChanges = true;
        }
      });
    }

    if (hasChanges) {
      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();
    }
  }, 5000);
}

function handleAppExit() {
  if (state.mqtt && state.currentUser.id) {
    try {
      if (state.connectedVoiceChannel) {
        state.mqtt.publish(TOPICS.voice(state.activeServerId), JSON.stringify({
          action: 'leave',
          userId: state.currentUser.id,
          voiceChannelId: state.connectedVoiceChannel.id,
          voiceServerId: state.activeServerId
        }), { qos: 1 });
      }
      publishPresence('leave');
    } catch (e) {}
  }
}

window.addEventListener('beforeunload', handleAppExit);
window.addEventListener('pagehide', handleAppExit);

function publishPresence(action) {
  if (!state.mqtt || !state.currentUser.username) return;

  const userServers = state.servers.map(s => s.id);

  const payload = {
    action,
    user: {
      id: state.currentUser.id,
      username: state.currentUser.username,
      avatar: state.currentUser.avatar || '',
      status: state.currentUser.status || 'online',
      servers: userServers,
      activeServerId: state.activeServerId,
      voiceServerId: state.connectedVoiceChannel ? state.activeServerId : null,
      voiceChannelId: state.connectedVoiceChannel ? state.connectedVoiceChannel.id : null,
      isSpeaking: dom.myAvatar ? dom.myAvatar.classList.contains('speaking') : false,
      isMuted: state.isMuted,
      isDeafened: state.isDeafened,
      isScreenSharing: state.isSharingScreen
    }
  };

  const str = JSON.stringify(payload);
  state.mqtt.publish(TOPICS.globalPresence, str);
  state.mqtt.publish(TOPICS.presence(state.activeServerId), str);
}

function handleGlobalPresenceMessage(msg) {
  if (!msg) return;

  // Global user profile update broadcast
  if (msg.action === 'update_user_profile') {
    if (msg.userId && msg.username) {
      state.knownUsers[msg.userId] = {
        id: msg.userId,
        username: msg.username,
        avatar: msg.avatar || '',
        updatedAt: Date.now()
      };
      saveStoredKnownUsers();

      const existing = state.globalUsers.get(msg.userId) || {};
      state.globalUsers.set(msg.userId, {
        ...existing,
        id: msg.userId,
        username: msg.username,
        avatar: msg.avatar || ''
      });

      updateUserInStoredMessages(msg.userId, msg.username, msg.avatar);
      renderChatFeed();
      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();
    }
    return;
  }

  if (!msg.user || msg.user.id === state.currentUser.id) return;
  const u = msg.user;

  if (u.id && u.username) {
    state.knownUsers[u.id] = {
      id: u.id,
      username: u.username,
      avatar: u.avatar || '',
      updatedAt: Date.now()
    };
    saveStoredKnownUsers();
  }

  if (msg.action === 'leave') {
    state.globalUsers.delete(u.id);
    state.users = state.users.filter(x => x.id !== u.id);
    closePeerConnection(u.id);
  } else if (msg.action === 'join' || msg.action === 'here' || msg.action === 'heartbeat' || msg.action === 'state') {
    const existing = state.globalUsers.get(u.id) || {};
    const updated = { ...existing, ...u, lastSeen: Date.now() };
    state.globalUsers.set(u.id, updated);

    // Keep active server's state.users strictly isolated
    const belongs = (Array.isArray(updated.servers) && updated.servers.includes(state.activeServerId)) ||
                    (updated.activeServerId === state.activeServerId);
    if (belongs) {
      const isVoiceInThisServer = (updated.voiceServerId === state.activeServerId || (!updated.voiceServerId && updated.activeServerId === state.activeServerId));
      const serverUser = {
        ...updated,
        voiceChannelId: isVoiceInThisServer ? updated.voiceChannelId : null,
        voiceServerId: isVoiceInThisServer ? updated.voiceServerId : null
      };
      const idx = state.users.findIndex(x => x.id === u.id);
      if (idx >= 0) state.users[idx] = serverUser;
      else state.users.push(serverUser);
    } else {
      state.users = state.users.filter(x => x.id !== u.id);
    }

    if (msg.action === 'whois' || msg.action === 'join') {
      publishPresence('here');
    }
  }

  renderChannelsList();
  renderVoiceLounge();
  renderOnlineMembersList();
}

function handlePresenceMessage(msg, srvId = state.activeServerId) {
  if (!msg || !msg.user || msg.user.id === state.currentUser.id) return;

  const u = msg.user;
  if (msg.action === 'join' || msg.action === 'here' || msg.action === 'heartbeat' || msg.action === 'state') {
    const existing = state.globalUsers.get(u.id) || {};
    const updated = { ...existing, ...u, lastSeen: Date.now() };
    state.globalUsers.set(u.id, updated);

    if (srvId === state.activeServerId) {
      const isVoiceInThisServer = (updated.voiceServerId === state.activeServerId || (!updated.voiceServerId && updated.activeServerId === state.activeServerId));
      const serverUser = {
        ...updated,
        voiceChannelId: isVoiceInThisServer ? updated.voiceChannelId : null,
        voiceServerId: isVoiceInThisServer ? updated.voiceServerId : null
      };
      const idx = state.users.findIndex(x => x.id === u.id);
      if (idx >= 0) state.users[idx] = serverUser;
      else state.users.push(serverUser);
    }

    if (msg.action === 'whois' || msg.action === 'join') {
      publishPresence('here');
      broadcastServerChannelsSync();
    }
  } else if (msg.action === 'whois') {
    publishPresence('here');
    broadcastServerChannelsSync();
  } else if (msg.action === 'leave') {
    state.globalUsers.delete(u.id);
    state.users = state.users.filter(x => x.id !== u.id);
    closePeerConnection(u.id);
  }

  renderChannelsList();
  renderVoiceLounge();
  renderOnlineMembersList();
}

function handleChatMessage(data, srvId = state.activeServerId) {
  if (!data) return;

  // 1. Another peer is requesting previous messages for a channel
  if (data.action === 'request_history') {
    if (data.requesterId && data.requesterId !== state.currentUser.id && data.channelId) {
      const msgs = (state.messages[srvId] && state.messages[srvId][data.channelId]) || [];
      if (msgs.length > 0) {
        state.mqtt.publish(TOPICS.chat(srvId), JSON.stringify({
          action: 'sync_history',
          channelId: data.channelId,
          targetRequesterId: data.requesterId,
          messages: msgs.slice(-100) // send up to last 100 messages
        }), { qos: 1 });
      }
    }
    return;
  }

  // 2. Incoming history synchronization from another peer
  if (data.action === 'sync_history') {
    if (data.targetRequesterId === state.currentUser.id && data.channelId && Array.isArray(data.messages)) {
      const chanId = data.channelId;
      if (!state.messages[srvId]) state.messages[srvId] = {};
      if (!state.messages[srvId][chanId]) state.messages[srvId][chanId] = [];

      let addedCount = 0;
      data.messages.forEach(m => {
        if (!m || !m.id) return;
        state.seenMessageIds.add(m.id);

        // Reconcile author if known
        if (m.authorId === state.currentUser.id || (m.author && m.author === state.currentUser.username)) {
          m.author = state.currentUser.username;
          m.authorId = state.currentUser.id;
          m.authorAvatar = state.currentUser.avatar || '';
        } else if (m.authorId && state.knownUsers && state.knownUsers[m.authorId]) {
          m.author = state.knownUsers[m.authorId].username;
          if (state.knownUsers[m.authorId].avatar) m.authorAvatar = state.knownUsers[m.authorId].avatar;
        }

        if (!state.messages[srvId][chanId].some(existing => existing.id === m.id)) {
          state.messages[srvId][chanId].push(m);
          addedCount++;
        }
      });

      if (addedCount > 0) {
        saveStoredMessages();
        if (state.activeServerId === srvId && state.activeChannel && state.activeChannel.id === chanId) {
          renderChatFeed();
        }
      }
    }
    return;
  }

  // 3. Delete message broadcast
  if (data.action === 'delete_message') {
    if (data.channelId && data.messageId) {
      if (state.messages[srvId] && state.messages[srvId][data.channelId]) {
        state.messages[srvId][data.channelId] = state.messages[srvId][data.channelId].filter(m => m.id !== data.messageId);
        saveStoredMessages();
      }
      if (state.activeServerId === srvId && state.activeChannel && state.activeChannel.id === data.channelId) {
        const el = dom.messagesFeed.querySelector('.message-item[data-message-id="' + data.messageId + '"]');
        if (el) {
          el.style.transition = 'opacity 0.2s ease, transform 0.2s ease';
          el.style.opacity = '0';
          el.style.transform = 'translateX(20px)';
          setTimeout(() => el.remove(), 200);
        }
      }
    }
    return;
  }

  // 4. User profile updated broadcast (name/avatar changed)
  if (data.action === 'update_user_profile') {
    if (data.userId && data.username) {
      state.knownUsers[data.userId] = {
        id: data.userId,
        username: data.username,
        avatar: data.avatar || '',
        updatedAt: Date.now()
      };
      saveStoredKnownUsers();

      const existing = state.globalUsers.get(data.userId) || {};
      state.globalUsers.set(data.userId, {
        ...existing,
        id: data.userId,
        username: data.username,
        avatar: data.avatar || ''
      });

      updateUserInStoredMessages(data.userId, data.username, data.avatar);
      renderChatFeed();
      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();
    }
    return;
  }

  // 5. Normal real-time message
  const { channelId, message } = data;
  if (!channelId || !message || !message.id) return;

  // Deduplication: ignore network echo or already processed messages
  if (state.seenMessageIds.has(message.id)) {
    return;
  }
  state.seenMessageIds.add(message.id);
  if (state.seenMessageIds.size > 2000) {
    const firstKey = state.seenMessageIds.values().next().value;
    state.seenMessageIds.delete(firstKey);
  }

  // Record into knownUsers
  if (message.authorId && message.author) {
    state.knownUsers[message.authorId] = {
      id: message.authorId,
      username: message.author,
      avatar: message.authorAvatar || '',
      updatedAt: Date.now()
    };
    saveStoredKnownUsers();
  }

  if (!state.messages[srvId]) state.messages[srvId] = {};
  if (!state.messages[srvId][channelId]) state.messages[srvId][channelId] = [];

  if (state.messages[srvId][channelId].some(m => m.id === message.id)) {
    return;
  }

  state.messages[srvId][channelId].push(message);
  saveStoredMessages();

  const isViewingThisChannel = (state.activeServerId === srvId) && state.activeChannel && state.activeChannel.id === channelId && state.activeChannel.type === 'text';

  if (isViewingThisChannel) {
    appendChatMessage(message);
    scrollToBottom();
  } else {
    // Increment unread count for the channel
    state.unreadCounts[channelId] = (state.unreadCounts[channelId] || 0) + 1;
    renderChannelsList();
    updateUnreadTitle();
  }

  if (message.authorId !== state.currentUser.id) {
    if (state.currentUser.status !== 'dnd') {
      window.audioEngine.playMessageSound();
    }
  }
}

function handleChannelsMessage(data, srvId = state.activeServerId) {
  if (!data || !data.action) return;

  const srv = state.servers.find(s => s.id === srvId) || getActiveServer();
  if (!srv) return;

  if (data.action === 'create' && data.channel) {
    const chan = data.channel;
    if (!srv.channels.some(c => c.id === chan.id)) {
      srv.channels.push(chan);
      saveStoredServers();
      if (srv.id === state.activeServerId) {
        renderChannelsList();
      }
      showToast((chan.type === 'voice' ? '🔊' : '#') + chan.name + ' foi criado por ' + (data.creator || 'um usuário'), 'info');
    }
  } else if (data.action === 'sync' && Array.isArray(data.channels)) {
    let hasNew = false;
    data.channels.forEach(chan => {
      if (!srv.channels.some(c => c.id === chan.id)) {
        srv.channels.push(chan);
        hasNew = true;
      }
    });
    if (hasNew) {
      saveStoredServers();
      if (srv.id === state.activeServerId) {
        renderChannelsList();
      }
    }
  }
}

function handleDiscoveryMessage(data) {
  if (!data || !data.action) return;

  // Someone is requesting info about an inviteCode
  if (data.action === 'request_server' && data.inviteCode) {
    const found = state.servers.find(s => s.inviteCode === data.inviteCode || s.id === data.inviteCode);
    if (found && state.mqtt) {
      state.mqtt.publish(TOPICS.discovery, JSON.stringify({
        action: 'provide_server',
        server: found,
        targetRequesterId: data.requesterId
      }));
    }
  } else if (data.action === 'provide_server' && data.server) {
    const incoming = data.server;
    if (data.targetRequesterId === state.currentUser.id || !state.servers.some(s => s.id === incoming.id)) {
      if (!state.servers.some(s => s.id === incoming.id)) {
        state.servers.push(incoming);
        saveStoredServers();
        renderServerRail();
        selectServer(incoming.id);
        showToast('Você entrou no servidor "' + incoming.name + '" via link de convite!', 'success');
      }
    }
  } else if (data.action === 'announce_server' && data.server) {
    // Discovery feed announce
  }
}

async function handleVoiceMessage(msg, srvId = state.activeServerId) {
  if (!msg || !msg.action) return;
  const { action, userId, voiceChannelId, isSpeaking, isMuted, isDeafened, isScreenSharing, targetUserId, targetUserName, toChannelId, toChannelName, movedBy } = msg;

  const effectiveUserId = userId || targetUserId;
  if (!effectiveUserId) return;

  switch (action) {
    case 'join': {
      if (effectiveUserId === state.currentUser.id) break;

      const existing = state.globalUsers.get(effectiveUserId) || { id: effectiveUserId, username: msg.username || 'Usuário' };
      const updated = {
        ...existing,
        id: effectiveUserId,
        username: msg.username || existing.username || 'Usuário',
        avatar: msg.avatar !== undefined ? msg.avatar : (existing.avatar || ''),
        voiceChannelId: voiceChannelId,
        voiceServerId: srvId,
        isSpeaking: false,
        lastSeen: Date.now()
      };
      state.globalUsers.set(effectiveUserId, updated);

      const idx = state.users.findIndex(u => u.id === effectiveUserId);
      if (idx >= 0) state.users[idx] = updated;
      else state.users.push(updated);

      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();

      // If local user is in the SAME voice channel on this server
      if (state.connectedVoiceChannel && state.connectedVoiceChannel.id === voiceChannelId && srvId === state.activeServerId) {
        console.log('[WebRTC] Novo par no mesmo canal de voz:', effectiveUserId);
        // Reply with voice_sync so the newcomer immediately learns about our presence in the room!
        if (state.mqtt) {
          state.mqtt.publish(TOPICS.voice(srvId), JSON.stringify({
            action: 'voice_sync',
            userId: state.currentUser.id,
            username: state.currentUser.username,
            avatar: state.currentUser.avatar || '',
            voiceChannelId: voiceChannelId,
            voiceServerId: srvId,
            isSpeaking: dom.myAvatar ? dom.myAvatar.classList.contains('speaking') : false,
            isMuted: state.isMuted,
            isDeafened: state.isDeafened,
            isScreenSharing: state.isSharingScreen
          }));
        }
        await createPeerConnection(effectiveUserId, updated.username, true);
      }
      break;
    }

    case 'voice_sync': {
      if (effectiveUserId === state.currentUser.id) break;

      const existing = state.globalUsers.get(effectiveUserId) || { id: effectiveUserId, username: msg.username || 'Usuário' };
      const updated = {
        ...existing,
        id: effectiveUserId,
        username: msg.username || existing.username || 'Usuário',
        avatar: msg.avatar !== undefined ? msg.avatar : (existing.avatar || ''),
        voiceChannelId: voiceChannelId,
        voiceServerId: srvId,
        isSpeaking: !!isSpeaking,
        isMuted: !!isMuted,
        isDeafened: !!isDeafened,
        isScreenSharing: !!isScreenSharing,
        lastSeen: Date.now()
      };
      state.globalUsers.set(effectiveUserId, updated);

      const idx = state.users.findIndex(u => u.id === effectiveUserId);
      if (idx >= 0) state.users[idx] = updated;
      else state.users.push(updated);

      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();

      if (state.connectedVoiceChannel && state.connectedVoiceChannel.id === voiceChannelId && srvId === state.activeServerId) {
        if (!rtc.peers.has(effectiveUserId)) {
          setTimeout(() => {
            if (state.connectedVoiceChannel && state.connectedVoiceChannel.id === voiceChannelId && !rtc.peers.has(effectiveUserId)) {
              console.log('[WebRTC] Fallback P2P handshake com:', effectiveUserId);
              createPeerConnection(effectiveUserId, updated.username, true);
            }
          }, 600);
        }
      }
      break;
    }

    case 'leave': {
      // Clear from globalUsers and state.users immediately
      const gu = state.globalUsers.get(effectiveUserId);
      if (gu) {
        gu.voiceChannelId = null;
        gu.voiceServerId = null;
        gu.isSpeaking = false;
        gu.isScreenSharing = false;
        gu.lastSeen = Date.now();
      }
      const su = state.users.find(u => u.id === effectiveUserId);
      if (su) {
        su.voiceChannelId = null;
        su.voiceServerId = null;
        su.isSpeaking = false;
        su.isScreenSharing = false;
        su.lastSeen = Date.now();
      }
      closePeerConnection(effectiveUserId);
      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();
      break;
    }

    case 'voice_ping': {
      if (effectiveUserId === state.currentUser.id) break;
      const gu = state.globalUsers.get(effectiveUserId);
      if (gu) {
        gu.voiceChannelId = voiceChannelId;
        gu.voiceServerId = srvId;
        gu.lastSeen = Date.now();
      }
      const su = state.users.find(u => u.id === effectiveUserId);
      if (su) {
        su.voiceChannelId = voiceChannelId;
        su.voiceServerId = srvId;
        su.lastSeen = Date.now();
      }
      break;
    }

    case 'speaking': {
      const gu = state.globalUsers.get(effectiveUserId);
      if (gu) {
        gu.isSpeaking = isSpeaking;
        gu.lastSeen = Date.now();
      }
      const su = state.users.find(u => u.id === effectiveUserId);
      if (su) {
        su.isSpeaking = isSpeaking;
        su.lastSeen = Date.now();
      }
      updateUserSpeakingIndicator(effectiveUserId, isSpeaking);
      break;
    }

    case 'state': {
      const gu = state.globalUsers.get(effectiveUserId);
      if (gu) {
        gu.isMuted = isMuted;
        gu.isDeafened = isDeafened;
        gu.isSpeaking = isSpeaking;
        gu.lastSeen = Date.now();
      }
      const su = state.users.find(u => u.id === effectiveUserId);
      if (su) {
        su.isMuted = isMuted;
        su.isDeafened = isDeafened;
        su.isSpeaking = isSpeaking;
        su.lastSeen = Date.now();
      }
      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();
      break;
    }

    case 'screenshare': {
      const gu = state.globalUsers.get(effectiveUserId);
      if (gu) gu.isScreenSharing = isScreenSharing;
      const su = state.users.find(u => u.id === effectiveUserId);
      if (su) su.isScreenSharing = isScreenSharing;

      if (!isScreenSharing && !state.isSharingScreen) {
        dom.screenshareDisplayContainer.classList.add('hidden');
        dom.screenshareVideo.srcObject = null;
      }
      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();
      break;
    }

    case 'move': {
      const gu = state.globalUsers.get(effectiveUserId);
      if (gu) {
        gu.voiceChannelId = toChannelId;
        gu.voiceServerId = srvId;
        gu.lastSeen = Date.now();
      }
      const su = state.users.find(u => u.id === effectiveUserId);
      if (su) {
        su.voiceChannelId = toChannelId;
        su.voiceServerId = srvId;
        su.lastSeen = Date.now();
      }
      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();

      if (effectiveUserId === state.currentUser.id) {
        const destChan = getActiveServerChannels().find(c => c.id === toChannelId);
        if (destChan) {
          showToast('Você foi transferido para a sala "' + destChan.name + '" por ' + (movedBy || 'um moderador') + '!', 'warning', 5000);
          await joinVoiceChannel(destChan);
        }
      } else {
        showToast((targetUserName || 'Usuário') + ' foi movido para "' + (toChannelName || 'outra sala') + '" por ' + (movedBy || 'um moderador'), 'info');
      }
      break;
    }
  }
}

// --- WebRTC Peer-to-Peer Implementation ---
async function createPeerConnection(peerId, username, isInitiator) {
  if (rtc.peers.has(peerId)) {
    closePeerConnection(peerId);
  }

  const pc = new RTCPeerConnection(rtc.config);
  rtc.peers.set(peerId, pc);

  pc.onconnectionstatechange = () => {
    console.log('[WebRTC] Connection state with ' + peerId + ':', pc.connectionState);
    if (pc.connectionState === 'closed') {
      closePeerConnection(peerId);
      const gu = state.globalUsers.get(peerId);
      if (gu) gu.voiceChannelId = null;
      const su = state.users.find(u => u.id === peerId);
      if (su) su.voiceChannelId = null;
      renderChannelsList();
      renderVoiceLounge();
      renderOnlineMembersList();
    } else if (pc.connectionState === 'failed') {
      setTimeout(() => {
        if (pc.connectionState === 'failed') {
          closePeerConnection(peerId);
        }
      }, 4000);
    }
  };

  pc.oniceconnectionstatechange = () => {
    console.log('[WebRTC] ICE state with ' + peerId + ':', pc.iceConnectionState);
    if (pc.iceConnectionState === 'failed') {
      setTimeout(() => {
        if (pc.iceConnectionState === 'failed') {
          closePeerConnection(peerId);
        }
      }, 4000);
    }
  };

  // Add local microphone audio track to peer connection
  if (state.localAudioStream) {
    state.localAudioStream.getAudioTracks().forEach(track => {
      const senders = pc.getSenders();
      if (!senders.some(s => s.track === track)) {
        pc.addTrack(track, state.localAudioStream);
      }
    });
  }

  if (state.isSharingScreen && state.screenStream) {
    const videoTrack = state.screenStream.getVideoTracks()[0];
    if (videoTrack) {
      const sender = pc.addTrack(videoTrack, state.screenStream);
      rtc.screenSenders.set(peerId, sender);
    }
  }

  pc.onicecandidate = (event) => {
    if (event.candidate && state.mqtt) {
      state.mqtt.publish(TOPICS.signal(peerId), JSON.stringify({
        from: state.currentUser.id,
        candidate: event.candidate
      }));
    }
  };

  pc.ontrack = (event) => {
    console.log('[WebRTC] Faixa de áudio/vídeo recebida de:', peerId, event.track.kind);

    if (event.track.kind === 'audio') {
      let audioEl = rtc.remoteAudios.get(peerId);
      if (!audioEl) {
        audioEl = document.createElement('audio');
        audioEl.autoplay = true;
        audioEl.id = 'remote-audio-' + peerId;
        audioContainer.appendChild(audioEl);
        rtc.remoteAudios.set(peerId, audioEl);
      }
      const stream = event.streams[0] || new MediaStream([event.track]);
      audioEl.srcObject = stream;
      const userVol = state.userVolumes[peerId] !== undefined ? state.userVolumes[peerId] : 100;
      audioEl.volume = Math.max(0, Math.min(1, userVol / 100));
      audioEl.muted = state.isDeafened || (userVol === 0);

      const tryPlay = () => {
        audioEl.play().catch(e => {
          console.warn('[WebRTC] Autoplay prevented, waiting for user gesture:', e);
          const resumeAudio = () => {
            audioEl.play().catch(() => {});
            if (window.audioEngine && window.audioEngine.audioCtx && window.audioEngine.audioCtx.state === 'suspended') {
              window.audioEngine.audioCtx.resume().catch(() => {});
            }
            window.removeEventListener('click', resumeAudio);
            window.removeEventListener('keydown', resumeAudio);
          };
          window.addEventListener('click', resumeAudio, { once: true });
          window.addEventListener('keydown', resumeAudio, { once: true });
        });
      };
      tryPlay();

      // Routing through Web Audio API GainNode for true 0% - 200% volume control
      try {
        if (!window.audioEngine.audioCtx) {
          const AudioContextClass = window.AudioContext || window.webkitAudioContext;
          window.audioEngine.audioCtx = new AudioContextClass();
        }
        const ctx = window.audioEngine.audioCtx;
        if (ctx.state === 'suspended') ctx.resume();

        // Disconnect previous gain node if exists
        const prevGain = rtc.remoteGains.get(peerId);
        if (prevGain) {
          try { prevGain.disconnect(); } catch (e) {}
        }

        const source = ctx.createMediaStreamSource(stream);
        const gainNode = ctx.createGain();
        gainNode.gain.value = state.isDeafened ? 0 : (userVol / 100);
        source.connect(gainNode);
        gainNode.connect(ctx.destination);
        rtc.remoteGains.set(peerId, gainNode);
        // CRUCIAL: Keep audioEl muted so sound is output via Web Audio API GainNode only.
        // This stops Chrome from bypassing volume slider and playing unattenuated 100% audio directly.
        audioEl.muted = true;
      } catch (err) {
        console.warn('[WebAudio] Gain routing warning:', err);
        audioEl.muted = state.isDeafened || (userVol === 0);
      }
    } else if (event.track.kind === 'video') {
      dom.screenshareVideo.srcObject = event.streams[0] || new MediaStream([event.track]);
      dom.screenshareDisplayContainer.classList.remove('hidden');
      dom.screenshareStreamerName.textContent = '🔴 AO VIVO: Tela de ' + (username || 'Membro');

      if (state.connectedVoiceChannel) {
        selectChannel(state.connectedVoiceChannel.id);
      }

      event.track.onended = () => {
        dom.screenshareDisplayContainer.classList.add('hidden');
        dom.screenshareVideo.srcObject = null;
      };
    }
  };

  if (isInitiator) {
    try {
      const offer = await pc.createOffer({
        offerToReceiveAudio: true,
        offerToReceiveVideo: true
      });
      await pc.setLocalDescription(offer);
      state.mqtt.publish(TOPICS.signal(peerId), JSON.stringify({
        from: state.currentUser.id,
        sdp: pc.localDescription
      }));
    } catch (err) {
      console.error('[WebRTC] Erro oferta:', err);
    }
  }

  return pc;
}

async function handleSignalMessage(data) {
  const fromPeerId = data.from;
  if (!fromPeerId || fromPeerId === state.currentUser.id) return;

  let pc = rtc.peers.get(fromPeerId);
  if (!pc) {
    const fromUser = state.users.find(u => u.id === fromPeerId);
    pc = await createPeerConnection(fromPeerId, fromUser ? fromUser.username : 'Membro', false);
  }

  if (data.sdp) {
    await pc.setRemoteDescription(new RTCSessionDescription(data.sdp));

    // Flush any queued ICE candidates for this peer
    const queue = rtc.iceCandidateQueues.get(fromPeerId) || [];
    for (const cand of queue) {
      try {
        await pc.addIceCandidate(new RTCIceCandidate(cand));
      } catch (e) {
        console.warn('[WebRTC] Erro ao adicionar ICE da fila:', e);
      }
    }
    rtc.iceCandidateQueues.delete(fromPeerId);

    if (data.sdp.type === 'offer') {
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      state.mqtt.publish(TOPICS.signal(fromPeerId), JSON.stringify({
        from: state.currentUser.id,
        sdp: pc.localDescription
      }));
    }
  } else if (data.candidate) {
    if (!pc.remoteDescription || !pc.remoteDescription.type) {
      // Remote description not set yet -> buffer candidate to prevent dropping!
      if (!rtc.iceCandidateQueues.has(fromPeerId)) {
        rtc.iceCandidateQueues.set(fromPeerId, []);
      }
      rtc.iceCandidateQueues.get(fromPeerId).push(data.candidate);
    } else {
      try {
        await pc.addIceCandidate(new RTCIceCandidate(data.candidate));
      } catch (e) {
        console.warn('[WebRTC] Candidate error:', e);
      }
    }
  }
}

function closePeerConnection(peerId) {
  const pc = rtc.peers.get(peerId);
  if (pc) {
    try { pc.close(); } catch (e) {}
    rtc.peers.delete(peerId);
  }

  const audioEl = rtc.remoteAudios.get(peerId);
  if (audioEl) {
    audioEl.pause();
    audioEl.srcObject = null;
    audioEl.remove();
    rtc.remoteAudios.delete(peerId);
  }

  const gainNode = rtc.remoteGains.get(peerId);
  if (gainNode) {
    try { gainNode.disconnect(); } catch (e) {}
    rtc.remoteGains.delete(peerId);
  }

  rtc.iceCandidateQueues.delete(peerId);
  rtc.screenSenders.delete(peerId);
}

function closeAllPeerConnections() {
  for (const peerId of Array.from(rtc.peers.keys())) {
    closePeerConnection(peerId);
  }
  rtc.peers.clear();
  rtc.remoteAudios.clear();
  rtc.remoteGains.clear();
  rtc.iceCandidateQueues.clear();
  rtc.screenSenders.clear();
}

function setUserVolume(userId, volumePercent) {
  const vol = Math.max(0, Math.min(200, volumePercent));
  state.userVolumes[userId] = vol;

  // 1. Web Audio API Gain Node (0% - 200% true volume amplification)
  let gainNode = rtc.remoteGains.get(userId);
  const audioEl = rtc.remoteAudios.get(userId);

  // Lazy GainNode initialization if remote audio stream exists but GainNode wasn't connected yet
  if (!gainNode && audioEl && audioEl.srcObject) {
    try {
      if (!window.audioEngine.audioCtx) {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        window.audioEngine.audioCtx = new AudioContextClass();
      }
      const ctx = window.audioEngine.audioCtx;
      if (ctx.state === 'suspended') ctx.resume();
      const source = ctx.createMediaStreamSource(audioEl.srcObject);
      gainNode = ctx.createGain();
      gainNode.gain.value = state.isDeafened ? 0 : (vol / 100);
      source.connect(gainNode);
      gainNode.connect(ctx.destination);
      rtc.remoteGains.set(userId, gainNode);
      audioEl.muted = true;
    } catch (err) {
      console.warn('[WebAudio] Lazy gain init warning:', err);
    }
  }

  if (gainNode) {
    if (window.audioEngine && window.audioEngine.audioCtx && window.audioEngine.audioCtx.state === 'suspended') {
      window.audioEngine.audioCtx.resume().catch(() => {});
    }
    gainNode.gain.value = state.isDeafened ? 0 : (vol / 100);
    if (audioEl) {
      // Keep audioEl muted so sound is output via GainNode exclusively
      audioEl.muted = true;
    }
  } else if (audioEl) {
    // Fallback if Web Audio GainNode is unavailable
    audioEl.volume = Math.max(0, Math.min(1, vol / 100));
    audioEl.muted = state.isDeafened || (vol === 0);
  }

  // 3. Synchronize all sliders and labels in DOM in real-time
  document.querySelectorAll(`.lounge-volume-slider[data-user-id="${userId}"]`).forEach(slider => {
    slider.value = vol;
    slider.title = 'Volume: ' + vol + '%';
  });
  document.querySelectorAll(`.context-menu-volume-slider[data-user-id="${userId}"]`).forEach(slider => {
    slider.value = vol;
  });
  document.querySelectorAll(`.context-menu-volume-val[data-user-id="${userId}"]`).forEach(span => {
    span.textContent = vol + '%';
  });
}

function updateRemoteAudiosMuteState() {
  for (const [peerId, gainNode] of rtc.remoteGains.entries()) {
    const userVol = state.userVolumes[peerId] !== undefined ? state.userVolumes[peerId] : 100;
    gainNode.gain.value = state.isDeafened ? 0 : (userVol / 100);
  }
  for (const [peerId, audioEl] of rtc.remoteAudios.entries()) {
    if (audioEl) {
      if (rtc.remoteGains.has(peerId)) {
        audioEl.muted = true;
      } else {
        audioEl.muted = state.isDeafened || (state.userVolumes[peerId] === 0);
      }
    }
  }
}

// --- Audio Callbacks & VAD ---
function setupAudioCallbacks() {
  window.audioEngine.onSpeakingChange = (isSpeaking) => {
    if (state.connectedVoiceChannel) {
      dom.myAvatar.classList.toggle('speaking', isSpeaking);
      updateUserSpeakingIndicator(state.currentUser.id, isSpeaking);

      if (state.mqtt) {
        state.mqtt.publish(TOPICS.voice(state.activeServerId), JSON.stringify({
          action: 'speaking',
          userId: state.currentUser.id,
          isSpeaking
        }));
      }
    }
  };

  window.audioEngine.onVolumeMeter = (percent) => {
    if (dom.meterBarFill) dom.meterBarFill.style.width = percent + '%';
    if (dom.meterLevelValue) dom.meterLevelValue.textContent = percent + '%';
  };
}

function updateUserSpeakingIndicator(userId, isSpeaking) {
  const rowAvatar = document.querySelector('.voice-user-avatar[data-user-id="' + userId + '"]');
  if (rowAvatar) {
    rowAvatar.classList.toggle('speaking', isSpeaking);
  }

  const loungeCard = document.querySelector('.lounge-member-card[data-user-id="' + userId + '"]');
  if (loungeCard) {
    loungeCard.classList.toggle('speaking', isSpeaking);
    const loungeAvatar = loungeCard.querySelector('.lounge-avatar-big');
    if (loungeAvatar) loungeAvatar.classList.toggle('speaking', isSpeaking);

    const statusBadge = loungeCard.querySelector('.lounge-member-status');
    if (statusBadge) {
      if (isSpeaking) {
        statusBadge.textContent = 'Falando...';
        statusBadge.classList.add('speaking-badge');
      } else {
        statusBadge.textContent = 'Ouvindo';
        statusBadge.classList.remove('speaking-badge');
      }
    }
  }

  // Right sidebar online member speaking indicator
  const memberAvatar = document.getElementById('member-avatar-' + userId);
  if (memberAvatar) {
    memberAvatar.classList.toggle('speaking', isSpeaking);
  }
}

// --- Advanced Screen Sharing System (Janelas, Monitores, Qualidade & FPS) ---
function getResolutionDimensions(res) {
  switch (res) {
    case '480p':
      return { width: 854, height: 480, label: '480p (Econômica)' };
    case '1080p':
      return { width: 1920, height: 1080, label: '1080p (Full HD)' };
    case '720p':
    default:
      return { width: 1280, height: 720, label: '720p (HD Padrão)' };
  }
}

function detectAvailableScreens() {
  const screens = [];
  const primaryWidth = (window.screen && window.screen.width) || 1920;
  const primaryHeight = (window.screen && window.screen.height) || 1080;

  screens.push({
    id: 'screen-primary',
    name: 'Monitor 1 (Principal)',
    resolution: `${primaryWidth} × ${primaryHeight}`,
    isPrimary: true
  });

  // Check if multiple monitors are connected (Window Screen Extended API)
  if (window.screen && window.screen.isExtended) {
    screens.push({
      id: 'screen-secondary',
      name: 'Monitor 2 (Secundário)',
      resolution: 'Estendido',
      isPrimary: false
    });
  }

  return screens;
}

function renderScreenShareSources() {
  if (!dom.screenshareWindowsGrid || !dom.screenshareScreensGrid) return;

  // 1. Render Window Cards (Aba Janelas)
  const windowSources = [
    {
      id: 'window-app',
      name: 'Janela do Aplicativo',
      badge: 'Software',
      type: 'app'
    },
    {
      id: 'window-browser',
      name: 'Navegador de Internet',
      badge: 'Navegador',
      type: 'browser'
    },
    {
      id: 'window-game',
      name: 'Jogo ou Vídeo',
      badge: 'Mídia / Jogo',
      type: 'game'
    },
    {
      id: 'window-other',
      name: 'Outro Programa Aberto',
      badge: 'Janela',
      type: 'window'
    }
  ];

  dom.screenshareWindowsGrid.innerHTML = '';
  windowSources.forEach(src => {
    const card = document.createElement('div');
    const isSelected = state.screenshareSettings.targetSurface === 'window' &&
                       state.screenshareSettings.selectedSourceId === src.id;
    card.className = `screenshare-source-card ${isSelected ? 'active' : ''}`;
    card.dataset.sourceId = src.id;
    card.dataset.surface = 'window';

    card.innerHTML = `
      <div class="source-preview-box">
        <div class="mockup-window">
          <div class="mockup-window-titlebar">
            <span class="mockup-dot"></span>
            <span class="mockup-dot"></span>
            <span class="mockup-dot"></span>
          </div>
          <div class="mockup-window-body">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
              <path d="M19 3H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm0 16H5V5h14v14zM7 10h2v7H7zm4-3h2v10h-2zm4 6h2v4h-2z"/>
            </svg>
          </div>
        </div>
        <span class="source-badge-tag">${src.badge}</span>
      </div>
      <div class="source-card-info">
        <span class="source-card-icon">🪟</span>
        <span class="source-card-name" title="${src.name}">${src.name}</span>
        <div class="source-card-check">✓</div>
      </div>
    `;

    card.addEventListener('click', () => {
      state.screenshareSettings.targetSurface = 'window';
      state.screenshareSettings.selectedSourceId = src.id;
      renderScreenShareSources();
    });
    card.addEventListener('dblclick', () => {
      state.screenshareSettings.targetSurface = 'window';
      state.screenshareSettings.selectedSourceId = src.id;
      startScreenShareWithSettings();
    });

    dom.screenshareWindowsGrid.appendChild(card);
  });

  // 2. Render Screen Cards (Aba Tela Inteira)
  const screens = detectAvailableScreens();
  dom.screenshareScreensGrid.innerHTML = '';
  screens.forEach(scr => {
    const card = document.createElement('div');
    const isSelected = state.screenshareSettings.targetSurface === 'monitor' &&
                       state.screenshareSettings.selectedSourceId === scr.id;
    card.className = `screenshare-source-card ${isSelected ? 'active' : ''}`;
    card.dataset.sourceId = scr.id;
    card.dataset.surface = 'monitor';

    card.innerHTML = `
      <div class="source-preview-box">
        <div class="mockup-monitor"></div>
        <div class="mockup-monitor-stand"></div>
        <div class="mockup-monitor-base"></div>
        <span class="source-badge-tag">${scr.resolution}</span>
      </div>
      <div class="source-card-info">
        <span class="source-card-icon">🖥️</span>
        <span class="source-card-name" title="${scr.name}">${scr.name}</span>
        <div class="source-card-check">✓</div>
      </div>
    `;

    card.addEventListener('click', () => {
      state.screenshareSettings.targetSurface = 'monitor';
      state.screenshareSettings.selectedSourceId = scr.id;
      renderScreenShareSources();
    });
    card.addEventListener('dblclick', () => {
      state.screenshareSettings.targetSurface = 'monitor';
      state.screenshareSettings.selectedSourceId = scr.id;
      startScreenShareWithSettings();
    });

    dom.screenshareScreensGrid.appendChild(card);
  });
}

function selectScreenShareTab(tabName) {
  if (tabName === 'windows') {
    state.screenshareSettings.targetSurface = 'window';
    if (!state.screenshareSettings.selectedSourceId || state.screenshareSettings.selectedSourceId.startsWith('screen-')) {
      state.screenshareSettings.selectedSourceId = 'window-app';
    }
    if (dom.tabBtnScreenshareWindows) dom.tabBtnScreenshareWindows.classList.add('active');
    if (dom.tabBtnScreenshareScreens) dom.tabBtnScreenshareScreens.classList.remove('active');
    if (dom.viewScreenshareWindows) dom.viewScreenshareWindows.classList.remove('hidden');
    if (dom.viewScreenshareScreens) dom.viewScreenshareScreens.classList.add('hidden');
  } else {
    state.screenshareSettings.targetSurface = 'monitor';
    if (!state.screenshareSettings.selectedSourceId || state.screenshareSettings.selectedSourceId.startsWith('window-')) {
      state.screenshareSettings.selectedSourceId = 'screen-primary';
    }
    if (dom.tabBtnScreenshareWindows) dom.tabBtnScreenshareWindows.classList.remove('active');
    if (dom.tabBtnScreenshareScreens) dom.tabBtnScreenshareScreens.classList.add('active');
    if (dom.viewScreenshareWindows) dom.viewScreenshareWindows.classList.add('hidden');
    if (dom.viewScreenshareScreens) dom.viewScreenshareScreens.classList.remove('hidden');
  }
  renderScreenShareSources();
}

function updateScreenShareQualityUI() {
  const res = state.screenshareSettings.resolution || '720p';
  const fps = state.screenshareSettings.fps || 30;

  // Update resolution pills
  if (dom.pillsResolution) {
    dom.pillsResolution.querySelectorAll('.quality-pill').forEach(pill => {
      pill.classList.toggle('active', pill.dataset.resolution === res);
    });
  }

  // Update FPS pills
  if (dom.pillsFps) {
    dom.pillsFps.querySelectorAll('.quality-pill').forEach(pill => {
      pill.classList.toggle('active', parseInt(pill.dataset.fps, 10) === fps);
    });
  }

  const dim = getResolutionDimensions(res);
  if (dom.valCurrentResolution) {
    dom.valCurrentResolution.textContent = dim.label;
  }
  if (dom.valCurrentFps) {
    dom.valCurrentFps.textContent = `${fps} FPS`;
  }
  if (dom.screenshareQualitySummary) {
    dom.screenshareQualitySummary.textContent = `${res} • ${fps} FPS`;
  }
}

function openScreenShareModal(options = {}) {
  // If not connected to voice, auto-join active or first voice channel
  if (!state.connectedVoiceChannel) {
    const channels = getActiveServerChannels();
    const voiceChan = (state.activeChannel && state.activeChannel.type === 'voice') 
      ? state.activeChannel 
      : channels.find(c => c.type === 'voice');

    if (voiceChan) {
      joinVoiceChannel(voiceChan);
    } else {
      showToast('Conecte-se a uma sala de voz primeiro para transmitir sua tela.', 'warning');
      return;
    }
  }

  const isLive = state.isSharingScreen;
  if (dom.screenshareModalTitle) {
    dom.screenshareModalTitle.textContent = isLive 
      ? 'Ajustar Qualidade da Transmissão' 
      : 'Configurações da Transmissão';
  }
  if (dom.screenshareModalSubtitle) {
    dom.screenshareModalSubtitle.textContent = isLive
      ? 'Ajuste a resolução e os quadros por segundo em tempo real'
      : 'Ajuste a resolução, taxa de quadros e áudio da sua transmissão';
  }
  if (dom.btnConfirmScreenshareText) {
    dom.btnConfirmScreenshareText.textContent = isLive
      ? 'Aplicar Alterações'
      : 'Iniciar Transmissão';
  }
  if (dom.btnStopFromModal) {
    dom.btnStopFromModal.classList.toggle('hidden', !isLive);
  }

  selectScreenShareTab(state.screenshareSettings.targetSurface || 'window');
  updateScreenShareQualityUI();

  if (dom.screenshareAudioCheckbox) {
    dom.screenshareAudioCheckbox.checked = !!state.screenshareSettings.shareAudio;
  }

  if (dom.screenshareModal) {
    dom.screenshareModal.classList.remove('hidden');
  }
}

function closeScreenShareModal() {
  if (dom.screenshareModal) {
    dom.screenshareModal.classList.add('hidden');
  }
}

async function applyScreenShareQuality(resolution, fps) {
  state.screenshareSettings.resolution = resolution;
  state.screenshareSettings.fps = fps;
  updateScreenShareQualityUI();

  const dim = getResolutionDimensions(resolution);

  // Update tag on video player
  if (dom.screenshareQualityTag) {
    dom.screenshareQualityTag.textContent = `${resolution.toUpperCase()} ${fps}FPS`;
  }

  if (state.isSharingScreen && state.screenStream) {
    try {
      const videoTrack = state.screenStream.getVideoTracks()[0];
      if (videoTrack && videoTrack.applyConstraints) {
        await videoTrack.applyConstraints({
          width: { ideal: dim.width, max: dim.width },
          height: { ideal: dim.height, max: dim.height },
          frameRate: { ideal: fps, max: fps }
        });
      }

      // Also try to update sender encoding parameters if available
      for (const [peerId, sender] of rtc.screenSenders.entries()) {
        try {
          const params = sender.getParameters();
          if (params && params.encodings && params.encodings.length > 0) {
            params.encodings[0].maxFramerate = fps;
            if (resolution === '480p') params.encodings[0].maxBitrate = 800000;
            else if (resolution === '720p') params.encodings[0].maxBitrate = 2000000;
            else if (resolution === '1080p') params.encodings[0].maxBitrate = 4500000;
            await sender.setParameters(params);
          }
        } catch (e) {
          // ignore minor sender param errors
        }
      }

      showToast(`Qualidade ajustada para ${resolution.toUpperCase()} • ${fps} FPS`, 'success');
    } catch (err) {
      console.warn('Erro ao aplicar qualidade em tempo real:', err);
      showToast(`Qualidade definida para ${resolution.toUpperCase()} • ${fps} FPS`, 'info');
    }
  }
}

async function startScreenShareWithSettings() {
  if (state.isSharingScreen) {
    // Already streaming -> apply the selected quality settings
    await applyScreenShareQuality(
      state.screenshareSettings.resolution,
      state.screenshareSettings.fps
    );
    closeScreenShareModal();
    return;
  }

  closeScreenShareModal();

  const surface = state.screenshareSettings.targetSurface || 'window';
  const resolution = state.screenshareSettings.resolution || '720p';
  const fps = state.screenshareSettings.fps || 30;
  const shareAudio = dom.screenshareAudioCheckbox ? dom.screenshareAudioCheckbox.checked : true;
  state.screenshareSettings.shareAudio = shareAudio;

  const dim = getResolutionDimensions(resolution);

  const constraints = {
    video: {
      cursor: 'always',
      displaySurface: surface,
      width: { ideal: dim.width, max: dim.width },
      height: { ideal: dim.height, max: dim.height },
      frameRate: { ideal: fps, max: fps }
    },
    audio: shareAudio,
    preferCurrentTab: false,
    selfBrowserSurface: 'exclude',
    systemAudio: shareAudio ? 'include' : 'exclude',
    surfaceSwitching: 'include'
  };

  try {
    const stream = await navigator.mediaDevices.getDisplayMedia(constraints);

    state.screenStream = stream;
    state.isSharingScreen = true;

    dom.screenshareVideo.srcObject = stream;
    dom.screenshareDisplayContainer.classList.remove('hidden');
    dom.screenshareStreamerName.textContent = state.currentUser.username + ' (Sua Transmissão)';

    if (dom.screenshareQualityTag) {
      dom.screenshareQualityTag.textContent = `${resolution.toUpperCase()} ${fps}FPS`;
    }

    updateScreenShareButtons(true);

    const videoTrack = stream.getVideoTracks()[0];

    for (const [peerId, pc] of rtc.peers.entries()) {
      try {
        const sender = pc.addTrack(videoTrack, stream);
        rtc.screenSenders.set(peerId, sender);

        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        state.mqtt.publish(TOPICS.signal(peerId), JSON.stringify({
          from: state.currentUser.id,
          sdp: pc.localDescription
        }));
      } catch (err) {
        console.warn('Vídeo track error:', err);
      }
    }

    videoTrack.onended = () => stopScreenShare();

    if (state.connectedVoiceChannel) {
      selectChannel(state.connectedVoiceChannel.id);
    }

    if (state.mqtt) {
      state.mqtt.publish(TOPICS.voice(state.activeServerId), JSON.stringify({
        action: 'screenshare',
        userId: state.currentUser.id,
        isScreenSharing: true
      }));
    }

    renderChannelsList();
    renderVoiceLounge();
    showToast(`Transmissão iniciada em ${resolution.toUpperCase()} • ${fps} FPS!`, 'success');
  } catch (err) {
    console.warn('Transmissão cancelada ou erro:', err);
  }
}

async function toggleScreenShare() {
  if (state.isSharingScreen) {
    stopScreenShare();
  } else {
    // Transmissão direta em 1 clique sem modal intermediário
    await startScreenShare();
  }
}

async function startScreenShare() {
  // If not connected to voice, auto-join active or first voice channel
  if (!state.connectedVoiceChannel) {
    const channels = getActiveServerChannels();
    const voiceChan = (state.activeChannel && state.activeChannel.type === 'voice') 
      ? state.activeChannel 
      : channels.find(c => c.type === 'voice');

    if (voiceChan) {
      await joinVoiceChannel(voiceChan);
    } else {
      showToast('Conecte-se a uma sala de voz primeiro para transmitir sua tela.', 'warning');
      return;
    }
  }

  await startScreenShareWithSettings();
}

async function stopScreenShare() {
  if (!state.isSharingScreen) return;
  state.isSharingScreen = false;

  for (const [peerId, pc] of rtc.peers.entries()) {
    const sender = rtc.screenSenders.get(peerId);
    if (sender) {
      try { pc.removeTrack(sender); } catch (e) {}
    }
    // Renegotiate track removal with remote peers
    try {
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      state.mqtt.publish(TOPICS.signal(peerId), JSON.stringify({
        from: state.currentUser.id,
        sdp: pc.localDescription
      }));
    } catch (e) {}
  }
  rtc.screenSenders.clear();

  if (state.screenStream) {
    state.screenStream.getTracks().forEach(t => t.stop());
    state.screenStream = null;
  }

  dom.screenshareVideo.srcObject = null;
  dom.screenshareDisplayContainer.classList.add('hidden');

  updateScreenShareButtons(false);
  closeScreenShareModal();

  if (state.mqtt) {
    state.mqtt.publish(TOPICS.voice(state.activeServerId), JSON.stringify({
      action: 'screenshare',
      userId: state.currentUser.id,
      isScreenSharing: false
    }));
  }

  renderChannelsList();
  renderVoiceLounge();
  showToast('Transmissão de tela encerrada.', 'info');
}

function updateScreenShareButtons(isSharing) {
  if (isSharing) {
    if (dom.btnScreenshareVoice) {
      dom.btnScreenshareVoice.classList.add('active-sharing');
      dom.btnScreenshareVoice.title = 'Parar Transmissão de Tela';
    }
    if (dom.loungeBtnScreenshare) {
      dom.loungeBtnScreenshare.classList.add('active-sharing');
      dom.loungeScreenshareText.textContent = 'Parar Transmissão';
    }
  } else {
    if (dom.btnScreenshareVoice) {
      dom.btnScreenshareVoice.classList.remove('active-sharing');
      dom.btnScreenshareVoice.title = 'Transmitir Tela / Janela';
    }
    if (dom.loungeBtnScreenshare) {
      dom.loungeBtnScreenshare.classList.remove('active-sharing');
      dom.loungeScreenshareText.textContent = 'Transmitir Tela';
    }
  }
  updateLoungeDockButtons();
}

// --- Server Rail Collapse & Server Hub Management ---
function collapseServerRail(collapsed) {
  if (!dom.appLeftPanel) dom.appLeftPanel = document.querySelector('.app-left-panel');
  if (!dom.appLeftPanel) return;

  if (collapsed) {
    dom.appLeftPanel.classList.add('rail-collapsed');
    if (dom.btnExpandServerRail) dom.btnExpandServerRail.classList.remove('hidden');
    localStorage.setItem('projetous_rail_collapsed', 'true');
    showToast('Baia de servidores recolhida. Use Alt+S para restaurar.', 'info', 2200);
  } else {
    dom.appLeftPanel.classList.remove('rail-collapsed');
    if (dom.btnExpandServerRail) dom.btnExpandServerRail.classList.add('hidden');
    localStorage.removeItem('projetous_rail_collapsed');
  }
}

function toggleServerRailCollapse() {
  if (!dom.appLeftPanel) dom.appLeftPanel = document.querySelector('.app-left-panel');
  const isCollapsed = dom.appLeftPanel ? dom.appLeftPanel.classList.contains('rail-collapsed') : false;
  collapseServerRail(!isCollapsed);
}

function openServerHub() {
  if (!dom.serverHubModal) return;
  dom.serverHubModal.classList.remove('hidden');
  if (dom.serverHubSearchInput) {
    dom.serverHubSearchInput.value = '';
    dom.serverHubSearchInput.focus();
  }
  if (dom.btnClearHubSearch) dom.btnClearHubSearch.classList.add('hidden');
  renderServerHub();
}

function closeServerHub() {
  if (!dom.serverHubModal) return;
  dom.serverHubModal.classList.add('hidden');
}

function countOnlineUsersInServer(serverId) {
  let count = 0;
  // Current user is always counted
  count++;
  // Global users connected to this server
  for (const [uid, u] of state.globalUsers.entries()) {
    if (uid !== state.currentUser.id && Array.isArray(u.servers) && u.servers.includes(serverId)) {
      count++;
    }
  }
  return count;
}

function renderServerHub(filterQuery = '') {
  if (!dom.serverHubGrid) return;
  const q = (filterQuery || '').trim().toLowerCase();

  const filtered = state.servers.filter(srv => {
    if (!q) return true;
    return (srv.name && srv.name.toLowerCase().includes(q)) || 
           (srv.inviteCode && srv.inviteCode.toLowerCase().includes(q));
  });

  const total = state.servers.length;
  if (dom.serverHubCountBadge) {
    dom.serverHubCountBadge.textContent = total === 1 ? '1 Servidor' : (total + ' Servidores');
  }

  dom.serverHubGrid.innerHTML = '';

  if (filtered.length === 0) {
    if (dom.serverHubEmpty) {
      dom.serverHubEmpty.classList.remove('hidden');
      if (dom.serverHubEmptyDesc) {
        dom.serverHubEmptyDesc.textContent = 'Nenhum servidor encontrado para "' + escapeHtml(filterQuery) + '".';
      }
    }
    return;
  }

  if (dom.serverHubEmpty) dom.serverHubEmpty.classList.add('hidden');

  filtered.forEach(srv => {
    const isActive = srv.id === state.activeServerId;
    const initials = srv.name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase() || 'S';
    const textChannelsCount = (srv.channels || []).filter(c => c.type === 'text').length;
    const voiceChannelsCount = (srv.channels || []).filter(c => c.type === 'voice').length;
    const onlineMembers = countOnlineUsersInServer(srv.id);

    const card = document.createElement('div');
    card.className = 'hub-server-card' + (isActive ? ' is-active' : '');
    card.setAttribute('data-server-id', srv.id);

    const avatarInner = srv.icon 
      ? '<img src="' + escapeHtml(srv.icon) + '" alt="' + escapeHtml(srv.name) + '">' 
      : initials;

    const activeBadge = isActive ? '<span class="hub-active-pill">Ativo</span>' : '';

    card.innerHTML = 
      '<div class="hub-card-banner">' + activeBadge + '</div>' +
      '<div class="hub-card-avatar-wrap">' +
        '<div class="hub-card-avatar">' + avatarInner + '</div>' +
      '</div>' +
      '<div class="hub-card-content">' +
        '<h3 class="hub-card-name" title="' + escapeHtml(srv.name) + '">' + escapeHtml(srv.name) + '</h3>' +
        '<div class="hub-card-invite">' +
          '<svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z"/></svg>' +
          '<span>' + escapeHtml(srv.inviteCode || 'convite') + '</span>' +
        '</div>' +
        '<div class="hub-card-stats">' +
          '<span class="hub-stat-chip" title="Canais de Texto">#' + textChannelsCount + ' texto</span>' +
          '<span class="hub-stat-chip" title="Salas de Voz">🔊 ' + voiceChannelsCount + ' voz</span>' +
          '<span class="hub-stat-chip" title="Membros Online">👥 ' + onlineMembers + ' online</span>' +
        '</div>' +
        '<div class="hub-card-actions">' +
          '<button type="button" class="btn-hub-enter">' +
            (isActive ? '<span>Acessar</span>' : '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"/></svg><span>Entrar</span>') +
          '</button>' +
          '<button type="button" class="btn-hub-copy-invite" title="Copiar Link de Convite">' +
            '<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>' +
          '</button>' +
        '</div>' +
      '</div>';

    // Click on copy invite button
    card.addEventListener('click', (ev) => {
      if (ev.target.closest('.btn-hub-copy-invite')) {
        ev.stopPropagation();
        const origin = window.location.origin;
        const pathname = window.location.pathname;
        const link = origin + pathname + '?invite=' + encodeURIComponent(srv.inviteCode || srv.id);
        copyTextToClipboard(link, 'Link de convite do servidor "' + srv.name + '" copiado!');
        return;
      }

      selectServer(srv.id);
      closeServerHub();
      showToast('Entrou no servidor "' + srv.name + '"', 'info', 1500);
    });

    dom.serverHubGrid.appendChild(card);
  });
}

// --- Server Rail Management ---
function renderServerRail() {
  if (!dom.serverIconsList) return;
  dom.serverIconsList.innerHTML = '';

  state.servers.forEach(srv => {
    const iconWrapper = document.createElement('div');
    iconWrapper.className = 'server-icon' + (srv.id === state.activeServerId ? ' active' : '');
    iconWrapper.title = srv.name;
    iconWrapper.setAttribute('data-server-id', srv.id);
    iconWrapper.setAttribute('data-server-name', srv.name);

    const initials = srv.name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase() || 'S';

    let avatarInner = '';
    if (srv.icon) {
      avatarInner = '<img src="' + escapeHtml(srv.icon) + '" class="server-icon-img" alt="' + escapeHtml(srv.name) + '">';
    } else {
      avatarInner = initials;
    }

    iconWrapper.innerHTML = 
      '<span class="server-pill"></span>' +
      '<div class="server-avatar">' + avatarInner + '</div>';

    iconWrapper.addEventListener('click', () => {
      selectServer(srv.id);
    });

    dom.serverIconsList.appendChild(iconWrapper);
  });
}

function selectServer(serverId, triggerNetwork = true) {
  const targetServer = state.servers.find(s => s.id === serverId);
  if (!targetServer) return;

  const oldServerId = state.activeServerId;
  state.activeServerId = serverId;

  // Update Header
  dom.currentServerName.textContent = targetServer.name;
  if (targetServer.icon) {
    dom.serverHeaderAvatar.innerHTML = '<img src="' + escapeHtml(targetServer.icon) + '" alt="' + escapeHtml(targetServer.name) + '">';
  } else {
    const initials = targetServer.name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase() || 'S';
    dom.serverHeaderAvatar.textContent = initials;
  }

  // Close dropdown menu if open
  if (dom.serverDropdownMenu) {
    dom.serverDropdownMenu.classList.add('hidden');
    if (dom.btnServerMenu) dom.btnServerMenu.classList.remove('open');
  }

  // Update Leave menu item for default server
  if (dom.menuItemLeave) {
    dom.menuItemLeave.style.opacity = (targetServer.id === DEFAULT_SERVER_ID) ? '0.4' : '1';
    dom.menuItemLeave.title = (targetServer.id === DEFAULT_SERVER_ID) ? 'O servidor padrão não pode ser excluído' : 'Sair deste servidor';
  }

  // If connected to voice in old server, disconnect
  if (oldServerId !== serverId && state.connectedVoiceChannel) {
    disconnectVoice();
  }

  // Populate users list for new server immediately from global presence
  if (oldServerId !== serverId) {
    state.users = [];
    for (const [uid, u] of state.globalUsers.entries()) {
      if (uid !== state.currentUser.id && Array.isArray(u.servers) && u.servers.includes(serverId)) {
        state.users.push({ ...u });
      }
    }
  }

  // Announce presence on active server switch without dropping subscriptions
  if (triggerNetwork && state.mqtt && oldServerId !== serverId) {
    publishPresence('join');
    publishPresence('whois');
    broadcastServerChannelsSync();
  }

  renderServerRail();
  renderChannelsList();

  // Select first text channel of the server
  const firstTextChan = targetServer.channels.find(c => c.type === 'text') || targetServer.channels[0];
  if (firstTextChan) {
    selectChannel(firstTextChan.id);
  }
}

// --- URL Invite Link Resolver ---
function checkUrlInvite() {
  const params = new URLSearchParams(window.location.search);
  const inviteCode = params.get('invite') || params.get('server');
  if (!inviteCode) return;

  // Check if we already have this server in our list
  const existing = state.servers.find(s => s.inviteCode === inviteCode || s.id === inviteCode);
  if (existing) {
    selectServer(existing.id);
    showToast('Você acessou o servidor "' + existing.name + '"!', 'info');
  } else {
    // Request info from online peers via discovery topic
    console.log('[ProjetoUS] Consultando convite na nuvem:', inviteCode);
    if (state.mqtt) {
      state.mqtt.publish(TOPICS.discovery, JSON.stringify({
        action: 'request_server',
        inviteCode: inviteCode,
        requesterId: state.currentUser.id
      }));
    }
  }
}

// --- Unread Title Indicator ---
function updateUnreadTitle() {
  let totalUnreads = 0;
  for (const chanId in state.unreadCounts) {
    totalUnreads += state.unreadCounts[chanId] || 0;
  }
  if (totalUnreads > 0) {
    document.title = '(' + totalUnreads + ') ProjetoUS';
  } else {
    document.title = 'ProjetoUS';
  }
}

// --- Voice Channel Members Query (Single Source of Truth, Zero Ghosts) ---
function getVoiceChannelMembers(channelId, serverId = state.activeServerId) {
  const result = [];
  const seenIds = new Set();
  const now = Date.now();

  // 1. Current user if active in this voice channel on this server
  if (state.connectedVoiceChannel && state.connectedVoiceChannel.id === channelId) {
    seenIds.add(state.currentUser.id);
    result.push({
      id: state.currentUser.id,
      username: state.currentUser.username,
      avatar: state.currentUser.avatar || '',
      voiceChannelId: channelId,
      voiceServerId: serverId,
      isSpeaking: dom.myAvatar ? dom.myAvatar.classList.contains('speaking') : false,
      isMuted: state.isMuted,
      isDeafened: state.isDeafened,
      isScreenSharing: state.isSharingScreen,
      isMe: true
    });
  }

  // 2. Members from global presence Map
  for (const [uid, u] of state.globalUsers.entries()) {
    if (uid === state.currentUser.id) continue;
    if (seenIds.has(uid)) continue;
    if (!u.username) continue;
    if (u.lastSeen && (now - u.lastSeen > 25000)) continue;

    // Strict check: must match voiceChannelId AND voiceServerId
    const isThisServer = (u.voiceServerId === serverId || (!u.voiceServerId && (u.activeServerId === serverId || (Array.isArray(u.servers) && u.servers.includes(serverId)))));
    if (u.voiceChannelId === channelId && isThisServer) {
      seenIds.add(uid);
      result.push({
        id: u.id,
        username: u.username || 'Usuário',
        avatar: u.avatar || '',
        voiceChannelId: u.voiceChannelId,
        voiceServerId: u.voiceServerId || serverId,
        isSpeaking: !!u.isSpeaking,
        isMuted: !!u.isMuted,
        isDeafened: !!u.isDeafened,
        isScreenSharing: !!u.isScreenSharing,
        isMe: false,
        lastSeen: u.lastSeen
      });
    }
  }

  // 3. Members from state.users (local cache)
  state.users.forEach(u => {
    if (u.id === state.currentUser.id) return;
    if (seenIds.has(u.id)) return;
    if (!u.username) return;
    if (u.lastSeen && (now - u.lastSeen > 25000)) return;

    const isThisServer = (u.voiceServerId === serverId || (!u.voiceServerId && state.activeServerId === serverId));
    if (u.voiceChannelId === channelId && isThisServer) {
      seenIds.add(u.id);
      result.push({
        id: u.id,
        username: u.username || 'Usuário',
        avatar: u.avatar || '',
        voiceChannelId: u.voiceChannelId,
        voiceServerId: u.voiceServerId || serverId,
        isSpeaking: !!u.isSpeaking,
        isMuted: !!u.isMuted,
        isDeafened: !!u.isDeafened,
        isScreenSharing: !!u.isScreenSharing,
        isMe: false,
        lastSeen: u.lastSeen
      });
    }
  });

  return result;
}

// --- Channels Rendering ---
function renderChannelsList() {
  const channels = getActiveServerChannels();

  dom.textChannelsList.innerHTML = '';
  const textChannels = channels.filter(c => c.type === 'text');
  
  textChannels.forEach(chan => {
    const item = document.createElement('div');
    item.className = 'channel-item';
    item.setAttribute('data-channel-id', chan.id);
    item.setAttribute('data-channel-type', 'text');
    item.setAttribute('data-channel-name', chan.name);
    if (state.activeChannel && state.activeChannel.id === chan.id) {
      item.classList.add('active');
    }
    const unreadCount = state.unreadCounts[chan.id] || 0;
    let unreadBadgeHtml = '';
    if (unreadCount > 0) {
      item.classList.add('has-unread');
      unreadBadgeHtml = '<span class="channel-unread-badge">' + unreadCount + '</span>';
    }
    item.innerHTML = 
      '<span class="unread-pill"></span>' +
      '<span class="channel-icon">#</span>' +
      '<span class="channel-title">' + escapeHtml(chan.name) + '</span>' +
      unreadBadgeHtml;
    item.addEventListener('click', () => selectChannel(chan.id));
    dom.textChannelsList.appendChild(item);
  });

  dom.voiceChannelsList.innerHTML = '';
  const voiceChannels = channels.filter(c => c.type === 'voice');

  voiceChannels.forEach(chan => {
    const container = document.createElement('div');
    container.className = 'voice-channel-group';

    const item = document.createElement('div');
    item.className = 'channel-item';
    item.setAttribute('data-channel-id', chan.id);
    item.setAttribute('data-channel-type', 'voice');
    item.setAttribute('data-channel-name', chan.name);
    if (state.connectedVoiceChannel && state.connectedVoiceChannel.id === chan.id) {
      item.classList.add('active');
    }
    item.innerHTML = '<span class="channel-icon">🔊</span><span class="channel-title">' + escapeHtml(chan.name) + '</span>';
    item.addEventListener('click', () => joinVoiceChannel(chan));

    // Drag-and-drop drop target handlers for voice channels
    item.addEventListener('dragover', (e) => {
      if (!state.draggedVoiceUser) return;
      if (state.draggedVoiceUser.fromChannelId === chan.id) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = 'move';
      item.classList.add('voice-drop-hover');
    });

    item.addEventListener('dragleave', () => {
      item.classList.remove('voice-drop-hover');
    });

    item.addEventListener('drop', (e) => {
      e.preventDefault();
      item.classList.remove('voice-drop-hover');
      let dragData = state.draggedVoiceUser;
      if (!dragData) {
        try {
          const raw = e.dataTransfer.getData('application/json');
          if (raw) dragData = JSON.parse(raw);
        } catch (err) {}
      }
      if (dragData && dragData.userId && dragData.fromChannelId !== chan.id) {
        executeMoveUser(dragData.userId, dragData.username, chan.id, chan.name);
      }
      state.draggedVoiceUser = null;
      document.body.classList.remove('is-dragging-voice-user');
    });

    container.appendChild(item);

    const usersInVoice = getVoiceChannelMembers(chan.id);

    if (usersInVoice.length > 0) {
      const tree = document.createElement('div');
      tree.className = 'voice-users-tree';

      usersInVoice.forEach(u => {
        const row = document.createElement('div');
        row.className = 'voice-user-row';
        row.setAttribute('data-user-id', u.id);
        row.setAttribute('data-user-name', u.username);
        row.setAttribute('data-channel-id', chan.id);
        const isMe = u.id === state.currentUser.id;
        const displayName = isMe ? (u.username + ' (Você)') : u.username;
        const initials = (u.username || '?').substring(0, 2).toUpperCase();

        // Drag-and-drop source setup
        row.setAttribute('draggable', 'true');
        row.title = isMe 
          ? 'Você (botão direito ou arraste para outra sala de voz)' 
          : (u.username + ' (botão direito ou arraste para outra sala de voz)');

        row.addEventListener('dragstart', (e) => {
          if (e.target.closest('button')) {
            e.preventDefault();
            return;
          }
          state.draggedVoiceUser = {
            userId: u.id,
            username: u.username,
            fromChannelId: chan.id
          };
          try {
            e.dataTransfer.setData('application/json', JSON.stringify(state.draggedVoiceUser));
            e.dataTransfer.setData('text/plain', u.username);
            e.dataTransfer.effectAllowed = 'move';
          } catch (err) {}
          row.classList.add('is-dragging-user');
          document.body.classList.add('is-dragging-voice-user');
        });

        row.addEventListener('dragend', () => {
          row.classList.remove('is-dragging-user');
          document.body.classList.remove('is-dragging-voice-user');
          document.querySelectorAll('.channel-item.voice-drop-hover').forEach(el => el.classList.remove('voice-drop-hover'));
          state.draggedVoiceUser = null;
        });

        let avatarContent = u.avatar ? '<img src="' + escapeHtml(u.avatar) + '" alt="Avatar">' : initials;

        row.innerHTML = 
          '<div class="voice-user-avatar ' + (u.isSpeaking ? 'speaking' : '') + '" data-user-id="' + u.id + '">' + avatarContent + '</div>' +
          '<span class="voice-user-name">' + escapeHtml(displayName) + '</span>' +
          '<div class="voice-user-badges">' +
            (u.isScreenSharing ? '<span class="badge-live" title="Transmitindo Tela">AO VIVO</span>' : '') +
            (u.isDeafened ? '<span class="badge-deafened" title="Áudio Desativado (Ensurdecido)">🎧❌</span>' : (u.isMuted ? '<span class="badge-muted" title="Microfone Mutado">🔇</span>' : '')) +
          '</div>';

        tree.appendChild(row);
      });

      container.appendChild(tree);
    }

    dom.voiceChannelsList.appendChild(container);
  });

  // Keep right-side online members list in sync
  renderOnlineMembersList();
}

// --- Online Members Sidebar (Right Side - Online Members Only) ---
function renderOnlineMembersList() {
  if (!dom.onlineMembersList || !dom.membersOnlineCount) return;

  const list = [];
  const activeServerId = state.activeServerId;
  const seenIds = new Set();
  const now = Date.now();

  // 1. Current user (if logged in)
  if (state.currentUser.username) {
    seenIds.add(state.currentUser.id);
    list.push({
      id: state.currentUser.id,
      username: state.currentUser.username,
      avatar: state.currentUser.avatar || '',
      status: state.currentUser.status || 'online',
      voiceChannelId: state.connectedVoiceChannel ? state.connectedVoiceChannel.id : null,
      isSpeaking: dom.myAvatar ? dom.myAvatar.classList.contains('speaking') : false,
      isMuted: state.isMuted,
      isDeafened: state.isDeafened,
      isScreenSharing: state.isSharingScreen,
      isMe: true
    });
  }

  // 2. Global users who belong to this active server
  for (const [uid, u] of state.globalUsers.entries()) {
    if (seenIds.has(uid) || !u.username) continue;
    if (u.lastSeen && (now - u.lastSeen > 25000)) continue;

    // Check if user belongs to active server
    const belongs = (Array.isArray(u.servers) && u.servers.includes(activeServerId)) ||
                    (u.activeServerId === activeServerId) ||
                    (state.users.some(su => su.id === uid));

    if (belongs) {
      seenIds.add(uid);
      const isVoiceInThisServer = (u.voiceServerId === activeServerId || !u.voiceServerId) && !!u.voiceChannelId;
      const isVoiceInOtherServer = (u.voiceServerId && u.voiceServerId !== activeServerId && !!u.voiceChannelId);

      list.push({
        id: u.id,
        username: u.username,
        avatar: u.avatar || '',
        status: u.status || 'online',
        voiceChannelId: isVoiceInThisServer ? u.voiceChannelId : null,
        isVoiceInOtherServer: isVoiceInOtherServer,
        isSpeaking: !!u.isSpeaking,
        isMuted: !!u.isMuted,
        isDeafened: !!u.isDeafened,
        isScreenSharing: !!u.isScreenSharing,
        isMe: false
      });
    }
  }

  // 3. Any in state.users that were not yet processed
  state.users.forEach(u => {
    if (!seenIds.has(u.id) && u.username) {
      if (u.lastSeen && (now - u.lastSeen > 25000)) return;
      seenIds.add(u.id);
      const isVoiceInThisServer = (u.voiceServerId === activeServerId || !u.voiceServerId) && !!u.voiceChannelId;
      const isVoiceInOtherServer = (u.voiceServerId && u.voiceServerId !== activeServerId && !!u.voiceChannelId);

      list.push({
        id: u.id,
        username: u.username,
        avatar: u.avatar || '',
        status: u.status || 'online',
        voiceChannelId: isVoiceInThisServer ? u.voiceChannelId : null,
        isVoiceInOtherServer: isVoiceInOtherServer,
        isSpeaking: !!u.isSpeaking,
        isMuted: !!u.isMuted,
        isDeafened: !!u.isDeafened,
        isScreenSharing: !!u.isScreenSharing,
        isMe: false
      });
    }
  });

  // Sort: current user first, then alphabetically by username
  list.sort((a, b) => {
    if (a.isMe) return -1;
    if (b.isMe) return 1;
    return a.username.localeCompare(b.username, undefined, { sensitivity: 'base' });
  });

  // Update header count
  dom.membersOnlineCount.textContent = list.length;

  dom.onlineMembersList.innerHTML = '';

  const channels = getActiveServerChannels();

  list.forEach(u => {
    const item = document.createElement('div');
    item.className = 'member-item';
    item.dataset.userId = u.id;
    item.setAttribute('data-user-id', u.id);
    item.setAttribute('data-user-name', u.username || '');
    item.setAttribute('data-is-me', u.isMe ? 'true' : 'false');
    item.setAttribute('data-voice-channel-id', u.voiceChannelId || '');

    // Subtitle / Activity
    const uStatus = u.status || 'online';
    let activityText = getStatusLabel(uStatus);
    let activityClass = '';

    if (u.isScreenSharing) {
      activityText = '🔴 Transmitindo Tela';
      activityClass = 'screen-sharing';
    } else if (u.isDeafened) {
      activityText = '🎧❌ Ensurdecido';
    } else if (u.isMuted) {
      activityText = '🔇 Mutado';
    } else if (u.voiceChannelId) {
      const vChan = channels.find(c => c.id === u.voiceChannelId);
      activityText = '🔊 ' + (vChan ? vChan.name : 'Em chamada');
      activityClass = 'in-voice';
    } else if (u.isVoiceInOtherServer) {
      activityText = '🔊 Em chamada';
      activityClass = 'in-voice';
    }

    const avatarHtml = u.avatar
      ? '<img src="' + escapeHtml(u.avatar) + '" alt="' + escapeHtml(u.username) + '">'
      : escapeHtml((u.username || 'U').substring(0, 2).toUpperCase());

    const speakingClass = u.isSpeaking ? ' speaking' : '';

    item.innerHTML =
      '<div class="member-avatar-wrapper">' +
        '<div class="member-avatar' + speakingClass + '" id="member-avatar-' + escapeHtml(u.id) + '">' +
          avatarHtml +
        '</div>' +
        '<div class="member-status-dot ' + uStatus + '" title="' + getStatusTitle(uStatus) + '"></div>' +
      '</div>' +
      '<div class="member-info">' +
        '<div class="member-name-row">' +
          '<span class="member-name">' + escapeHtml(u.username) + '</span>' +
          (u.isMe ? '<span class="member-badge-you">Você</span>' : '') +
        '</div>' +
        '<span class="member-activity ' + activityClass + '">' + escapeHtml(activityText) + '</span>' +
      '</div>';

    // Drag-and-drop: if user is in voice, allow dragging to another voice channel
    if (u.voiceChannelId) {
      item.setAttribute('draggable', 'true');
      item.title = u.isMe 
        ? 'Você (botão direito ou arraste para outra sala de voz)' 
        : (u.username + ' (botão direito ou arraste para outra sala de voz)');

      item.addEventListener('dragstart', (e) => {
        state.draggedVoiceUser = {
          userId: u.id,
          username: u.username,
          fromChannelId: u.voiceChannelId
        };
        try {
          e.dataTransfer.setData('application/json', JSON.stringify(state.draggedVoiceUser));
          e.dataTransfer.setData('text/plain', u.username);
          e.dataTransfer.effectAllowed = 'move';
        } catch (err) {}
        item.classList.add('is-dragging-user');
        document.body.classList.add('is-dragging-voice-user');
      });

      item.addEventListener('dragend', () => {
        item.classList.remove('is-dragging-user');
        document.body.classList.remove('is-dragging-voice-user');
        document.querySelectorAll('.channel-item.voice-drop-hover').forEach(el => el.classList.remove('voice-drop-hover'));
        state.draggedVoiceUser = null;
      });
    }

    // Click: if peer is in voice channel and not self, allow moving
    item.addEventListener('click', () => {
      if (u.voiceChannelId && !u.isMe) {
        openMoveModal(u.id, u.username, u.voiceChannelId);
      }
    });

    dom.onlineMembersList.appendChild(item);
  });
}

function selectChannel(channelId) {
  const channels = getActiveServerChannels();
  const chan = channels.find(c => c.id === channelId);
  if (!chan) return;

  state.activeChannel = chan;

  dom.topbarChannelIcon.textContent = chan.type === 'voice' ? '🔊' : '#';
  dom.topbarChannelName.textContent = chan.name;
  dom.topbarChannelTopic.textContent = chan.topic || '';

  if (chan.type === 'voice') {
    dom.chatSection.classList.add('hidden');
    dom.voiceLoungeSection.classList.remove('hidden');
    renderVoiceLounge();
  } else {
    // If channel has unread messages, prepare divider count and clear unread
    if (state.unreadCounts[chan.id] > 0) {
      state.lastViewedUnreadCount = state.unreadCounts[chan.id];
      delete state.unreadCounts[chan.id];
      updateUnreadTitle();
    } else {
      state.lastViewedUnreadCount = 0;
    }

    dom.voiceLoungeSection.classList.add('hidden');
    dom.chatSection.classList.remove('hidden');
    renderChatFeed();
    requestChannelHistory(chan.id, state.activeServerId);
    dom.chatInput.placeholder = 'Conversar em #' + chan.name;
    dom.chatInput.focus();
  }

  renderChannelsList();
}

async function joinVoiceChannel(channel) {
  if (state.connectedVoiceChannel && state.connectedVoiceChannel.id === channel.id) {
    selectChannel(channel.id);
    return;
  }

  if (state.connectedVoiceChannel) {
    closeAllPeerConnections();
  }

  state.connectedVoiceChannel = channel;
  window.audioEngine.playConnect();

  dom.voiceStatusPanel.classList.remove('hidden');
  dom.voiceStatusRoomName.textContent = channel.name;
  dom.topbarVoiceBadge.classList.add('active');
  dom.topbarVoiceBadgeText.textContent = channel.name;

  await window.audioEngine.startMicrophone();
  state.localAudioStream = window.audioEngine.micStream;

  // Update local state immediately
  const myGu = state.globalUsers.get(state.currentUser.id) || { id: state.currentUser.id, username: state.currentUser.username };
  state.globalUsers.set(state.currentUser.id, {
    ...myGu,
    id: state.currentUser.id,
    username: state.currentUser.username,
    avatar: state.currentUser.avatar || '',
    voiceChannelId: channel.id,
    voiceServerId: state.activeServerId,
    lastSeen: Date.now()
  });

  if (state.mqtt) {
    state.mqtt.publish(TOPICS.voice(state.activeServerId), JSON.stringify({
      action: 'join',
      userId: state.currentUser.id,
      username: state.currentUser.username,
      avatar: state.currentUser.avatar || '',
      voiceChannelId: channel.id,
      voiceServerId: state.activeServerId
    }));
    publishPresence('state');
  }

  selectChannel(channel.id);
}

function disconnectVoice() {
  if (!state.connectedVoiceChannel) return;

  if (state.isSharingScreen) stopScreenShare();
  if (state.isCameraOn) stopLoungeCamera();
  if (state.isLoungeFullscreen) toggleLoungeFullscreen();
  closeAllPeerConnections();

  window.audioEngine.playDisconnect();
  window.audioEngine.stopMicrophone();
  state.localAudioStream = null;

  const leftChannelId = state.connectedVoiceChannel.id;
  const leftServerId = state.activeServerId;
  state.connectedVoiceChannel = null;
  dom.voiceStatusPanel.classList.add('hidden');
  dom.topbarVoiceBadge.classList.remove('active');
  dom.myAvatar.classList.remove('speaking');

  // Immediately clear our own voice channel in local state
  const myGu = state.globalUsers.get(state.currentUser.id);
  if (myGu) {
    myGu.voiceChannelId = null;
    myGu.voiceServerId = null;
    myGu.isSpeaking = false;
    myGu.isScreenSharing = false;
  }
  const mySu = state.users.find(u => u.id === state.currentUser.id);
  if (mySu) {
    mySu.voiceChannelId = null;
    mySu.voiceServerId = null;
    mySu.isSpeaking = false;
    mySu.isScreenSharing = false;
  }

  if (state.mqtt) {
    state.mqtt.publish(TOPICS.voice(leftServerId), JSON.stringify({
      action: 'leave',
      userId: state.currentUser.id,
      voiceChannelId: leftChannelId,
      voiceServerId: leftServerId
    }));
    publishPresence('state');
  }

  renderChannelsList();
  renderVoiceLounge();
  renderOnlineMembersList();

  if (state.activeChannel && state.activeChannel.type === 'voice') {
    const firstText = getActiveServerChannels().find(c => c.type === 'text');
    if (firstText) selectChannel(firstText.id);
  }
}

function updateLoungeDockButtons() {
  if (!dom.loungeDockMic) return;

  const isConnected = state.connectedVoiceChannel && state.activeChannel && state.connectedVoiceChannel.id === state.activeChannel.id;

  // Mic button
  dom.loungeDockMic.classList.toggle('is-muted', state.isMuted);
  const iconMicOn = dom.loungeDockMic.querySelector('.dock-icon-mic-on');
  const iconMicOff = dom.loungeDockMic.querySelector('.dock-icon-mic-off');
  if (iconMicOn && iconMicOff) {
    iconMicOn.classList.toggle('hidden', state.isMuted);
    iconMicOff.classList.toggle('hidden', !state.isMuted);
  }
  dom.loungeDockMic.title = state.isMuted ? 'Desmutar Microfone' : 'Silenciar Microfone';

  // Deafen button
  dom.loungeDockDeafen.classList.toggle('is-deafened', state.isDeafened);
  const iconDeafenOff = dom.loungeDockDeafen.querySelector('.dock-icon-deafen-off');
  const iconDeafenOn = dom.loungeDockDeafen.querySelector('.dock-icon-deafen-on');
  if (iconDeafenOff && iconDeafenOn) {
    iconDeafenOff.classList.toggle('hidden', state.isDeafened);
    iconDeafenOn.classList.toggle('hidden', !state.isDeafened);
  }
  dom.loungeDockDeafen.title = state.isDeafened ? 'Reativar Áudio' : 'Ensurdecer Áudio';

  // Screenshare button
  dom.loungeDockScreenshare.classList.toggle('active-sharing', state.isSharingScreen);
  dom.loungeDockScreenshare.title = state.isSharingScreen ? 'Parar Transmissão de Tela' : 'Compartilhar Tela';

  // Camera button
  dom.loungeDockCamera.classList.toggle('active-cam', state.isCameraOn);
  const iconCamOn = dom.loungeDockCamera.querySelector('.dock-icon-cam-on');
  const iconCamOff = dom.loungeDockCamera.querySelector('.dock-icon-cam-off');
  if (iconCamOn && iconCamOff) {
    iconCamOn.classList.toggle('hidden', !state.isCameraOn);
    iconCamOff.classList.toggle('hidden', state.isCameraOn);
  }
  dom.loungeDockCamera.title = state.isCameraOn ? 'Desativar Câmera' : 'Ativar Câmera';

  // Fullscreen buttons
  if (dom.loungeDockFullscreen) {
    dom.loungeDockFullscreen.classList.toggle('active-sharing', state.isLoungeFullscreen);
  }
  if (dom.loungeBtnFullscreen) {
    dom.loungeBtnFullscreen.classList.toggle('active', state.isLoungeFullscreen);
  }

  // Disconnect button
  if (dom.loungeDockDisconnect) {
    dom.loungeDockDisconnect.style.display = isConnected ? 'flex' : 'none';
  }
}

function toggleLoungeFullscreen() {
  state.isLoungeFullscreen = !state.isLoungeFullscreen;
  dom.voiceLoungeSection.classList.toggle('voice-lounge-fullscreen', state.isLoungeFullscreen);
  updateLoungeDockButtons();

  if (state.isLoungeFullscreen) {
    showToast('Modo Cinema ativado (Pressione ESC ou o botão para sair)', 'info');
  }
}

function toggleLoungeMeterPopover() {
  if (dom.loungeMeterPopover) {
    dom.loungeMeterPopover.classList.toggle('hidden');
  }
}

async function toggleLoungeCamera() {
  if (state.isCameraOn) {
    stopLoungeCamera();
  } else {
    await startLoungeCamera();
  }
}

async function startLoungeCamera() {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 1280 }, height: { ideal: 720 } },
      audio: false
    });
    state.isCameraOn = true;
    state.cameraStream = stream;

    // Show video preview in screen share container if no screen share is active
    if (!state.isSharingScreen) {
      dom.screenshareVideo.srcObject = stream;
      dom.screenshareDisplayContainer.classList.remove('hidden');
      dom.screenshareStreamerName.textContent = '📹 Câmera de ' + state.currentUser.username;
      if (dom.loungeStage) dom.loungeStage.classList.add('stage-theater-mode');
    }

    // Add video track to active WebRTC peers
    const videoTrack = stream.getVideoTracks()[0];
    if (videoTrack) {
      for (const [peerId, pc] of rtc.peers.entries()) {
        try {
          const sender = pc.addTrack(videoTrack, stream);
          rtc.screenSenders.set(peerId, sender);
        } catch (e) {
          console.warn('[WebRTC] Erro ao enviar track de câmera:', e);
        }
      }
      videoTrack.onended = () => stopLoungeCamera();
    }

    updateLoungeDockButtons();
    showToast('Câmera ativada com sucesso!', 'success');
  } catch (err) {
    console.warn('Erro ao acessar câmera:', err);
    showToast('Não foi possível acessar a câmera ou permissão não concedida.', 'warning');
  }
}

function stopLoungeCamera() {
  state.isCameraOn = false;
  if (state.cameraStream) {
    state.cameraStream.getTracks().forEach(t => t.stop());
    state.cameraStream = null;
  }
  if (!state.isSharingScreen) {
    dom.screenshareVideo.srcObject = null;
    dom.screenshareDisplayContainer.classList.add('hidden');
    if (dom.loungeStage) dom.loungeStage.classList.remove('stage-theater-mode');
  }
  updateLoungeDockButtons();
  showToast('Câmera desativada.', 'info');
}

function renderVoiceLounge() {
  if (!state.activeChannel || state.activeChannel.type !== 'voice') return;

  const currentChan = state.activeChannel;
  dom.loungeRoomTitle.textContent = '🔊 ' + currentChan.name;

  const members = getVoiceChannelMembers(currentChan.id);
  const isConnectedToThisChan = state.connectedVoiceChannel && state.connectedVoiceChannel.id === currentChan.id;

  // Update participants counter & RTC status badge
  if (dom.loungeMembersCount) {
    dom.loungeMembersCount.textContent = members.length + (members.length === 1 ? ' Conectado' : ' Conectados');
  }
  if (dom.loungeRtcStatusText) {
    dom.loungeRtcStatusText.textContent = isConnectedToThisChan ? 'WebRTC P2P Conectado' : 'Pronto para Conectar';
  }

  // Empty state handling
  if (members.length === 0) {
    if (dom.loungeEmptyState) dom.loungeEmptyState.classList.remove('hidden');
    if (dom.loungeMembersGrid) {
      dom.loungeMembersGrid.classList.add('hidden');
      dom.loungeMembersGrid.innerHTML = '';
    }
    if (dom.loungeBtnEmptyJoin) {
      dom.loungeBtnEmptyJoin.onclick = () => joinVoiceChannel(currentChan);
    }
  } else {
    if (dom.loungeEmptyState) dom.loungeEmptyState.classList.add('hidden');
    if (dom.loungeMembersGrid) {
      dom.loungeMembersGrid.classList.remove('hidden');
      dom.loungeMembersGrid.innerHTML = '';

      // Dynamic Grid Layout class
      dom.loungeMembersGrid.className = 'lounge-members-grid';
      if (members.length === 1) {
        dom.loungeMembersGrid.classList.add('grid-count-1');
      } else if (members.length === 2) {
        dom.loungeMembersGrid.classList.add('grid-count-2');
      } else if (members.length <= 4) {
        dom.loungeMembersGrid.classList.add('grid-count-3-4');
      } else {
        dom.loungeMembersGrid.classList.add('grid-count-many');
      }

      // Check theater mode (screen share or camera)
      const isVideoActive = !dom.screenshareDisplayContainer.classList.contains('hidden');
      if (dom.loungeStage) {
        dom.loungeStage.classList.toggle('stage-theater-mode', isVideoActive);
      }

      members.forEach(u => {
        const isMe = u.id === state.currentUser.id;
        const initials = (u.username || '?').substring(0, 2).toUpperCase();
        const card = document.createElement('div');
        card.className = 'lounge-member-card ' + (u.isSpeaking ? 'speaking' : '');
        card.setAttribute('data-user-id', u.id);
        card.setAttribute('data-user-name', u.username || '');
        card.setAttribute('data-channel-id', currentChan.id);
        card.setAttribute('data-is-me', isMe ? 'true' : 'false');

        card.title = isMe 
          ? 'Você (botão direito para opções)' 
          : (u.username + ' (botão direito para opções)');

        let avatarBigContent = u.avatar ? '<img src="' + escapeHtml(u.avatar) + '" alt="Avatar">' : initials;

        // Card controls for peers: volume slider
        let cardControlsHtml = '';
        if (!isMe) {
          const userVol = state.userVolumes[u.id] !== undefined ? state.userVolumes[u.id] : 100;
          cardControlsHtml = 
            '<div class="lounge-card-controls">' +
              '<div class="lounge-volume-wrapper" title="Volume de ' + escapeHtml(u.username) + '">' +
                '<span class="lounge-volume-icon">🔊</span>' +
                '<input type="range" class="lounge-volume-slider" data-user-id="' + u.id + '" min="0" max="200" value="' + userVol + '" title="Volume: ' + userVol + '%">' +
              '</div>' +
            '</div>';
        }

        let statusText = 'Ouvindo';
        let statusClass = '';
        if (u.isScreenSharing) {
          statusText = '🔴 Transmitindo Tela';
          statusClass = 'speaking-badge';
        } else if (u.isDeafened) {
          statusText = 'Ensurdecido 🎧❌';
          statusClass = 'muted-badge';
        } else if (u.isMuted) {
          statusText = 'Mutado 🔇';
          statusClass = 'muted-badge';
        } else if (u.isSpeaking) {
          statusText = 'Falando... 🟢';
          statusClass = 'speaking-badge';
        }

        card.innerHTML = 
          '<div class="lounge-avatar-container">' +
            '<div class="lounge-avatar-big ' + (u.isSpeaking ? 'speaking' : '') + '">' + avatarBigContent + '</div>' +
            '<div class="lounge-speaking-halo"></div>' +
          '</div>' +
          '<div class="lounge-member-name">' +
            '<span>' + escapeHtml(u.username) + '</span>' +
            (isMe ? '<span class="lounge-badge-you">Você</span>' : '') +
          '</div>' +
          '<div class="lounge-member-status ' + statusClass + '">' + statusText + '</div>' +
          cardControlsHtml;

        // Hook up peer volume slider using Web Audio Gain Node
        const volSlider = card.querySelector('.lounge-volume-slider');
        if (volSlider) {
          const updateCardVol = (e) => {
            const val = parseInt(e.target.value, 10);
            setUserVolume(u.id, val);
          };
          volSlider.addEventListener('input', updateCardVol);
          volSlider.addEventListener('change', updateCardVol);
          volSlider.addEventListener('click', (e) => e.stopPropagation());
          volSlider.addEventListener('pointerdown', (e) => e.stopPropagation());
          volSlider.addEventListener('mousedown', (e) => e.stopPropagation());
        }

        dom.loungeMembersGrid.appendChild(card);
      });
    }
  }

  // Update legacy button for safety
  if (dom.loungeDisconnectBtn) {
    if (isConnectedToThisChan) {
      dom.loungeDisconnectBtn.textContent = 'Desconectar da Sala';
      dom.loungeDisconnectBtn.onclick = disconnectVoice;
    } else {
      dom.loungeDisconnectBtn.textContent = 'Entrar nesta Sala de Voz';
      dom.loungeDisconnectBtn.onclick = () => joinVoiceChannel(currentChan);
    }
  }

  updateLoungeDockButtons();
}

// --- Move User Logic ---
function openMoveModal(userId, username, currentChannelId) {
  state.pendingMoveUser = { userId, username, currentChannelId };
  dom.moveModalTitle.textContent = 'Mover ' + username;
  dom.moveModalSubtitle.textContent = 'Escolha a sala de voz de destino para transferir ' + username + ':';
  dom.moveChannelsList.innerHTML = '';

  const voiceChannels = getActiveServerChannels().filter(c => c.type === 'voice' && c.id !== currentChannelId);
  if (voiceChannels.length === 0) {
    dom.moveChannelsList.innerHTML = '<div style="color: var(--text-muted); font-size: 13px; text-align: center; padding: 12px 0;">Não há outras salas de voz disponíveis. Crie uma sala nova primeiro!</div>';
  } else {
    voiceChannels.forEach(chan => {
      const btn = document.createElement('button');
      btn.className = 'move-channel-option';
      btn.type = 'button';
      btn.innerHTML = '<span class="chan-icon">🔊</span><span>' + escapeHtml(chan.name) + '</span>';
      btn.addEventListener('click', () => {
        executeMoveUser(userId, username, chan.id, chan.name);
      });
      dom.moveChannelsList.appendChild(btn);
    });
  }

  dom.moveModal.classList.remove('hidden');
}

function executeMoveUser(userId, username, toChannelId, toChannelName) {
  if (dom.moveModal) dom.moveModal.classList.add('hidden');

  // If local user is moving self
  if (userId === state.currentUser.id) {
    const destChan = getActiveServerChannels().find(c => c.id === toChannelId);
    if (destChan) {
      joinVoiceChannel(destChan);
      showToast('Você mudou para a sala ' + toChannelName, 'info');
    }
    return;
  }

  // Update locally immediately for instant responsive UI
  const targetUser = state.users.find(u => u.id === userId);
  if (targetUser) {
    targetUser.voiceChannelId = toChannelId;
  }
  const globalUser = state.globalUsers ? state.globalUsers.get(userId) : null;
  if (globalUser) {
    globalUser.voiceChannelId = toChannelId;
    globalUser.voiceServerId = state.activeServerId;
  }
  renderChannelsList();
  renderVoiceLounge();

  if (state.mqtt) {
    state.mqtt.publish(TOPICS.voice(state.activeServerId), JSON.stringify({
      action: 'move',
      targetUserId: userId,
      targetUserName: username,
      toChannelId: toChannelId,
      toChannelName: toChannelName,
      movedBy: state.currentUser.username
    }));
  }

  showToast('Você moveu ' + username + ' para ' + toChannelName, 'info');
}

// --- Text Chat Management & Permanent Persistence ---
function updateUserInStoredMessages(userId, newUsername, newAvatar, oldUsername) {
  if (!userId && !oldUsername) return;
  let hasChanges = false;
  for (const srvId in state.messages) {
    for (const chanId in state.messages[srvId]) {
      const list = state.messages[srvId][chanId];
      if (Array.isArray(list)) {
        list.forEach(m => {
          if (!m) return;
          const matchAuthor = (userId && m.authorId === userId) || (oldUsername && m.author === oldUsername);
          if (matchAuthor) {
            if (userId && !m.authorId) m.authorId = userId;
            if (newUsername && m.author !== newUsername) {
              m.author = newUsername;
              hasChanges = true;
            }
            if (newAvatar !== undefined && m.authorAvatar !== newAvatar) {
              m.authorAvatar = newAvatar;
              hasChanges = true;
            }
          }
          const matchReply = (userId && m.replyTo && m.replyTo.authorId === userId) || (oldUsername && m.replyTo && m.replyTo.author === oldUsername);
          if (matchReply) {
            if (userId && !m.replyTo.authorId) m.replyTo.authorId = userId;
            if (newUsername && m.replyTo.author !== newUsername) {
              m.replyTo.author = newUsername;
              hasChanges = true;
            }
          }
        });
      }
    }
  }
  if (hasChanges) {
    saveStoredMessages();
  }
}

function startReplyingToMessage(msgId, author, text, authorId) {
  if (!msgId) return;
  state.replyingTo = {
    id: msgId,
    author: author || 'Usuário',
    text: text || '',
    authorId: authorId || ''
  };
  if (dom.replyBarAuthor) dom.replyBarAuthor.textContent = '@' + state.replyingTo.author;
  if (dom.replyBarSnippet) {
    const cleanText = (state.replyingTo.text || '').trim();
    dom.replyBarSnippet.textContent = cleanText.length > 55 ? ('"' + cleanText.substring(0, 55) + '..."') : ('"' + cleanText + '"');
  }
  if (dom.chatReplyBar) dom.chatReplyBar.classList.remove('hidden');
  if (dom.chatInput) dom.chatInput.focus();
}

function cancelReplyingToMessage() {
  state.replyingTo = null;
  if (dom.chatReplyBar) dom.chatReplyBar.classList.add('hidden');
}

function scrollToChatMessage(targetId) {
  if (!targetId || !dom.messagesFeed) return;
  const el = dom.messagesFeed.querySelector('.message-item[data-message-id="' + targetId + '"]');
  if (el) {
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    el.classList.add('message-highlight');
    setTimeout(() => {
      el.classList.remove('message-highlight');
    }, 1800);
  } else {
    showToast('Mensagem original não está visível neste canal.', 'info');
  }
}
window.scrollToChatMessage = scrollToChatMessage;

function deleteChatMessage(msgId) {
  if (!msgId || !state.activeChannel) return;
  const srvId = state.activeServerId;
  const chanId = state.activeChannel.id;

  if (state.messages[srvId] && state.messages[srvId][chanId]) {
    state.messages[srvId][chanId] = state.messages[srvId][chanId].filter(m => m.id !== msgId);
    saveStoredMessages();
  }

  const el = dom.messagesFeed.querySelector('.message-item[data-message-id="' + msgId + '"]');
  if (el) {
    el.style.transition = 'opacity 0.2s ease, transform 0.2s ease';
    el.style.opacity = '0';
    el.style.transform = 'translateX(20px)';
    setTimeout(() => el.remove(), 200);
  }

  if (state.mqtt) {
    state.mqtt.publish(TOPICS.chat(srvId), JSON.stringify({
      action: 'delete_message',
      channelId: chanId,
      messageId: msgId
    }), { qos: 1 });
  }

  showToast('Mensagem apagada.', 'info');
}

function renderChatFeed() {
  if (!state.activeChannel || state.activeChannel.type !== 'text') return;

  const srvId = state.activeServerId;
  const chanId = state.activeChannel.id;

  if (!state.messages[srvId]) state.messages[srvId] = {};
  const msgs = state.messages[srvId][chanId] || [];

  dom.welcomeTitle.textContent = 'Bem-vindo ao #' + state.activeChannel.name + '!';
  dom.welcomeDesc.textContent = 'Este é o início do canal #' + state.activeChannel.name + ' no ' + getActiveServer().name + '.';

  dom.messagesFeed.innerHTML = '';
  const unreadCount = state.lastViewedUnreadCount || 0;
  const unreadStartIndex = unreadCount > 0 ? Math.max(0, msgs.length - unreadCount) : -1;

  msgs.forEach((m, idx) => {
    appendChatMessage(m, idx === unreadStartIndex);
  });

  state.lastViewedUnreadCount = 0;
  scrollToBottom();
}

function appendChatMessage(msg, isUnreadDivider = false) {
  if (!msg) return;

  if (isUnreadDivider) {
    const divider = document.createElement('div');
    divider.className = 'unread-divider';
    divider.innerHTML = '<span class="unread-line"></span><span class="unread-badge">NOVAS MENSAGENS</span><span class="unread-line"></span>';
    dom.messagesFeed.appendChild(divider);
  }

  // Prevent duplicate rendering in DOM
  if (msg.id && dom.messagesFeed.querySelector('.message-item[data-message-id="' + msg.id + '"]')) {
    return;
  }

  // Dynamic user resolution (ensures current username and avatar are always used)
  let displayAuthor = msg.author || 'Usuário';
  let displayAvatar = msg.authorAvatar;
  if (msg.authorId === state.currentUser.id || (msg.author && msg.author === state.currentUser.username)) {
    displayAuthor = state.currentUser.username || msg.author || 'Usuário';
    if (state.currentUser.avatar !== undefined) displayAvatar = state.currentUser.avatar;
  } else if (msg.authorId && state.globalUsers.has(msg.authorId)) {
    const gu = state.globalUsers.get(msg.authorId);
    if (gu.username) displayAuthor = gu.username;
    if (gu.avatar !== undefined) displayAvatar = gu.avatar;
  } else if (msg.authorId && state.knownUsers && state.knownUsers[msg.authorId]) {
    const ku = state.knownUsers[msg.authorId];
    if (ku.username) displayAuthor = ku.username;
    if (ku.avatar !== undefined) displayAvatar = ku.avatar;
  }

  const item = document.createElement('div');
  item.className = 'message-item';
  if (msg.id) item.setAttribute('data-message-id', msg.id);
  if (msg.authorId) item.setAttribute('data-author-id', msg.authorId);
  if (displayAuthor) item.setAttribute('data-author-name', displayAuthor);
  if (msg.text) item.setAttribute('data-message-text', msg.text);
  if (msg.gifUrl) item.setAttribute('data-gif-url', msg.gifUrl);
  if (msg.isSystem) item.classList.add('system-msg');

  const initials = (displayAuthor || '?').substring(0, 2).toUpperCase();
  const avatarHtml = displayAvatar 
    ? '<img src="' + escapeHtml(displayAvatar) + '" alt="Avatar">'
    : initials;

  let replyHtml = '';
  if (msg.replyTo && msg.replyTo.id) {
    let replyAuthor = msg.replyTo.author || 'Usuário';
    if (msg.replyTo.authorId === state.currentUser.id || (msg.replyTo.author && msg.replyTo.author === state.currentUser.username)) {
      replyAuthor = state.currentUser.username || replyAuthor;
    } else if (msg.replyTo.authorId && state.globalUsers.has(msg.replyTo.authorId)) {
      const rgu = state.globalUsers.get(msg.replyTo.authorId);
      if (rgu.username) replyAuthor = rgu.username;
    } else if (msg.replyTo.authorId && state.knownUsers && state.knownUsers[msg.replyTo.authorId]) {
      const rku = state.knownUsers[msg.replyTo.authorId];
      if (rku.username) replyAuthor = rku.username;
    }
    replyHtml = 
      '<div class="message-reply-preview" onclick="scrollToChatMessage(\'' + escapeHtml(msg.replyTo.id) + '\')">' +
        '<svg class="reply-spine-icon" width="14" height="14" viewBox="0 0 24 24" fill="currentColor">' +
          '<path d="M10 9V5l-7 7 7 7v-4.1c5 0 8.5 1.6 11 5.1-1-5-4-10-11-11z"/>' +
        '</svg>' +
        '<span class="reply-author">@' + escapeHtml(replyAuthor) + '</span>' +
        '<span class="reply-snippet">' + escapeHtml(msg.replyTo.text || '') + '</span>' +
      '</div>';
  }

  let contentHtml = '';
  if (msg.text) {
    contentHtml += '<div class="message-text">' + escapeHtml(msg.text) + '</div>';
  }
  if (msg.gifUrl) {
    contentHtml += 
      '<div class="message-gif-container">' +
        '<img class="message-gif" src="' + escapeHtml(msg.gifUrl) + '" alt="GIF" loading="lazy" onclick="window.open(this.src, \'_blank\')">' +
      '</div>';
  }

  let actionsHtml = '';
  if (!msg.isSystem) {
    const isOwner = msg.authorId === state.currentUser.id;
    actionsHtml = 
      '<div class="message-actions">' +
        '<button type="button" class="btn-msg-action action-reply" title="Responder">' +
          '<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M10 9V5l-7 7 7 7v-4.1c5 0 8.5 1.6 11 5.1-1-5-4-10-11-11z"/></svg>' +
        '</button>' +
        (isOwner ? 
        '<button type="button" class="btn-msg-action action-delete" title="Apagar Mensagem">' +
          '<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>' +
        '</button>' : '') +
      '</div>';
  }

  item.innerHTML = 
    actionsHtml +
    '<div class="message-avatar" data-user-id="' + escapeHtml(msg.authorId || '') + '" data-user-name="' + escapeHtml(displayAuthor || '') + '">' + avatarHtml + '</div>' +
    '<div class="message-content-wrapper">' +
      replyHtml +
      '<div class="message-header">' +
        '<span class="message-author" data-user-id="' + escapeHtml(msg.authorId || '') + '" data-user-name="' + escapeHtml(displayAuthor || '') + '">' + escapeHtml(displayAuthor) + '</span>' +
        '<span class="message-time">' + escapeHtml(msg.timestamp) + '</span>' +
      '</div>' +
      contentHtml +
    '</div>';

  const btnReply = item.querySelector('.action-reply');
  if (btnReply) {
    btnReply.addEventListener('click', () => {
      startReplyingToMessage(msg.id, displayAuthor, msg.text || (msg.gifUrl ? '[GIF]' : ''), msg.authorId);
    });
  }

  const btnDelete = item.querySelector('.action-delete');
  if (btnDelete) {
    btnDelete.addEventListener('click', () => {
      deleteChatMessage(msg.id);
    });
  }

  dom.messagesFeed.appendChild(item);
}

function sendGifMessage(gifUrl) {
  if (!gifUrl || !state.activeChannel) return;
  const cleanUrl = gifUrl.trim();
  if (!cleanUrl) return;

  const now = new Date();
  const hours = String(now.getHours()).padStart(2, '0');
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const msgId = 'm-' + Date.now() + '-' + Math.random().toString(36).substring(2, 7);

  const newMsg = {
    id: msgId,
    author: state.currentUser.username,
    authorId: state.currentUser.id,
    authorAvatar: state.currentUser.avatar || '',
    text: '',
    gifUrl: cleanUrl,
    timestamp: 'Hoje às ' + hours + ':' + minutes
  };

  if (state.replyingTo) {
    newMsg.replyTo = {
      id: state.replyingTo.id,
      author: state.replyingTo.author,
      text: state.replyingTo.text,
      authorId: state.replyingTo.authorId
    };
    cancelReplyingToMessage();
  }

  state.seenMessageIds.add(msgId);

  const srvId = state.activeServerId;
  const chanId = state.activeChannel.id;

  if (!state.messages[srvId]) state.messages[srvId] = {};
  if (!state.messages[srvId][chanId]) state.messages[srvId][chanId] = [];

  state.messages[srvId][chanId].push(newMsg);
  saveStoredMessages();

  appendChatMessage(newMsg);
  scrollToBottom();

  if (state.mqtt) {
    state.mqtt.publish(TOPICS.chat(srvId), JSON.stringify({
      channelId: chanId,
      message: newMsg
    }), { qos: 1 });
  }

  dom.gifPickerModal.classList.add('hidden');
  if (dom.gifCustomUrlInput) dom.gifCustomUrlInput.value = '';
}

let isSendingMessage = false;

function sendCurrentChatMessage() {
  const text = dom.chatInput.value.trim();
  if (!text || !state.activeChannel || isSendingMessage) return;

  isSendingMessage = true;
  dom.chatInput.value = '';

  const now = new Date();
  const hours = String(now.getHours()).padStart(2, '0');
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const msgId = 'm-' + Date.now() + '-' + Math.random().toString(36).substring(2, 7);

  const newMsg = {
    id: msgId,
    author: state.currentUser.username,
    authorId: state.currentUser.id,
    authorAvatar: state.currentUser.avatar || '',
    text,
    timestamp: 'Hoje às ' + hours + ':' + minutes
  };

  if (state.replyingTo) {
    newMsg.replyTo = {
      id: state.replyingTo.id,
      author: state.replyingTo.author,
      text: state.replyingTo.text,
      authorId: state.replyingTo.authorId
    };
    cancelReplyingToMessage();
  }

  // Register locally to prevent reflection duplicate
  state.seenMessageIds.add(msgId);

  const srvId = state.activeServerId;
  const chanId = state.activeChannel.id;

  if (!state.messages[srvId]) state.messages[srvId] = {};
  if (!state.messages[srvId][chanId]) state.messages[srvId][chanId] = [];

  state.messages[srvId][chanId].push(newMsg);
  saveStoredMessages();

  try {
    appendChatMessage(newMsg);
    scrollToBottom();

    if (state.mqtt) {
      state.mqtt.publish(TOPICS.chat(srvId), JSON.stringify({
        channelId: chanId,
        message: newMsg
      }), { qos: 1 });
    }
  } catch (err) {
    console.error('Erro ao enviar mensagem:', err);
  } finally {
    setTimeout(() => {
      isSendingMessage = false;
    }, 50);
  }

  dom.chatInput.focus();
}

function scrollToBottom() {
  dom.messagesContainer.scrollTop = dom.messagesContainer.scrollHeight;
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// --- Audio Controls Helpers ---
function toggleMute() {
  if (state.isDeafened) {
    toggleDeafen();
    return;
  }
  state.isMuted = !state.isMuted;
  window.audioEngine.setMute(state.isMuted);
  dom.btnToggleMute.classList.toggle('active-red', state.isMuted);
  dom.btnToggleMute.title = state.isMuted ? 'Desmutar Microfone' : 'Mutar Microfone';

  if (state.mqtt) {
    state.mqtt.publish(TOPICS.voice(state.activeServerId), JSON.stringify({
      action: 'state',
      userId: state.currentUser.id,
      isMuted: state.isMuted,
      isDeafened: state.isDeafened,
      isSpeaking: false
    }));
  }
  renderChannelsList();
  renderVoiceLounge();
}

function toggleDeafen() {
  state.isDeafened = !state.isDeafened;

  if (state.isDeafened) {
    state.isMuted = true;
    window.audioEngine.setMute(true);
    dom.btnToggleMute.classList.add('active-red');
    dom.btnToggleMute.title = 'Desmutar Microfone';
  } else {
    state.isMuted = false;
    window.audioEngine.setMute(false);
    dom.btnToggleMute.classList.remove('active-red');
    dom.btnToggleMute.title = 'Mutar Microfone';
  }

  window.audioEngine.setDeafen(state.isDeafened);
  window.audioEngine.playDeafen(state.isDeafened);
  updateRemoteAudiosMuteState();

  dom.btnToggleDeafen.classList.toggle('active-red', state.isDeafened);
  dom.btnToggleDeafen.title = state.isDeafened ? 'Reativar Áudio (Ensurdecido)' : 'Desativar Áudio (Ensurdecer)';

  if (state.isDeafened) {
    showToast('Áudio desativado (Ensurdecido). Você não ouvirá ninguém.', 'warning');
  } else {
    showToast('Áudio reativado. Você agora pode ouvir a sala.', 'success');
  }

  if (state.mqtt) {
    state.mqtt.publish(TOPICS.voice(state.activeServerId), JSON.stringify({
      action: 'state',
      userId: state.currentUser.id,
      isMuted: state.isMuted,
      isDeafened: state.isDeafened,
      isSpeaking: false
    }));
  }

  renderChannelsList();
  renderVoiceLounge();
}

// --- Event Listeners Setup ---
function setupEventListeners() {
  // Login Form
  dom.loginForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const val = dom.usernameInput.value.trim();
    if (val) login(val);
  });

  // Chat Input
  dom.chatSendBtn.addEventListener('click', sendCurrentChatMessage);
  dom.chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      if (e.isComposing) return;
      e.preventDefault();
      sendCurrentChatMessage();
    } else if (e.key === 'Escape' && state.replyingTo) {
      e.preventDefault();
      cancelReplyingToMessage();
    }
  });

  // Cancel Reply Button
  if (dom.btnCancelReply) {
    dom.btnCancelReply.addEventListener('click', cancelReplyingToMessage);
  }

  // Screen Share Buttons
  dom.btnScreenshareVoice.addEventListener('click', toggleScreenShare);
  dom.loungeBtnScreenshare.addEventListener('click', toggleScreenShare);
  if (dom.loungeBtnScreenshareSettings) {
    dom.loungeBtnScreenshareSettings.addEventListener('click', () => openScreenShareModal());
  }
  dom.btnVideoStop.addEventListener('click', stopScreenShare);

  if (dom.btnVideoQuality) {
    dom.btnVideoQuality.addEventListener('click', () => openScreenShareModal());
  }
  if (dom.screenshareQualityTag) {
    dom.screenshareQualityTag.addEventListener('click', () => openScreenShareModal());
  }

  // Screen Share Modal Events
  if (dom.btnCloseScreenshareX) {
    dom.btnCloseScreenshareX.addEventListener('click', closeScreenShareModal);
  }
  if (dom.btnCancelScreenshare) {
    dom.btnCancelScreenshare.addEventListener('click', closeScreenShareModal);
  }
  if (dom.btnStopFromModal) {
    dom.btnStopFromModal.addEventListener('click', () => {
      stopScreenShare();
      closeScreenShareModal();
    });
  }
  if (dom.btnConfirmScreenshare) {
    dom.btnConfirmScreenshare.addEventListener('click', startScreenShareWithSettings);
  }
  if (dom.tabBtnScreenshareWindows) {
    dom.tabBtnScreenshareWindows.addEventListener('click', () => selectScreenShareTab('windows'));
  }
  if (dom.tabBtnScreenshareScreens) {
    dom.tabBtnScreenshareScreens.addEventListener('click', () => selectScreenShareTab('screens'));
  }

  // Resolution pills
  if (dom.pillsResolution) {
    dom.pillsResolution.querySelectorAll('.quality-pill').forEach(pill => {
      pill.addEventListener('click', () => {
        const res = pill.dataset.resolution;
        state.screenshareSettings.resolution = res;
        updateScreenShareQualityUI();
        if (state.isSharingScreen) {
          applyScreenShareQuality(res, state.screenshareSettings.fps);
        }
      });
    });
  }

  // FPS pills
  if (dom.pillsFps) {
    dom.pillsFps.querySelectorAll('.quality-pill').forEach(pill => {
      pill.addEventListener('click', () => {
        const fps = parseInt(pill.dataset.fps, 10);
        state.screenshareSettings.fps = fps;
        updateScreenShareQualityUI();
        if (state.isSharingScreen) {
          applyScreenShareQuality(state.screenshareSettings.resolution, fps);
        }
      });
    });
  }

  // Audio checkbox
  if (dom.screenshareAudioCheckbox) {
    dom.screenshareAudioCheckbox.addEventListener('change', (e) => {
      state.screenshareSettings.shareAudio = !!e.target.checked;
    });
  }

  dom.btnVideoFullscreen.addEventListener('click', () => {
    if (dom.screenshareVideo.requestFullscreen) {
      dom.screenshareVideo.requestFullscreen();
    }
  });

  // Audio Controls
  dom.btnToggleMute.addEventListener('click', toggleMute);
  dom.btnToggleDeafen.addEventListener('click', toggleDeafen);
  dom.btnDisconnectVoice.addEventListener('click', disconnectVoice);
  dom.btnLogout.addEventListener('click', logout);

  // User Status Popover & Status Selector Controls
  if (dom.userProfileTrigger) {
    dom.userProfileTrigger.addEventListener('click', toggleUserStatusPopover);
  }

  document.querySelectorAll('.status-popover-item').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const status = btn.getAttribute('data-status');
      setUserStatus(status, false);
      closeUserStatusPopover();
    });
  });

  if (dom.popoverBtnSettings) {
    dom.popoverBtnSettings.addEventListener('click', (e) => {
      e.stopPropagation();
      closeUserStatusPopover();
      if (dom.btnSettings) dom.btnSettings.click();
    });
  }

  document.querySelectorAll('.settings-status-card').forEach(card => {
    card.addEventListener('click', (e) => {
      e.preventDefault();
      const status = card.getAttribute('data-status');
      setUserStatus(status, false);
    });
  });

  document.addEventListener('click', (e) => {
    if (dom.userStatusPopover && !dom.userStatusPopover.classList.contains('hidden')) {
      if (!dom.userStatusPopover.contains(e.target) && !dom.userProfileTrigger.contains(e.target)) {
        closeUserStatusPopover();
      }
    }
  });

  // Auto-Idle Inactivity Detector (5 minutes)
  let lastUserActivityTime = Date.now();
  const IDLE_TIMEOUT_MS = 5 * 60 * 1000;

  function resetUserActivity() {
    lastUserActivityTime = Date.now();
    // If auto-set to idle while manual preference is online, return to online
    if (state.currentUser.status === 'idle' && state.userStatusPreference === 'online') {
      setUserStatus('online', true);
    }
  }

  window.addEventListener('mousemove', resetUserActivity, { passive: true });
  window.addEventListener('keydown', resetUserActivity, { passive: true });
  window.addEventListener('mousedown', resetUserActivity, { passive: true });
  window.addEventListener('touchstart', resetUserActivity, { passive: true });

  setInterval(() => {
    if (!state.currentUser.username) return;
    if (state.userStatusPreference === 'online' && state.currentUser.status === 'online') {
      if (Date.now() - lastUserActivityTime >= IDLE_TIMEOUT_MS) {
        setUserStatus('idle', true);
      }
    }
  }, 15000);

  // Lounge Floating Dock Controls & Voice Stage Actions
  if (dom.loungeDockMic) dom.loungeDockMic.addEventListener('click', toggleMute);
  if (dom.loungeDockDeafen) dom.loungeDockDeafen.addEventListener('click', toggleDeafen);
  if (dom.loungeDockScreenshare) dom.loungeDockScreenshare.addEventListener('click', toggleScreenShare);
  if (dom.loungeDockCamera) dom.loungeDockCamera.addEventListener('click', toggleLoungeCamera);
  if (dom.loungeDockMeterBtn) dom.loungeDockMeterBtn.addEventListener('click', toggleLoungeMeterPopover);
  if (dom.btnCloseMeterPopover) dom.btnCloseMeterPopover.addEventListener('click', toggleLoungeMeterPopover);
  if (dom.loungeDockFullscreen) dom.loungeDockFullscreen.addEventListener('click', toggleLoungeFullscreen);
  if (dom.loungeBtnFullscreen) dom.loungeBtnFullscreen.addEventListener('click', toggleLoungeFullscreen);
  if (dom.loungeDockDisconnect) dom.loungeDockDisconnect.addEventListener('click', disconnectVoice);
  if (dom.loungeBtnEmptyJoin) dom.loungeBtnEmptyJoin.addEventListener('click', () => {
    if (state.activeChannel) joinVoiceChannel(state.activeChannel);
  });

  if (dom.meterSlider) {
    dom.meterSlider.addEventListener('input', (e) => {
      const val = parseInt(e.target.value, 10);
      if (window.audioEngine) {
        window.audioEngine.speakingThreshold = val;
      }
      if (dom.meterThresholdMarker) {
        dom.meterThresholdMarker.style.left = val + '%';
      }
    });
  }

  // Keyboard shortcut: ESC to exit call cinema mode or close modals
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (dom.screenshareModal && !dom.screenshareModal.classList.contains('hidden')) {
        closeScreenShareModal();
      } else if (state.isLoungeFullscreen) {
        toggleLoungeFullscreen();
      }
    }
  });

  // Toggle Online Members Sidebar
  if (dom.btnToggleMembersSidebar) {
    dom.btnToggleMembersSidebar.addEventListener('click', () => {
      if (!dom.membersSidebar) return;
      const isHidden = dom.membersSidebar.classList.toggle('hidden');
      dom.btnToggleMembersSidebar.classList.toggle('active', !isHidden);
    });
  }

  // Refresh / Update App Button
  if (dom.btnRefreshApp) {
    dom.btnRefreshApp.addEventListener('click', () => {
      dom.btnRefreshApp.classList.add('refreshing');
      showToast('Buscando atualizações e recarregando...', 'info', 1500);

      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.getRegistrations().then(registrations => {
          registrations.forEach(r => r.update());
        }).catch(() => {});
      }

      setTimeout(() => {
        window.location.reload();
      }, 350);
    });
  }

  // --- Add Server Modal (Tabs & Actions) ---
  function switchServerModalTab(tab) {
    if (tab === 'create') {
      if (dom.tabBtnCreateServer) dom.tabBtnCreateServer.classList.add('active');
      if (dom.tabBtnJoinServer) dom.tabBtnJoinServer.classList.remove('active');
      if (dom.viewCreateServer) dom.viewCreateServer.classList.remove('hidden');
      if (dom.viewJoinServer) dom.viewJoinServer.classList.add('hidden');
      if (dom.serverModalTitle) dom.serverModalTitle.textContent = 'Criar seu Servidor';
      if (dom.newServerNameInput) dom.newServerNameInput.focus();
    } else {
      if (dom.tabBtnCreateServer) dom.tabBtnCreateServer.classList.remove('active');
      if (dom.tabBtnJoinServer) dom.tabBtnJoinServer.classList.add('active');
      if (dom.viewCreateServer) dom.viewCreateServer.classList.add('hidden');
      if (dom.viewJoinServer) dom.viewJoinServer.classList.remove('hidden');
      if (dom.serverModalTitle) dom.serverModalTitle.textContent = 'Entrar em um Servidor';
      if (dom.joinServerInput) dom.joinServerInput.focus();
    }
  }

  if (dom.tabBtnCreateServer) dom.tabBtnCreateServer.addEventListener('click', () => switchServerModalTab('create'));
  if (dom.tabBtnJoinServer) dom.tabBtnJoinServer.addEventListener('click', () => switchServerModalTab('join'));
  if (dom.btnCancelJoinServer) dom.btnCancelJoinServer.addEventListener('click', () => dom.createServerModal.classList.add('hidden'));

  dom.btnAddServer.addEventListener('click', () => {
    switchServerModalTab('create');
    state.tempServerIcon = '';
    dom.newServerNameInput.value = '';
    dom.serverIconUrl.value = '';
    dom.serverIconPreview.innerHTML = '<svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>';
    if (dom.joinServerInput) dom.joinServerInput.value = '';
    dom.createServerModal.classList.remove('hidden');
    dom.newServerNameInput.focus();
  });

  dom.btnCancelCreateServer.addEventListener('click', () => dom.createServerModal.classList.add('hidden'));
  dom.btnCloseCreateServerX.addEventListener('click', () => dom.createServerModal.classList.add('hidden'));

  // Join Server Form Submission
  if (dom.joinServerForm) {
    dom.joinServerForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const rawVal = dom.joinServerInput.value.trim();
      if (!rawVal) return;

      let inviteCode = rawVal;
      try {
        if (rawVal.includes('http://') || rawVal.includes('https://')) {
          const parsed = new URL(rawVal);
          inviteCode = parsed.searchParams.get('invite') || parsed.searchParams.get('server') || rawVal;
        }
      } catch (err) {}

      inviteCode = inviteCode.replace(/^[?&]invite=/, '').trim();
      if (!inviteCode) return;

      const existing = state.servers.find(s => s.inviteCode === inviteCode || s.id === inviteCode || s.name.toLowerCase() === inviteCode.toLowerCase());
      if (existing) {
        dom.createServerModal.classList.add('hidden');
        selectServer(existing.id);
        showToast('Você já está no servidor "' + existing.name + '"!', 'info');
        dom.joinServerInput.value = '';
        return;
      }

      dom.createServerModal.classList.add('hidden');
      showToast('Conectando ao servidor...', 'info');

      if (state.mqtt) {
        state.mqtt.publish(TOPICS.discovery, JSON.stringify({
          action: 'request_server',
          inviteCode: inviteCode,
          requesterId: state.currentUser.id
        }));
      }

      setTimeout(() => {
        const foundAfter = state.servers.find(s => s.inviteCode === inviteCode || s.id === inviteCode);
        if (!foundAfter) {
          const cleanId = 'srv-' + inviteCode.toLowerCase().replace(/[^a-z0-9_-]/g, '');
          const newJoinedServer = {
            id: cleanId,
            name: 'Servidor ' + inviteCode,
            icon: '',
            inviteCode: inviteCode,
            channels: [
              { id: 'c-geral-' + cleanId, name: 'geral', type: 'text', topic: 'Canal principal' },
              { id: 'v-geral-' + cleanId, name: 'Sala Geral', type: 'voice', userLimit: 15 }
            ]
          };
          state.servers.push(newJoinedServer);
          saveStoredServers();
          renderServerRail();
          selectServer(newJoinedServer.id);
          publishPresence('join');
          showToast('Entrou no servidor "' + newJoinedServer.name + '" com sucesso!', 'success');
        }
      }, 1000);

      dom.joinServerInput.value = '';
    });
  }

  // Server icon file picker
  dom.serverIconFile.addEventListener('change', (e) => {
    const file = e.target.files[0];
    if (file) {
      const reader = new FileReader();
      reader.onload = (evt) => {
        state.tempServerIcon = evt.target.result;
        dom.serverIconPreview.innerHTML = '<img src="' + state.tempServerIcon + '" alt="Icon Preview">';
        dom.serverIconUrl.value = '';
      };
      reader.readAsDataURL(file);
    }
  });

  dom.serverIconUrl.addEventListener('input', () => {
    const url = dom.serverIconUrl.value.trim();
    if (url) {
      state.tempServerIcon = url;
      dom.serverIconPreview.innerHTML = '<img src="' + escapeHtml(url) + '" alt="Icon Preview">';
    }
  });

  dom.createServerForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const name = dom.newServerNameInput.value.trim();
    if (!name) return;

    const serverId = 'srv-' + Date.now();
    const inviteCode = 'inv-' + Math.random().toString(36).substring(2, 8);

    const newServer = {
      id: serverId,
      name: name,
      icon: state.tempServerIcon || '',
      inviteCode: inviteCode,
      isOwner: true,
      channels: [
        { id: 'c-geral-' + serverId, name: 'geral', type: 'text', topic: 'Canal de texto principal' },
        { id: 'c-avisos-' + serverId, name: 'avisos', type: 'text', topic: 'Avisos e comunicados' },
        { id: 'v-geral-' + serverId, name: 'Sala Geral', type: 'voice', userLimit: 15 },
        { id: 'v-batepapo-' + serverId, name: 'Bate-Papo', type: 'voice', userLimit: 10 }
      ]
    };

    state.servers.push(newServer);
    saveStoredServers();
    renderServerRail();
    selectServer(serverId);

    dom.createServerModal.classList.add('hidden');
    showToast('Servidor "' + name + '" criado com sucesso!', 'success');

    // Announce to network discovery
    if (state.mqtt) {
      state.mqtt.publish(TOPICS.discovery, JSON.stringify({
        action: 'announce_server',
        server: newServer
      }));
    }
  });

  // --- Invite Friends Modal ---
  function openInviteFriendsModal() {
    const srv = getActiveServer();
    if (!srv) return;

    const origin = window.location.origin;
    const pathname = window.location.pathname;
    const inviteLink = origin + pathname + '?invite=' + srv.inviteCode;

    dom.inviteLinkInput.value = inviteLink;
    dom.inviteModalTitle.textContent = 'Convidar amigos para ' + srv.name;
    dom.inviteModal.classList.remove('hidden');
  }

  if (dom.btnOpenInvite) {
    dom.btnOpenInvite.addEventListener('click', openInviteFriendsModal);
  }

  dom.btnCopyInvite.addEventListener('click', () => {
    dom.inviteLinkInput.select();
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(dom.inviteLinkInput.value).then(() => {
        dom.btnCopyInvite.textContent = 'Copiado!';
        showToast('Link de convite copiado para a área de transferência!', 'success');
        setTimeout(() => { dom.btnCopyInvite.textContent = 'Copiar'; }, 2000);
      });
    } else {
      document.execCommand('copy');
      dom.btnCopyInvite.textContent = 'Copiado!';
      showToast('Link de convite copiado!', 'success');
      setTimeout(() => { dom.btnCopyInvite.textContent = 'Copiar'; }, 2000);
    }
  });

  dom.btnCancelInvite.addEventListener('click', () => dom.inviteModal.classList.add('hidden'));
  dom.btnCloseInviteX.addEventListener('click', () => dom.inviteModal.classList.add('hidden'));

  // --- Server Rail Collapse & Server Hub Handlers ---
  if (dom.btnCollapseServerRail) {
    dom.btnCollapseServerRail.addEventListener('click', (e) => {
      e.stopPropagation();
      collapseServerRail(true);
    });
  }

  if (dom.btnExpandServerRail) {
    dom.btnExpandServerRail.addEventListener('click', (e) => {
      e.stopPropagation();
      collapseServerRail(false);
    });
  }

  if (dom.btnMaximizeServers) {
    dom.btnMaximizeServers.addEventListener('click', (e) => {
      e.stopPropagation();
      openServerHub();
    });
  }

  if (dom.btnCloseServerHub) {
    dom.btnCloseServerHub.addEventListener('click', closeServerHub);
  }

  if (dom.btnHubCreateServer) {
    dom.btnHubCreateServer.addEventListener('click', () => {
      closeServerHub();
      if (dom.btnAddServer) dom.btnAddServer.click();
    });
  }

  if (dom.serverHubSearchInput) {
    dom.serverHubSearchInput.addEventListener('input', () => {
      const q = dom.serverHubSearchInput.value;
      if (dom.btnClearHubSearch) {
        dom.btnClearHubSearch.classList.toggle('hidden', !q);
      }
      renderServerHub(q);
    });
  }

  if (dom.btnClearHubSearch) {
    dom.btnClearHubSearch.addEventListener('click', () => {
      dom.serverHubSearchInput.value = '';
      dom.btnClearHubSearch.classList.add('hidden');
      renderServerHub();
      dom.serverHubSearchInput.focus();
    });
  }

  // Keyboard shortcut listener for Server Hub (Escape) and Rail Collapse (Alt + S)
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (dom.serverHubModal && !dom.serverHubModal.classList.contains('hidden')) {
        closeServerHub();
      }
    } else if (e.altKey && (e.key === 's' || e.key === 'S')) {
      e.preventDefault();
      toggleServerRailCollapse();
    }
  });

  // --- Settings Modal Handlers (Username & Avatar & Themes) ---
  dom.btnSettings.addEventListener('click', () => {
    const current = state.currentUser.username || '';
    state.tempUserAvatar = state.currentUser.avatar || '';
    dom.settingsUsernameInput.value = current;
    dom.settingsAvatarUrl.value = (state.tempUserAvatar.startsWith('http') ? state.tempUserAvatar : '');
    dom.settingsPreviewName.textContent = current || 'Usuário';

    updateSettingsAvatarPreview();
    switchSettingsTab('profile');
    dom.settingsModal.classList.remove('hidden');
    dom.settingsUsernameInput.focus();
  });

  // Settings Modal Tabs (Meu Perfil vs Aparência / Temas)
  if (dom.tabBtnSettingsProfile) {
    dom.tabBtnSettingsProfile.addEventListener('click', () => switchSettingsTab('profile'));
  }
  if (dom.tabBtnSettingsTheme) {
    dom.tabBtnSettingsTheme.addEventListener('click', () => switchSettingsTab('theme'));
  }
  if (dom.btnCloseThemeTab) {
    dom.btnCloseThemeTab.addEventListener('click', () => dom.settingsModal.classList.add('hidden'));
  }

  // Theme Cards Click Handlers
  document.querySelectorAll('.theme-card').forEach(card => {
    card.addEventListener('click', () => {
      const themeVal = card.getAttribute('data-theme-value');
      if (themeVal) applyTheme(themeVal, true);
    });
  });

  function updateSettingsAvatarPreview() {
    const name = dom.settingsUsernameInput.value.trim() || 'Usuário';
    if (state.tempUserAvatar) {
      dom.settingsPreviewAvatar.innerHTML = '<img src="' + state.tempUserAvatar + '" alt="Avatar">';
    } else {
      dom.settingsPreviewAvatar.textContent = name.substring(0, 2).toUpperCase();
    }
  }

  dom.settingsUsernameInput.addEventListener('input', () => {
    const val = dom.settingsUsernameInput.value.trim();
    dom.settingsPreviewName.textContent = val || 'Usuário';
    updateSettingsAvatarPreview();
  });

  dom.settingsAvatarFile.addEventListener('change', (e) => {
    const file = e.target.files[0];
    if (file) {
      const reader = new FileReader();
      reader.onload = (evt) => {
        state.tempUserAvatar = evt.target.result;
        dom.settingsAvatarUrl.value = '';
        updateSettingsAvatarPreview();
      };
      reader.readAsDataURL(file);
    }
  });

  dom.settingsAvatarUrl.addEventListener('input', () => {
    const url = dom.settingsAvatarUrl.value.trim();
    state.tempUserAvatar = url;
    updateSettingsAvatarPreview();
  });

  dom.btnRemoveAvatar.addEventListener('click', () => {
    state.tempUserAvatar = '';
    dom.settingsAvatarUrl.value = '';
    dom.settingsAvatarFile.value = '';
    updateSettingsAvatarPreview();
  });

  dom.btnCancelSettings.addEventListener('click', () => dom.settingsModal.classList.add('hidden'));
  dom.btnCloseSettingsX.addEventListener('click', () => dom.settingsModal.classList.add('hidden'));

  dom.settingsForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const newName = dom.settingsUsernameInput.value.trim();
    if (!newName) return;

    const oldName = state.currentUser.username;
    state.currentUser.username = newName;
    state.currentUser.avatar = state.tempUserAvatar || '';

    if (state.knownUsers) {
      state.knownUsers[state.currentUser.id] = {
        id: state.currentUser.id,
        username: newName,
        avatar: state.currentUser.avatar || '',
        updatedAt: Date.now()
      };
      saveStoredKnownUsers();
    }

    localStorage.setItem('projetous_username', newName);
    if (state.currentUser.avatar) {
      localStorage.setItem('projetous_avatar', state.currentUser.avatar);
    } else {
      localStorage.removeItem('projetous_avatar');
    }

    updateUserProfileUI();
    updateUserInStoredMessages(state.currentUser.id, newName, state.currentUser.avatar, oldName);
    renderChatFeed();
    publishPresence('join');

    if (state.mqtt) {
      const profilePayload = JSON.stringify({
        action: 'update_user_profile',
        userId: state.currentUser.id,
        username: newName,
        avatar: state.currentUser.avatar || ''
      });
      // Broadcast to global presence so all peers regardless of server receive the updated name
      state.mqtt.publish(TOPICS.globalPresence, profilePayload, { qos: 1 });
      // Broadcast to all servers
      state.servers.forEach(srv => {
        state.mqtt.publish(TOPICS.chat(srv.id), profilePayload, { qos: 1 });
      });
    }

    renderChannelsList();
    renderVoiceLounge();

    dom.settingsModal.classList.add('hidden');
    showToast('Perfil atualizado com sucesso!', 'success');
  });

  // --- Move Modal Handlers ---
  dom.btnCancelMove.addEventListener('click', () => dom.moveModal.classList.add('hidden'));
  dom.btnCloseMoveX.addEventListener('click', () => dom.moveModal.classList.add('hidden'));

  // --- Category Collapsible Handlers (HUD Style) ---
  const catHeaderText = dom.categoryHeaderText || document.getElementById('category-header-text');
  const catHeaderVoice = dom.categoryHeaderVoice || document.getElementById('category-header-voice');

  if (catHeaderText) {
    catHeaderText.addEventListener('click', (e) => {
      if (e.target.closest('#btn-add-text-channel')) return;
      toggleCategoryCollapse('text');
    });
  }

  if (catHeaderVoice) {
    catHeaderVoice.addEventListener('click', (e) => {
      if (e.target.closest('#btn-add-voice-channel')) return;
      toggleCategoryCollapse('voice');
    });
  }

  // --- Create Channel Modal Handlers ---
  dom.btnAddTextChannel.addEventListener('click', (e) => {
    e.stopPropagation();
    openCreateChannelModal('text');
  });
  dom.btnAddVoiceChannel.addEventListener('click', (e) => {
    e.stopPropagation();
    openCreateChannelModal('voice');
  });
  dom.btnCancelChannel.addEventListener('click', () => dom.channelModal.classList.add('hidden'));

  dom.optionTextChan.addEventListener('click', () => {
    dom.optionTextChan.classList.add('active');
    dom.optionVoiceChan.classList.remove('active');
    dom.optionTextChan.querySelector('input').checked = true;
  });

  dom.optionVoiceChan.addEventListener('click', () => {
    dom.optionVoiceChan.classList.add('active');
    dom.optionTextChan.classList.remove('active');
    dom.optionVoiceChan.querySelector('input').checked = true;
  });

  dom.channelForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const name = dom.channelNameInput.value.trim();
    const type = document.querySelector('input[name="channel-type"]:checked').value;
    if (name) {
      const srv = getActiveServer();
      const cleanName = name.toLowerCase().replace(/\s+/g, '-');
      const id = (type === 'voice' ? 'v-' : 'c-') + Date.now();
      const newChan = {
        id,
        name: cleanName,
        type,
        topic: type === 'voice' ? 'Sala de voz do servidor ' + srv.name : ('Canal #' + cleanName)
      };

      srv.channels.push(newChan);
      saveStoredServers();

      // Ensure the category is expanded so user sees the created channel
      if (type === 'voice' && categoryCollapseState.voice) {
        categoryCollapseState.voice = false;
        saveCategoryCollapseState();
        applyCategoryCollapseState();
      } else if (type === 'text' && categoryCollapseState.text) {
        categoryCollapseState.text = false;
        saveCategoryCollapseState();
        applyCategoryCollapseState();
      }

      renderChannelsList();
      selectChannel(id);

      // Broadcast new channel to current server peers
      if (state.mqtt) {
        state.mqtt.publish(TOPICS.channels(srv.id), JSON.stringify({
          action: 'create',
          channel: newChan,
          creator: state.currentUser.username
        }));
      }

      dom.channelModal.classList.add('hidden');
      dom.channelNameInput.value = '';
      showToast('Canal criado no servidor ' + srv.name + '!', 'success');
    }
  });

  // --- Server Header Dropdown Menu (HUD Style) ---
  function toggleServerDropdown(forceClose = false) {
    if (!dom.serverDropdownMenu) return;
    if (forceClose) {
      dom.serverDropdownMenu.classList.add('hidden');
      if (dom.btnServerMenu) dom.btnServerMenu.classList.remove('open');
      return;
    }
    const isHidden = dom.serverDropdownMenu.classList.toggle('hidden');
    if (dom.btnServerMenu) {
      dom.btnServerMenu.classList.toggle('open', !isHidden);
    }
  }

  if (dom.btnServerMenu) {
    dom.btnServerMenu.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleServerDropdown();
    });
  }

  if (dom.serverHeader) {
    dom.serverHeader.addEventListener('click', () => {
      toggleServerDropdown();
    });
  }

  document.addEventListener('click', (e) => {
    if (dom.serverDropdownMenu && !dom.serverDropdownMenu.classList.contains('hidden')) {
      if (dom.serverHeader && !dom.serverHeader.contains(e.target) && !dom.serverDropdownMenu.contains(e.target)) {
        toggleServerDropdown(true);
      }
    }
  });

  // Dropdown Option 1: Convidar Usuário
  if (dom.menuItemInvite) {
    dom.menuItemInvite.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleServerDropdown(true);
      openInviteFriendsModal();
    });
  }

  // Dropdown Option 2: Configuração do Servidor
  if (dom.menuItemSettings) {
    dom.menuItemSettings.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleServerDropdown(true);
      openServerSettingsModal();
    });
  }

  // Dropdown Option 3: Sair do Servidor
  if (dom.menuItemLeave) {
    dom.menuItemLeave.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleServerDropdown(true);
      handleLeaveCurrentServer();
    });
  }

  function handleLeaveCurrentServer() {
    const srv = getActiveServer();
    if (!srv || srv.id === DEFAULT_SERVER_ID) {
      showToast('O servidor padrão ProjetoUS não pode ser excluído.', 'warning');
      return;
    }

    if (!confirm('Tem certeza que deseja sair/excluir o servidor "' + srv.name + '"?')) {
      return;
    }

    state.servers = state.servers.filter(s => s.id !== srv.id);
    saveStoredServers();
    if (dom.serverSettingsModal) dom.serverSettingsModal.classList.add('hidden');
    selectServer(DEFAULT_SERVER_ID);
    showToast('Você saiu do servidor "' + srv.name + '".', 'info');
  }

  // --- Server Settings Modal Handlers ---
  if (dom.btnServerSettings) {
    dom.btnServerSettings.addEventListener('click', openServerSettingsModal);
  }

  function openServerSettingsModal() {
    const srv = getActiveServer();
    if (!srv) return;

    state.tempEditServerIcon = srv.icon || '';
    dom.editServerNameInput.value = srv.name;
    dom.editServerIconUrl.value = (state.tempEditServerIcon.startsWith('http') ? state.tempEditServerIcon : '');
    
    const origin = window.location.origin;
    const pathname = window.location.pathname;
    dom.editServerInviteInput.value = origin + pathname + '?invite=' + srv.inviteCode;

    updateEditServerIconPreview();

    // Prevent deleting default server
    if (srv.id === DEFAULT_SERVER_ID) {
      dom.btnDeleteServer.disabled = true;
      dom.btnDeleteServer.title = 'O servidor padrão não pode ser excluído.';
      dom.btnDeleteServer.textContent = 'Servidor Padrão';
    } else {
      dom.btnDeleteServer.disabled = false;
      dom.btnDeleteServer.title = 'Excluir servidor';
      dom.btnDeleteServer.textContent = 'Excluir Servidor';
    }

    dom.serverSettingsModal.classList.remove('hidden');
    dom.editServerNameInput.focus();
  }

  function updateEditServerIconPreview() {
    const srv = getActiveServer();
    const initials = ((dom.editServerNameInput.value.trim() || (srv ? srv.name : '')) || 'S').substring(0, 2).toUpperCase();
    if (state.tempEditServerIcon) {
      dom.editServerIconPreview.innerHTML = '<img src="' + escapeHtml(state.tempEditServerIcon) + '" alt="Icon Preview">';
    } else {
      dom.editServerIconPreview.textContent = initials;
    }
  }

  if (dom.editServerNameInput) {
    dom.editServerNameInput.addEventListener('input', updateEditServerIconPreview);
  }

  if (dom.editServerIconFile) {
    dom.editServerIconFile.addEventListener('change', (e) => {
      const file = e.target.files[0];
      if (file) {
        const reader = new FileReader();
        reader.onload = (evt) => {
          state.tempEditServerIcon = evt.target.result;
          dom.editServerIconUrl.value = '';
          updateEditServerIconPreview();
        };
        reader.readAsDataURL(file);
      }
    });
  }

  if (dom.editServerIconUrl) {
    dom.editServerIconUrl.addEventListener('input', () => {
      const url = dom.editServerIconUrl.value.trim();
      state.tempEditServerIcon = url;
      updateEditServerIconPreview();
    });
  }

  if (dom.btnRemoveServerIcon) {
    dom.btnRemoveServerIcon.addEventListener('click', () => {
      state.tempEditServerIcon = '';
      dom.editServerIconUrl.value = '';
      dom.editServerIconFile.value = '';
      updateEditServerIconPreview();
    });
  }

  if (dom.btnCopyEditInvite) {
    dom.btnCopyEditInvite.addEventListener('click', () => {
      dom.editServerInviteInput.select();
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(dom.editServerInviteInput.value).then(() => {
          dom.btnCopyEditInvite.textContent = 'Copiado!';
          showToast('Link de convite copiado!', 'success');
          setTimeout(() => { dom.btnCopyEditInvite.textContent = 'Copiar'; }, 2000);
        });
      } else {
        document.execCommand('copy');
        dom.btnCopyEditInvite.textContent = 'Copiado!';
        showToast('Link de convite copiado!', 'success');
        setTimeout(() => { dom.btnCopyEditInvite.textContent = 'Copiar'; }, 2000);
      }
    });
  }

  if (dom.btnCancelServerSettings) {
    dom.btnCancelServerSettings.addEventListener('click', () => dom.serverSettingsModal.classList.add('hidden'));
  }
  if (dom.btnCloseServerSettingsX) {
    dom.btnCloseServerSettingsX.addEventListener('click', () => dom.serverSettingsModal.classList.add('hidden'));
  }

  if (dom.serverSettingsForm) {
    dom.serverSettingsForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const srv = getActiveServer();
      if (!srv) return;

      const newName = dom.editServerNameInput.value.trim();
      if (!newName) return;

      srv.name = newName;
      srv.icon = state.tempEditServerIcon || '';

      saveStoredServers();
      renderServerRail();

      dom.currentServerName.textContent = srv.name;
      if (srv.icon) {
        dom.serverHeaderAvatar.innerHTML = '<img src="' + escapeHtml(srv.icon) + '" alt="' + escapeHtml(srv.name) + '">';
      } else {
        const initials = srv.name.split(' ').map(w => w[0]).join('').substring(0, 2).toUpperCase() || 'S';
        dom.serverHeaderAvatar.textContent = initials;
      }

      if (state.mqtt) {
        state.mqtt.publish(TOPICS.discovery, JSON.stringify({
          action: 'announce_server',
          server: srv
        }));
      }

      dom.serverSettingsModal.classList.add('hidden');
      showToast('Configurações do servidor "' + srv.name + '" salvas com sucesso!', 'success');
    });
  }

  if (dom.btnDeleteServer) {
    dom.btnDeleteServer.addEventListener('click', handleLeaveCurrentServer);
  }

  // --- GIF Picker Modal Handlers ---
  function openGifPickerModal() {
    state.activeGifCategory = 'all';
    if (dom.gifSearchInput) dom.gifSearchInput.value = '';
    if (dom.btnClearGifSearch) dom.btnClearGifSearch.classList.add('hidden');
    renderGifCategories();
    renderGifGrid();
    dom.gifPickerModal.classList.remove('hidden');
    if (dom.gifSearchInput) dom.gifSearchInput.focus();
  }

  function renderGifCategories() {
    if (!dom.gifCategoryChips) return;
    dom.gifCategoryChips.innerHTML = '';

    GIF_CATEGORIES.forEach(cat => {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'gif-category-chip' + (state.activeGifCategory === cat.id ? ' active' : '');
      chip.textContent = cat.name;
      chip.addEventListener('click', () => {
        state.activeGifCategory = cat.id;
        renderGifCategories();
        renderGifGrid();
      });
      dom.gifCategoryChips.appendChild(chip);
    });
  }

  function renderGifGrid() {
    if (!dom.gifGrid) return;
    dom.gifGrid.innerHTML = '';

    const query = dom.gifSearchInput ? dom.gifSearchInput.value.trim().toLowerCase() : '';
    let filtered = GIF_DATABASE;

    if (query) {
      filtered = filtered.filter(g => g.title.toLowerCase().includes(query) || g.category.toLowerCase().includes(query));
    } else if (state.activeGifCategory !== 'all') {
      filtered = filtered.filter(g => g.category === state.activeGifCategory);
    }

    if (filtered.length === 0) {
      dom.gifGrid.innerHTML = '<div style="grid-column: 1/-1; text-align: center; color: var(--text-muted); padding: 30px 0; font-size: 13px;">Nenhum GIF encontrado. Tente buscar outro termo ou cole o link direto abaixo!</div>';
      return;
    }

    filtered.forEach(gif => {
      const card = document.createElement('div');
      card.className = 'gif-card';
      card.title = gif.title;
      card.innerHTML = 
        '<img src="' + escapeHtml(gif.url) + '" alt="' + escapeHtml(gif.title) + '" loading="lazy">' +
        '<div class="gif-card-overlay">' + escapeHtml(gif.title) + '</div>';

      card.addEventListener('click', () => {
        sendGifMessage(gif.url);
      });

      dom.gifGrid.appendChild(card);
    });
  }

  if (dom.chatBtnGif) {
    dom.chatBtnGif.addEventListener('click', openGifPickerModal);
  }

  if (dom.btnCloseGifX) {
    dom.btnCloseGifX.addEventListener('click', () => dom.gifPickerModal.classList.add('hidden'));
  }

  if (dom.gifSearchInput) {
    dom.gifSearchInput.addEventListener('input', () => {
      const val = dom.gifSearchInput.value.trim();
      if (dom.btnClearGifSearch) {
        dom.btnClearGifSearch.classList.toggle('hidden', val.length === 0);
      }
      renderGifGrid();
    });
  }

  if (dom.btnClearGifSearch) {
    dom.btnClearGifSearch.addEventListener('click', () => {
      dom.gifSearchInput.value = '';
      dom.btnClearGifSearch.classList.add('hidden');
      renderGifGrid();
      dom.gifSearchInput.focus();
    });
  }

  if (dom.btnSendCustomGif) {
    dom.btnSendCustomGif.addEventListener('click', () => {
      const url = dom.gifCustomUrlInput ? dom.gifCustomUrlInput.value.trim() : '';
      if (!url) {
        showToast('Insira um link de GIF válido.', 'warning');
        return;
      }
      sendGifMessage(url);
    });
  }

  if (dom.gifCustomUrlInput) {
    dom.gifCustomUrlInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        if (dom.btnSendCustomGif) dom.btnSendCustomGif.click();
      }
    });
  }

  // --- Emoji Picker Handlers ---
  const EMOJI_CATEGORIES = [
    {
      name: 'Populares & Carinhas',
      emojis: ['😀', '😂', '🤣', '😅', '😊', '😍', '🥰', '😎', '🥳', '🤔', '😴', '😭', '💀', '🤡', '🤖', '👻', '🫡', '🤫', '🤯', '🥺', '😏', '😌', '🙃', '😇', '😋', '😜', '🤪', '🤩', '😤', '😡', '😱', '🥵', '🥶']
    },
    {
      name: 'Gestos & Mãos',
      emojis: ['👍', '👎', '👏', '🙌', '🤝', '✌️', '🤞', '👊', '🤛', '🤜', '🤙', '🫰', '👋', '🙏', '💪', '💅', '👀', '🔥', '💯', '✨', '⭐', '❤️', '💔', '💖', '🎉', '🎈', '🏆', '🚀', '⚡', '💥']
    },
    {
      name: 'Jogos, Comidas & Objetos',
      emojis: ['🎮', '🕹️', '🎲', '🎯', '🍕', '🍔', '🍟', '🍿', '🍻', '🍺', '☕', '🥤', '🍩', '🍪', '🍫', '🎧', '🎤', '🎬', '👾', '💎', '💰', '💸', '👑', '🗿', '🐱', '🐶', '🐸', '⚔️', '🛡️', '📦']
    }
  ];

  function renderEmojiPicker(query = '') {
    if (!dom.emojiPickerScroll) return;
    dom.emojiPickerScroll.innerHTML = '';
    const q = query.trim().toLowerCase();

    EMOJI_CATEGORIES.forEach(cat => {
      let list = cat.emojis;
      if (q) {
        list = list.filter(em => em.includes(q));
      }
      if (list.length === 0) return;

      const title = document.createElement('div');
      title.className = 'emoji-category-title';
      title.textContent = cat.name;
      dom.emojiPickerScroll.appendChild(title);

      const grid = document.createElement('div');
      grid.className = 'emoji-grid';

      list.forEach(emoji => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'emoji-item-btn';
        btn.textContent = emoji;
        btn.title = emoji;
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          insertEmojiToChat(emoji);
        });
        grid.appendChild(btn);
      });

      dom.emojiPickerScroll.appendChild(grid);
    });

    if (dom.emojiPickerScroll.children.length === 0) {
      dom.emojiPickerScroll.innerHTML = '<div style="text-align: center; color: var(--text-muted); padding: 24px 0; font-size: 13px;">Nenhum emoji encontrado.</div>';
    }
  }

  function insertEmojiToChat(emoji) {
    if (!dom.chatInput) return;
    const input = dom.chatInput;
    const start = input.selectionStart !== null ? input.selectionStart : input.value.length;
    const end = input.selectionEnd !== null ? input.selectionEnd : input.value.length;
    const text = input.value;
    input.value = text.substring(0, start) + emoji + text.substring(end);
    const newPos = start + emoji.length;
    input.setSelectionRange(newPos, newPos);
    input.focus();
  }

  function toggleEmojiPicker() {
    if (!dom.emojiPickerPopover) return;
    const isHidden = dom.emojiPickerPopover.classList.toggle('hidden');
    if (!isHidden) {
      if (dom.emojiSearchInput) {
        dom.emojiSearchInput.value = '';
        dom.emojiSearchInput.focus();
      }
      renderEmojiPicker();
    }
  }

  if (dom.chatBtnEmoji) {
    dom.chatBtnEmoji.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleEmojiPicker();
    });
  }

  if (dom.btnCloseEmojiPicker) {
    dom.btnCloseEmojiPicker.addEventListener('click', () => {
      if (dom.emojiPickerPopover) dom.emojiPickerPopover.classList.add('hidden');
    });
  }

  if (dom.emojiSearchInput) {
    dom.emojiSearchInput.addEventListener('input', () => {
      renderEmojiPicker(dom.emojiSearchInput.value);
    });
  }

  // Fechar seletor de emojis ao clicar fora ou pressionar ESC
  document.addEventListener('click', (e) => {
    if (dom.emojiPickerPopover && !dom.emojiPickerPopover.classList.contains('hidden')) {
      if (!dom.emojiPickerPopover.contains(e.target) && e.target !== dom.chatBtnEmoji && !dom.chatBtnEmoji.contains(e.target)) {
        dom.emojiPickerPopover.classList.add('hidden');
      }
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && dom.emojiPickerPopover && !dom.emojiPickerPopover.classList.contains('hidden')) {
      dom.emojiPickerPopover.classList.add('hidden');
    }
  });

  // ==========================================
  // --- Universal HUD-Style Context Menu ---
  // ==========================================
  function closeContextMenu() {
    const menu = dom.appContextMenu || document.getElementById('app-context-menu');
    if (menu) {
      menu.classList.add('hidden');
      menu.innerHTML = '';
    }
  }

  function copyTextToClipboard(text, successMsg = 'Copiado para a área de transferência!') {
    if (!text) return;
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => {
        showToast(successMsg, 'success');
      }).catch(() => {
        fallbackCopyText(text, successMsg);
      });
    } else {
      fallbackCopyText(text, successMsg);
    }
  }

  function fallbackCopyText(text, successMsg) {
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      showToast(successMsg, 'success');
    } catch (err) {
      showToast('Não foi possível copiar.', 'warning');
    }
  }

  function mentionUserInChat(username) {
    if (!dom.chatInput) return;
    const mention = '@' + username + ' ';
    if (!dom.chatInput.value.includes(mention)) {
      dom.chatInput.value = (dom.chatInput.value ? dom.chatInput.value + ' ' : '') + mention;
    }
    dom.chatInput.focus();
    const len = dom.chatInput.value.length;
    dom.chatInput.setSelectionRange(len, len);
  }

  function markChannelAsRead(channelId) {
    if (state.unreadCounts[channelId]) {
      delete state.unreadCounts[channelId];
      updateDocumentTitle();
      renderChannelsList();
      showToast('Canal marcado como lido.', 'info');
    } else {
      showToast('O canal já está lido.', 'info');
    }
  }

  function markServerAsRead(serverId) {
    const targetServer = state.servers.find(s => s.id === serverId);
    if (!targetServer) return;
    let cleared = false;
    targetServer.channels.forEach(ch => {
      if (state.unreadCounts[ch.id]) {
        delete state.unreadCounts[ch.id];
        cleared = true;
      }
    });
    if (cleared) {
      updateDocumentTitle();
      renderChannelsList();
      showToast('Servidor "' + targetServer.name + '" marcado como lido.', 'info');
    } else {
      showToast('Todas as mensagens de "' + targetServer.name + '" já estão lidas.', 'info');
    }
  }

  function showContextMenu(e, items) {
    const menu = dom.appContextMenu || document.getElementById('app-context-menu');
    if (!menu || !items || items.length === 0) return;

    menu.innerHTML = '';

    items.forEach(item => {
      if (item.type === 'separator') {
        const sep = document.createElement('div');
        sep.className = 'context-menu-separator';
        menu.appendChild(sep);
      } else if (item.type === 'header') {
        const header = document.createElement('div');
        header.className = 'context-menu-header';
        header.textContent = item.label;
        header.addEventListener('click', (ev) => ev.stopPropagation());
        menu.appendChild(header);
      } else if (item.type === 'slider') {
        const row = document.createElement('div');
        row.className = 'context-menu-slider-row';

        const labelRow = document.createElement('div');
        labelRow.className = 'context-menu-slider-label';
        const valClass = item.userId ? 'val-display context-menu-volume-val' : 'val-display';
        const valAttr = item.userId ? ` data-user-id="${escapeHtml(item.userId)}"` : '';
        labelRow.innerHTML = '<span>' + escapeHtml(item.label) + '</span><span class="' + valClass + '"' + valAttr + '>' + item.value + (item.unit || '%') + '</span>';

        const slider = document.createElement('input');
        slider.type = 'range';
        slider.className = 'context-menu-slider context-menu-volume-slider';
        if (item.userId) slider.setAttribute('data-user-id', item.userId);
        slider.min = item.min !== undefined ? item.min : 0;
        slider.max = item.max !== undefined ? item.max : 200;
        slider.value = item.value !== undefined ? item.value : 100;

        const updateSliderVal = (ev) => {
          ev.stopPropagation();
          const v = parseInt(slider.value, 10);
          const disp = labelRow.querySelector('.val-display');
          if (disp) disp.textContent = v + (item.unit || '%');
          if (item.onChange) item.onChange(v);
        };

        slider.addEventListener('input', updateSliderVal);
        slider.addEventListener('change', updateSliderVal);
        slider.addEventListener('click', (ev) => ev.stopPropagation());
        slider.addEventListener('pointerdown', (ev) => ev.stopPropagation());
        slider.addEventListener('mousedown', (ev) => ev.stopPropagation());
        slider.addEventListener('touchstart', (ev) => ev.stopPropagation(), { passive: true });

        row.addEventListener('click', (ev) => ev.stopPropagation());
        row.addEventListener('contextmenu', (ev) => ev.stopPropagation());

        row.appendChild(labelRow);
        row.appendChild(slider);
        menu.appendChild(row);
      } else if (item.type === 'collapsible') {
        const wrap = document.createElement('div');
        wrap.className = 'context-menu-collapsible' + (item.defaultOpen ? ' open' : '');

        const header = document.createElement('button');
        header.type = 'button';
        header.className = 'context-menu-collapsible-header';

        const countHtml = (item.items && item.items.length > 0)
          ? `<span class="context-menu-collapsible-count">(${item.items.length})</span>`
          : '';
        header.innerHTML = 
          `<div class="context-menu-collapsible-left">` +
            (item.icon ? `<span class="context-menu-item-icon">${item.icon}</span>` : '') +
            `<span>${escapeHtml(item.label)}</span>` +
            countHtml +
          `</div>` +
          `<span class="context-menu-collapsible-chevron">▶</span>`;

        const body = document.createElement('div');
        body.className = 'context-menu-collapsible-body';

        (item.items || []).forEach(sub => {
          const subBtn = document.createElement('button');
          subBtn.type = 'button';
          subBtn.className = 'context-menu-subitem' + (sub.danger ? ' danger' : '');
          subBtn.innerHTML =
            `<div class="context-menu-item-left">` +
              (sub.icon ? `<span class="context-menu-item-icon">${sub.icon}</span>` : '') +
              `<span>${escapeHtml(sub.label)}</span>` +
            `</div>` +
            (sub.badge ? `<span class="context-menu-subitem-badge">${escapeHtml(sub.badge)}</span>` : '');

          subBtn.addEventListener('click', (ev) => {
            ev.stopPropagation();
            closeContextMenu();
            if (sub.action) sub.action();
          });
          body.appendChild(subBtn);
        });

        header.addEventListener('click', (ev) => {
          ev.stopPropagation();
          wrap.classList.toggle('open');
          const rect = menu.getBoundingClientRect();
          if (rect.bottom > window.innerHeight - 10) {
            const newTop = Math.max(10, window.innerHeight - rect.height - 10);
            menu.style.top = newTop + 'px';
          }
        });

        wrap.appendChild(header);
        wrap.appendChild(body);
        menu.appendChild(wrap);
      } else {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'context-menu-item' + (item.danger ? ' danger' : '');
        
        let iconHtml = item.icon ? '<span class="context-menu-item-icon">' + item.icon + '</span>' : '';
        let badgeHtml = item.badge ? '<span class="context-menu-item-badge">' + escapeHtml(item.badge) + '</span>' : '';
        
        btn.innerHTML = 
          '<div class="context-menu-item-left">' +
            iconHtml +
            '<span>' + escapeHtml(item.label) + '</span>' +
          '</div>' +
          badgeHtml;

        btn.addEventListener('click', (ev) => {
          ev.stopPropagation();
          closeContextMenu();
          if (item.action) item.action();
        });

        menu.appendChild(btn);
      }
    });

    menu.classList.remove('hidden');

    // Viewport edge collision protection
    const menuWidth = menu.offsetWidth || 230;
    const menuHeight = menu.offsetHeight || 260;

    let x = e.clientX;
    let y = e.clientY;

    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;

    if (x + menuWidth > viewportWidth - 10) {
      x = Math.max(10, viewportWidth - menuWidth - 10);
    }
    if (y + menuHeight > viewportHeight - 10) {
      y = Math.max(10, viewportHeight - menuHeight - 10);
    }

    menu.style.left = Math.max(10, x) + 'px';
    menu.style.top = Math.max(10, y) + 'px';
  }

  // --- Right-Click Dispatcher ---
  document.addEventListener('contextmenu', (e) => {
    // 1. CHAT USERS (Highest priority when clicking avatar or author inside messages)
    const msgAuthor = e.target.closest('.message-author, .message-avatar');
    const memberItem = e.target.closest('.member-item');
    const userBarEl = e.target.closest('.user-profile-bar, #user-profile-trigger');

    // 2. CALL PARTICIPANTS & CALL STAGE
    const loungeCard = e.target.closest('.lounge-member-card');
    const voiceRow = e.target.closest('.voice-user-row');
    const loungeStage = e.target.closest('.lounge-stage, .lounge-call-bar, #voice-lounge');

    // 3. MESSAGES FEED ITEM
    const msgItem = e.target.closest('.message-item');

    // 4. SERVER RAIL ICONS & RAIL
    const serverIcon = e.target.closest('.server-icon');
    const serverRailEl = e.target.closest('.server-rail');
    const serverHeaderEl = e.target.closest('.server-header');

    // 5. CHANNELS LIST / CATEGORY
    const channelItem = e.target.closest('.channel-item');
    const catHeader = e.target.closest('.category-header');

    // TARGET 1: CHAMADAS (Voice Lounge call stage & sidebar voice channels user tree)
    if (loungeCard || voiceRow || (loungeStage && !msgItem && !memberItem && !userBarEl && !serverIcon && !channelItem)) {
      e.preventDefault();
      const userId = loungeCard ? loungeCard.getAttribute('data-user-id') : (voiceRow ? voiceRow.getAttribute('data-user-id') : state.currentUser.id);
      const userName = (loungeCard ? loungeCard.getAttribute('data-user-name') : (voiceRow ? voiceRow.getAttribute('data-user-name') : state.currentUser.username)) || 'Usuário';
      const chanId = (loungeCard ? loungeCard.getAttribute('data-channel-id') : (voiceRow ? voiceRow.getAttribute('data-channel-id') : '')) || (state.connectedVoiceChannel ? state.connectedVoiceChannel.id : '');
      const isMe = (userId === state.currentUser.id);

      const items = [];

      if (isMe) {
        items.push({ type: 'header', label: '🔊 Sua Voz na Chamada' });
        items.push({
          type: 'collapsible',
          label: 'Status: ' + getStatusLabel(state.currentUser.status),
          icon: state.currentUser.status === 'dnd' ? '🔴' : (state.currentUser.status === 'idle' ? '🟡' : '🟢'),
          items: [
            {
              label: 'Online',
              icon: '🟢',
              badge: state.currentUser.status === 'online' ? 'Ativo' : '',
              action: () => setUserStatus('online')
            },
            {
              label: 'Ausente',
              icon: '🟡',
              badge: state.currentUser.status === 'idle' ? 'Ativo' : '',
              action: () => setUserStatus('idle')
            },
            {
              label: 'Não Perturbe',
              icon: '🔴',
              badge: state.currentUser.status === 'dnd' ? 'Ativo' : '',
              action: () => setUserStatus('dnd')
            }
          ]
        });
        items.push({
          label: state.isMuted ? 'Desmutar Microfone' : 'Mutar Microfone',
          icon: state.isMuted ? '🎙️' : '🔇',
          action: () => toggleMute()
        });
        items.push({
          label: state.isDeafened ? 'Desensurdecer Áudio' : 'Ensurdecer Áudio',
          icon: state.isDeafened ? '🎧' : '🎧❌',
          action: () => toggleDeafen()
        });
        if (state.isSharingScreen) {
          items.push({
            label: 'Ajustar Qualidade da Transmissão',
            icon: '⚙️',
            action: () => openScreenShareModal()
          });
          items.push({
            label: 'Parar Transmissão de Tela',
            icon: '⏹️',
            action: () => stopScreenShare()
          });
        } else {
          items.push({
            label: 'Transmitir Tela (1 Clique)',
            icon: '🖥️',
            action: () => toggleScreenShare()
          });
          items.push({
            label: 'Configurações de Transmissão...',
            icon: '⚙️',
            action: () => openScreenShareModal()
          });
        }
        items.push({
          label: state.isCameraOn ? 'Desligar Câmera' : 'Ligar Câmera',
          icon: '📷',
          action: () => toggleCamera()
        });
        items.push({
          label: 'Alternar Tela Cheia',
          icon: '⛶',
          action: () => toggleLoungeFullscreen()
        });

        // Direct voice channel switch for self (RETRAÍDO)
        const myChanId = chanId || (state.connectedVoiceChannel ? state.connectedVoiceChannel.id : '');
        const otherVoiceChannels = getActiveServerChannels().filter(c => c.type === 'voice' && c.id !== myChanId);
        if (otherVoiceChannels.length > 0) {
          items.push({ type: 'separator' });
          items.push({
            type: 'collapsible',
            label: 'Mudar de Sala de Voz',
            icon: '🔊',
            items: otherVoiceChannels.map(dest => ({
              label: '#' + dest.name,
              icon: '🔊',
              badge: 'Mudar',
              action: () => executeMoveUser(state.currentUser.id, state.currentUser.username, dest.id, dest.name)
            }))
          });
        }

        items.push({ type: 'separator' });
        items.push({
          label: 'Desconectar da Chamada',
          icon: '📞',
          danger: true,
          action: () => leaveVoiceChannel()
        });
      } else {
        items.push({ type: 'header', label: '👤 ' + userName });
        const currentVol = state.userVolumes[userId] !== undefined ? state.userVolumes[userId] : 100;
        items.push({
          type: 'slider',
          userId: userId,
          label: 'Volume de ' + userName,
          value: currentVol,
          min: 0,
          max: 200,
          unit: '%',
          onChange: (val) => {
            setUserVolume(userId, val);
          }
        });
        const isLocallyMuted = (currentVol === 0);
        items.push({
          label: isLocallyMuted ? 'Desmutar Localmente' : 'Mutar Localmente',
          icon: isLocallyMuted ? '🔊' : '🔇',
          action: () => {
            const newVol = isLocallyMuted ? 100 : 0;
            setUserVolume(userId, newVol);
            showToast(isLocallyMuted ? ('Áudio de ' + userName + ' desmutado') : ('Áudio de ' + userName + ' mutado localmente'), 'info');
          }
        });

        // Direct voice channel options to move this user (RETRAÍDO)
        const otherVoiceChannels = getActiveServerChannels().filter(c => c.type === 'voice' && c.id !== chanId);
        if (otherVoiceChannels.length > 0) {
          items.push({ type: 'separator' });
          const moveSubitems = otherVoiceChannels.map(dest => ({
            label: '#' + dest.name,
            icon: '🔊',
            badge: 'Mover',
            action: () => executeMoveUser(userId, userName, dest.id, dest.name)
          }));
          moveSubitems.push({
            label: 'Outras salas (abrir modal)...',
            icon: '⇄',
            action: () => openMoveModal(userId, userName, chanId)
          });
          items.push({
            type: 'collapsible',
            label: 'Mover ' + userName + ' para Sala',
            icon: '🔊',
            items: moveSubitems
          });
        } else if (chanId) {
          items.push({
            label: 'Mover para outra sala...',
            icon: '⇄',
            action: () => openMoveModal(userId, userName, chanId)
          });
        }

        items.push({ type: 'separator' });
        items.push({
          label: 'Mencionar @' + userName,
          icon: '@',
          action: () => mentionUserInChat(userName)
        });
        items.push({
          label: 'Copiar Nome',
          icon: '📋',
          action: () => copyTextToClipboard(userName, 'Nome de ' + userName + ' copiado!')
        });
        items.push({
          label: 'Copiar ID do Usuário',
          icon: '🆔',
          action: () => copyTextToClipboard(userId, 'ID copiado!')
        });
      }

      showContextMenu(e, items);
      return;
    }

    // TARGET 4: USUÁRIOS (Clicking on author/avatar in chat, member in online members sidebar, or user-profile-bar)
    if (msgAuthor || memberItem || userBarEl) {
      e.preventDefault();
      const userId = memberItem ? memberItem.getAttribute('data-user-id') : (msgAuthor ? msgAuthor.getAttribute('data-user-id') : state.currentUser.id);
      const userName = (memberItem ? memberItem.getAttribute('data-user-name') : (msgAuthor ? msgAuthor.getAttribute('data-user-name') : state.currentUser.username)) || 'Usuário';
      const isMe = (userId === state.currentUser.id);
      const voiceChanId = memberItem ? memberItem.getAttribute('data-voice-channel-id') : '';

      // Determine voice channel of target user
      const targetVoiceChanId = voiceChanId || (() => {
        if (isMe && state.connectedVoiceChannel) return state.connectedVoiceChannel.id;
        const u = state.users.find(x => x.id === userId);
        if (u && u.voiceChannelId) return u.voiceChannelId;
        const gu = state.globalUsers ? state.globalUsers.get(userId) : null;
        if (gu && gu.voiceChannelId && (gu.voiceServerId === state.activeServerId || !gu.voiceServerId)) return gu.voiceChannelId;
        return '';
      })();

      const items = [];
      items.push({ type: 'header', label: '👤 ' + userName + (isMe ? ' (Você)' : '') });

      if (isMe) {
        items.push({
          type: 'collapsible',
          label: 'Status: ' + getStatusLabel(state.currentUser.status),
          icon: state.currentUser.status === 'dnd' ? '🔴' : (state.currentUser.status === 'idle' ? '🟡' : '🟢'),
          defaultOpen: true,
          items: [
            {
              label: 'Online',
              icon: '🟢',
              badge: state.currentUser.status === 'online' ? 'Ativo' : '',
              action: () => setUserStatus('online')
            },
            {
              label: 'Ausente',
              icon: '🟡',
              badge: state.currentUser.status === 'idle' ? 'Ativo' : '',
              action: () => setUserStatus('idle')
            },
            {
              label: 'Não Perturbe',
              icon: '🔴',
              badge: state.currentUser.status === 'dnd' ? 'Ativo' : '',
              action: () => setUserStatus('dnd')
            }
          ]
        });
        items.push({
          label: 'Configurações de Usuário',
          icon: '⚙️',
          action: () => {
            if (dom.btnSettings) dom.btnSettings.click();
          }
        });
      } else {
        items.push({
          label: 'Mencionar @' + userName,
          icon: '@',
          action: () => mentionUserInChat(userName)
        });
        // If peer is in active voice call with me or has an active audio/WebRTC stream
        const isInCallWithMe = (
          (state.connectedVoiceChannel && targetVoiceChanId && targetVoiceChanId === state.connectedVoiceChannel.id) ||
          rtc.remoteAudios.has(userId) ||
          rtc.peers.has(userId)
        );

        if (isInCallWithMe) {
          const currentVol = state.userVolumes[userId] !== undefined ? state.userVolumes[userId] : 100;
          items.push({
            type: 'slider',
            userId: userId,
            label: 'Volume de ' + userName,
            value: currentVol,
            min: 0,
            max: 200,
            unit: '%',
            onChange: (val) => {
              setUserVolume(userId, val);
            }
          });
          const isLocallyMuted = (currentVol === 0);
          items.push({
            label: isLocallyMuted ? 'Desmutar Localmente' : 'Mutar Localmente',
            icon: isLocallyMuted ? '🔊' : '🔇',
            action: () => {
              const newVol = isLocallyMuted ? 100 : 0;
              setUserVolume(userId, newVol);
              showToast(isLocallyMuted ? ('Áudio de ' + userName + ' desmutado') : ('Áudio de ' + userName + ' mutado localmente'), 'info');
            }
          });
        }
      }

      // Voice move options if target user is connected to a voice channel (RETRAÍDO)
      if (targetVoiceChanId) {
        const otherVoiceChannels = getActiveServerChannels().filter(c => c.type === 'voice' && c.id !== targetVoiceChanId);
        if (otherVoiceChannels.length > 0) {
          items.push({ type: 'separator' });
          const moveSubitems = otherVoiceChannels.map(dest => ({
            label: '#' + dest.name,
            icon: '🔊',
            badge: isMe ? 'Mudar' : 'Mover',
            action: () => executeMoveUser(userId, userName, dest.id, dest.name)
          }));
          if (!isMe) {
            moveSubitems.push({
              label: 'Outras salas (abrir modal)...',
              icon: '⇄',
              action: () => openMoveModal(userId, userName, targetVoiceChanId)
            });
          }

          items.push({
            type: 'collapsible',
            label: isMe ? 'Mudar de Sala de Voz' : ('Mover ' + userName + ' para Sala'),
            icon: '🔊',
            items: moveSubitems
          });
        }
      }

      items.push({ type: 'separator' });
      items.push({
        label: 'Copiar Nome',
        icon: '📋',
        action: () => copyTextToClipboard(userName, 'Nome de ' + userName + ' copiado!')
      });
      items.push({
        label: 'Copiar ID do Usuário',
        icon: '🆔',
        action: () => copyTextToClipboard(userId, 'ID do usuário copiado!')
      });

      showContextMenu(e, items);
      return;
    }

    // TARGET 2: MENSAGENS (Chat messages in feed)
    if (msgItem) {
      e.preventDefault();
      const msgId = msgItem.getAttribute('data-message-id');
      const authorName = msgItem.getAttribute('data-author-name') || 'Usuário';
      const authorId = msgItem.getAttribute('data-author-id') || '';
      const msgText = msgItem.getAttribute('data-message-text') || '';
      const gifUrl = msgItem.getAttribute('data-gif-url') || '';
      const isOwner = (authorId === state.currentUser.id);

      const items = [];
      items.push({ type: 'header', label: '💬 Mensagem de ' + authorName });

      items.push({
        label: 'Responder Mensagem',
        icon: '↩️',
        action: () => startReplyingToMessage(msgId, authorName, msgText || (gifUrl ? '[GIF]' : ''), authorId)
      });

      if (msgText) {
        items.push({
          label: 'Copiar Texto',
          icon: '📋',
          action: () => copyTextToClipboard(msgText, 'Texto copiado!')
        });
      }

      if (gifUrl) {
        items.push({
          label: 'Copiar Link do GIF',
          icon: '🖼️',
          action: () => copyTextToClipboard(gifUrl, 'Link do GIF copiado!')
        });
        items.push({
          label: 'Abrir GIF em Nova Aba',
          icon: '↗️',
          action: () => window.open(gifUrl, '_blank')
        });
      }

      items.push({
        label: 'Mencionar Autor',
        icon: '@',
        action: () => mentionUserInChat(authorName)
      });

      items.push({
        label: 'Adicionar Emoji...',
        icon: '😀',
        action: () => {
          if (dom.chatBtnEmoji) dom.chatBtnEmoji.click();
        }
      });

      items.push({
        label: 'Copiar ID da Mensagem',
        icon: '🆔',
        action: () => copyTextToClipboard(msgId, 'ID da mensagem copiado!')
      });

      if (isOwner) {
        items.push({ type: 'separator' });
        items.push({
          label: 'Apagar Mensagem',
          icon: '🗑️',
          danger: true,
          action: () => deleteChatMessage(msgId)
        });
      }

      showContextMenu(e, items);
      return;
    }

    // TARGET 3: SERVIDORES (Server rail icons on the left or server rail area)
    if (serverIcon) {
      e.preventDefault();
      const serverId = serverIcon.getAttribute('data-server-id');
      const targetServer = state.servers.find(s => s.id === serverId);
      if (!targetServer) {
        if (serverIcon.id === 'btn-maximize-servers' || serverIcon.classList.contains('hub-server')) {
          openServerHub();
          return;
        }
        if (serverIcon.id === 'btn-collapse-server-rail' || serverIcon.classList.contains('collapse-server-rail')) {
          collapseServerRail(true);
          return;
        }
        return;
      }

      const items = [];
      items.push({ type: 'header', label: '🌐 ' + targetServer.name });

      items.push({
        label: 'Convidar Amigos',
        icon: '👥',
        action: () => {
          selectServer(serverId);
          openInviteFriendsModal();
        }
      });

      items.push({
        label: 'Configurações do Servidor',
        icon: '⚙️',
        action: () => {
          selectServer(serverId);
          openServerSettingsModal();
        }
      });

      items.push({
        label: 'Marcar como Lido',
        icon: '✓',
        action: () => markServerAsRead(serverId)
      });

      items.push({ type: 'separator' });

      items.push({
        label: 'Central de Servidores (Tela Cheia)',
        icon: '⊞',
        action: () => openServerHub()
      });

      items.push({
        label: 'Ocultar Baia de Servidores',
        icon: '⇤',
        action: () => collapseServerRail(true)
      });

      items.push({ type: 'separator' });

      items.push({
        label: 'Copiar Link de Convite',
        icon: '🔗',
        action: () => {
          const origin = window.location.origin;
          const pathname = window.location.pathname;
          const inviteLink = origin + pathname + '?invite=' + targetServer.inviteCode;
          copyTextToClipboard(inviteLink, 'Link de convite do servidor copiado!');
        }
      });

      items.push({
        label: 'Copiar ID do Servidor',
        icon: '🆔',
        action: () => copyTextToClipboard(serverId, 'ID do servidor copiado!')
      });

      items.push({ type: 'separator' });

      if (targetServer.id === DEFAULT_SERVER_ID) {
        items.push({
          label: 'Servidor Padrão (Fixo)',
          icon: '🔒',
          badge: 'Padrão',
          action: () => showToast('O servidor padrão ProjetoUS não pode ser excluído.', 'warning')
        });
      } else {
        items.push({
          label: 'Sair do Servidor',
          icon: '🚪',
          danger: true,
          action: () => {
            selectServer(serverId);
            handleLeaveCurrentServer();
          }
        });
      }

      showContextMenu(e, items);
      return;
    }

    if (serverRailEl && !serverIcon) {
      e.preventDefault();
      const items = [
        { type: 'header', label: '🌐 Baia de Servidores' },
        { label: 'Central de Servidores (Tela Cheia)', icon: '⊞', action: () => openServerHub() },
        { label: 'Criar um Novo Servidor', icon: '➕', action: () => dom.btnAddServer.click() },
        { type: 'separator' },
        { label: 'Ocultar Baia de Servidores (Alt+S)', icon: '⇤', action: () => collapseServerRail(true) }
      ];
      showContextMenu(e, items);
      return;
    }

    if (serverHeaderEl && !catHeader && !channelItem) {
      e.preventDefault();
      const srv = getActiveServer();
      const isCollapsed = dom.appLeftPanel && dom.appLeftPanel.classList.contains('rail-collapsed');
      const items = [
        { type: 'header', label: '🌐 ' + srv.name },
        { label: 'Convidar Usuário', icon: '👥', action: () => openInviteFriendsModal() },
        { label: 'Configuração do Servidor', icon: '⚙️', action: () => openServerSettingsModal() },
        { type: 'separator' },
        { label: 'Central de Servidores (Tela Cheia)', icon: '⊞', action: () => openServerHub() },
        { 
          label: isCollapsed ? 'Mostrar Baia de Servidores (Alt+S)' : 'Ocultar Baia de Servidores (Alt+S)', 
          icon: isCollapsed ? '⇥' : '⇤', 
          action: () => collapseServerRail(!isCollapsed) 
        }
      ];
      showContextMenu(e, items);
      return;
    }

    // TARGET 5: BAIA DE CHAT (Canais de texto, canais de voz, cabeçalhos de categoria)
    if (channelItem || catHeader) {
      e.preventDefault();

      if (catHeader) {
        const isVoiceCat = catHeader.id === 'category-header-voice' || catHeader.textContent.includes('Voz');
        const items = [];
        items.push({ type: 'header', label: '📂 ' + (isVoiceCat ? 'Canais de Voz' : 'Canais de Texto') });

        items.push({
          label: isVoiceCat ? 'Criar Canal de Voz...' : 'Criar Canal de Texto...',
          icon: '➕',
          action: () => openCreateChannelModal(isVoiceCat ? 'voice' : 'text')
        });

        items.push({
          label: 'Recolher / Expandir Categoria',
          icon: '▾',
          action: () => catHeader.click()
        });

        showContextMenu(e, items);
        return;
      }

      const chanId = channelItem.getAttribute('data-channel-id');
      const chanType = channelItem.getAttribute('data-channel-type') || 'text';
      const chanName = channelItem.getAttribute('data-channel-name') || 'canal';
      const chanObj = getActiveServerChannels().find(c => c.id === chanId);

      const items = [];

      if (chanType === 'text') {
        items.push({ type: 'header', label: '# ' + chanName });

        items.push({
          label: 'Abrir Canal',
          icon: '#',
          action: () => selectChannel(chanId)
        });

        items.push({
          label: 'Marcar como Lido',
          icon: '✓',
          action: () => markChannelAsRead(chanId)
        });

        items.push({
          label: 'Copiar Nome do Canal',
          icon: '📋',
          action: () => copyTextToClipboard(chanName, 'Nome do canal copiado!')
        });

        items.push({
          label: 'Copiar ID do Canal',
          icon: '🆔',
          action: () => copyTextToClipboard(chanId, 'ID do canal copiado!')
        });

        items.push({ type: 'separator' });

        items.push({
          label: 'Criar Novo Canal de Texto...',
          icon: '➕',
          action: () => openCreateChannelModal('text')
        });
      } else {
        // Voice Channel
        items.push({ type: 'header', label: '🔊 ' + chanName });

        const isConnectedHere = state.connectedVoiceChannel && state.connectedVoiceChannel.id === chanId;

        if (isConnectedHere) {
          items.push({
            label: state.isMuted ? 'Desmutar Microfone' : 'Mutar Microfone',
            icon: state.isMuted ? '🎙️' : '🔇',
            action: () => toggleMute()
          });
          items.push({
            label: state.isDeafened ? 'Desensurdecer Áudio' : 'Ensurdecer Áudio',
            icon: state.isDeafened ? '🎧' : '🎧❌',
            action: () => toggleDeafen()
          });
          items.push({
            label: 'Desconectar da Sala',
            icon: '📞',
            danger: true,
            action: () => leaveVoiceChannel()
          });
        } else {
          items.push({
            label: 'Entrar na Sala de Voz',
            icon: '🔊',
            action: () => joinVoiceChannel(chanObj || { id: chanId, name: chanName, type: 'voice' })
          });

          if (state.connectedVoiceChannel) {
            items.push({
              label: 'Mudar para esta Sala',
              icon: '⇄',
              badge: 'Mudar',
              action: () => executeMoveUser(state.currentUser.id, state.currentUser.username, chanId, chanName)
            });
          }
        }

        // Pull users from other voice rooms to this channel
        const usersInOtherRooms = state.users.filter(u => u.voiceChannelId && u.voiceChannelId !== chanId);
        if (usersInOtherRooms.length > 0) {
          items.push({ type: 'separator' });
          items.push({ type: 'header', label: '👥 Puxar Participante para cá' });
          usersInOtherRooms.forEach(u => {
            const isMe = (u.id === state.currentUser.id);
            items.push({
              label: isMe ? 'Mover-se para cá' : ('Puxar ' + u.username),
              icon: '📥',
              action: () => executeMoveUser(u.id, u.username, chanId, chanName)
            });
          });
        }

        items.push({ type: 'separator' });

        items.push({
          label: 'Copiar Nome da Sala',
          icon: '📋',
          action: () => copyTextToClipboard(chanName, 'Nome da sala copiado!')
        });

        items.push({
          label: 'Copiar ID da Sala',
          icon: '🆔',
          action: () => copyTextToClipboard(chanId, 'ID da sala copiado!')
        });

        items.push({ type: 'separator' });

        items.push({
          label: 'Criar Novo Canal de Voz...',
          icon: '➕',
          action: () => openCreateChannelModal('voice')
        });
      }

      showContextMenu(e, items);
      return;
    }

    // Otherwise close menu and let standard browser right-click proceed
    closeContextMenu();
  });

  // Global dismissal listeners
  document.addEventListener('click', (e) => {
    const menu = dom.appContextMenu || document.getElementById('app-context-menu');
    if (menu && !menu.classList.contains('hidden')) {
      if (!menu.contains(e.target)) {
        closeContextMenu();
      }
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      closeContextMenu();
    }
  });

  window.addEventListener('resize', closeContextMenu);
  window.addEventListener('scroll', (e) => {
    const menu = dom.appContextMenu || document.getElementById('app-context-menu');
    if (menu && menu.contains(e.target)) return;
    closeContextMenu();
  }, true);
}

function openCreateChannelModal(defaultType) {
  dom.channelNameInput.value = '';
  if (defaultType === 'voice') dom.optionVoiceChan.click();
  else dom.optionTextChan.click();
  dom.channelModal.classList.remove('hidden');
  dom.channelNameInput.focus();
}

window.addEventListener('DOMContentLoaded', initApp);
