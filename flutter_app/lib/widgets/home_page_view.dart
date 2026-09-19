import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../models/server.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'modals/create_server_dialog.dart';
import 'modals/add_friend_dialog.dart';
import 'modals/server_invite_dialog.dart';

class HomePageView extends StatefulWidget {
  const HomePageView({super.key});

  @override
  State<HomePageView> createState() => _HomePageViewState();
}

enum FriendViewTab { online, all, offline }

class _HomePageViewState extends State<HomePageView> {
  FriendViewTab _selectedTab = FriendViewTab.online;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentUser = state.currentUser;
    final isVoiceConnected = state.connectedVoiceChannelId != null;

    final allFriends = state.friendsWithLiveStatus;
    final onlineFriends = allFriends.where((f) => f.status != UserStatus.offline).toList();
    final offlineFriends = allFriends.where((f) => f.status == UserStatus.offline).toList();

    List<UserModel> currentList;
    switch (_selectedTab) {
      case FriendViewTab.online:
        currentList = onlineFriends;
        break;
      case FriendViewTab.all:
        currentList = allFriends;
        break;
      case FriendViewTab.offline:
        currentList = offlineFriends;
        break;
    }

    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      currentList = currentList.where((u) {
        final nameMatches = u.displayNameOrUsername.toLowerCase().contains(query);
        final handleMatches = u.handle.toLowerCase().contains(query);
        final tagMatches = u.username.toLowerCase().contains(query);
        return nameMatches || handleMatches || tagMatches;
      }).toList();
    }

    return Container(
      color: HudTheme.bgChat,
      child: Column(
        children: [
          // Barra de Navegação Superior HUD (com abas de Amigos)
          _buildTopBar(
            context,
            state,
            onlineFriends.length,
            allFriends.length,
            offlineFriends.length,
          ),

          // Painel de Rolagem Principal
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero Banner de Boas-Vindas Tático
                  _buildHeroCard(context, state, currentUser),
                  const SizedBox(height: 24),

                  // Banner de Chamada Ativa (se conectado)
                  if (isVoiceConnected) ...[
                    _buildActiveCallBanner(context, state),
                    const SizedBox(height: 24),
                  ],

                  // Barra de Busca Rápida de Amigos
                  _buildSearchBar(),
                  const SizedBox(height: 18),

                  // Seção Principal: Central de Amigos
                  _buildFriendsListSection(
                    context,
                    state,
                    currentList,
                    allFriends.length,
                  ),
                  const SizedBox(height: 32),

                  // Seção: Meus Servidores (Grid Tático)
                  _buildServersSection(context, state),
                  const SizedBox(height: 28),

                  // Salas de Voz Disponíveis
                  _buildVoiceLoungesCard(context, state),
                  const SizedBox(height: 28),

                  // Painel de Diagnósticos do Sistema HUD
                  _buildSystemStatusCard(state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TOP BAR COM ABAS DE AMIGOS ---
  Widget _buildTopBar(
    BuildContext context,
    AppState state,
    int onlineCount,
    int allCount,
    int offlineCount,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: HudTheme.bgSidebar,
        border: Border(bottom: BorderSide(color: HudTheme.divider, width: 1)),
      ),
      child: Row(
        children: [
          // Ícone e Título Amigos
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: HudTheme.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.people_alt_rounded, color: HudTheme.green, size: 20),
          ),
          const SizedBox(width: 10),
          const Text(
            'Amigos',
            style: TextStyle(
              color: HudTheme.textHeader,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 20, color: HudTheme.divider),
          const SizedBox(width: 12),

          // Abas de Filtro
          _buildFilterTab(FriendViewTab.online, 'Disponível', onlineCount),
          const SizedBox(width: 6),
          _buildFilterTab(FriendViewTab.all, 'Todos', allCount),
          const SizedBox(width: 6),
          _buildFilterTab(FriendViewTab.offline, 'Offline', offlineCount),
          const SizedBox(width: 12),

          // Botão Verde Neon: Adicionar Amigo
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 1,
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
            label: const Text(
              'Adicionar Amigo',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            onPressed: () => AddFriendDialog.show(context),
          ),

          const Spacer(),

          // Botão: Entrar via Código de Convite
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: HudTheme.accent,
              side: const BorderSide(color: HudTheme.divider),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.vpn_key_rounded, size: 14),
            label: const Text('Entrar com Convite', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
            onPressed: () => _showJoinInviteDialog(context, state),
          ),
          const SizedBox(width: 8),

          // Botão: Criar Novo Servidor
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.bgCard,
              foregroundColor: Colors.white,
              side: const BorderSide(color: HudTheme.divider),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.add_rounded, size: 16, color: HudTheme.green),
            label: const Text('Criar Servidor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            onPressed: () => CreateServerDialog.show(context),
          ),

          if (state.activeServer != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: HudTheme.textHeader,
                side: const BorderSide(color: HudTheme.divider),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 14, color: HudTheme.accent),
              label: Text(
                state.activeServer!.name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
              ),
              onPressed: state.closeHomePage,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterTab(FriendViewTab tab, String label, int count) {
    final isSelected = _selectedTab == tab;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = tab;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? HudTheme.bgHover : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : HudTheme.textMuted,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? HudTheme.green : HudTheme.bgCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? Colors.black : HudTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- BARRA DE BUSCA RÁPIDA ---
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: HudTheme.bgSidebar,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HudTheme.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: HudTheme.textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Buscar amigos por nome de exibição ou @tag...',
                hintStyle: TextStyle(color: HudTheme.textMuted, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: HudTheme.textMuted, size: 16),
              splashRadius: 16,
              onPressed: () {
                setState(() {
                  _searchController.clear();
                });
              },
            ),
        ],
      ),
    );
  }

  // --- SEÇÃO PRINCIPAL DE AMIGOS ---
  Widget _buildFriendsListSection(
    BuildContext context,
    AppState state,
    List<UserModel> friends,
    int totalFriendsCount,
  ) {
    String tabTitle;
    switch (_selectedTab) {
      case FriendViewTab.online:
        tabTitle = 'DISPONÍVEIS';
        break;
      case FriendViewTab.all:
        tabTitle = 'TODOS OS AMIGOS';
        break;
      case FriendViewTab.offline:
        tabTitle = 'OFFLINE';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: HudTheme.bgSidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HudTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_alt_rounded, color: HudTheme.green, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    '$tabTitle (${friends.length})',
                    style: const TextStyle(
                      color: HudTheme.textHeader,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Text(
                'Total de Amigos: $totalFriendsCount',
                style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (friends.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: HudTheme.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.radar_rounded, color: HudTheme.green, size: 38),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _selectedTab == FriendViewTab.online
                        ? 'Nenhum amigo online no momento.'
                        : (_selectedTab == FriendViewTab.offline
                            ? 'Nenhum amigo offline.'
                            : 'Nenhum amigo encontrado.'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Adicione seus amigos usando a tag única @usuario para iniciar chamadas e conversar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: HudTheme.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HudTheme.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: const Text('Adicionar Amigo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () => AddFriendDialog.show(context),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: friends.length,
              separatorBuilder: (_, _) => const Divider(color: HudTheme.divider, height: 12),
              itemBuilder: (context, index) {
                final friend = friends[index];
                final inCall = friend.currentVoiceChannelId != null;
                final isOffline = friend.status == UserStatus.offline;

                Color statusBadgeColor;
                String statusLabel;
                switch (friend.status) {
                  case UserStatus.online:
                    statusBadgeColor = HudTheme.statusOnline;
                    statusLabel = inCall ? 'Em chamada de voz' : 'Disponível no PapoCall';
                    break;
                  case UserStatus.idle:
                    statusBadgeColor = HudTheme.statusIdle;
                    statusLabel = 'Ausente';
                    break;
                  case UserStatus.dnd:
                    statusBadgeColor = HudTheme.statusDnd;
                    statusLabel = 'Não Perturbe';
                    break;
                  case UserStatus.offline:
                    statusBadgeColor = HudTheme.statusOffline;
                    statusLabel = 'Offline';
                    break;
                }

                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  hoverColor: HudTheme.bgHover.withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: [
                        // Avatar com indicador de presença
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: isOffline ? HudTheme.bgSidebar : HudTheme.bgHover,
                              child: Text(
                                friend.initials,
                                style: TextStyle(
                                  color: isOffline ? HudTheme.textMuted : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: statusBadgeColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: HudTheme.bgSidebar, width: 2),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),

                        // Nome de Exibição + Tag @usuario
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    friend.displayNameOrUsername,
                                    style: TextStyle(
                                      color: isOffline ? HudTheme.textMuted : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    friend.handle,
                                    style: const TextStyle(
                                      color: HudTheme.green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  color: inCall ? HudTheme.green : HudTheme.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Ações Rápidas
                        if (inCall)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HudTheme.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.call_rounded, size: 14),
                            label: const Text(
                              'Entrar na Call',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () {
                              state.connectVoice(friend.currentVoiceChannelId!);
                              state.selectChannel(friend.currentVoiceChannelId!);
                              state.closeHomePage();
                            },
                          ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.person_remove_rounded, size: 18, color: HudTheme.textMuted),
                          tooltip: 'Remover dos Amigos',
                          splashRadius: 18,
                          onPressed: () => state.removeFriend(friend.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // --- HERO CARD ---
  Widget _buildHeroCard(BuildContext context, AppState state, UserModel user) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HudTheme.bgCard,
            HudTheme.bgSidebar.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HudTheme.green.withValues(alpha: 0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar do Usuário
          Stack(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: HudTheme.bgHover,
                child: Text(
                  user.username.isNotEmpty
                      ? user.username.replaceAll('@', '').substring(0, 1).toUpperCase()
                      : 'P',
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: HudTheme.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: HudTheme.bgCard, width: 3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),

          // Informações e Versão
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Bem-vindo ao PapoCall, ${user.username}!',
                      style: const TextStyle(
                        color: HudTheme.textHeader,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: HudTheme.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: HudTheme.green.withValues(alpha: 0.4)),
                      ),
                      child: const Text(
                        'v${HudTheme.appVersion}',
                        style: TextStyle(color: HudTheme.green, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Comunicação militar tática de alta fidelidade: voz de baixa latência, salas de squad e streaming otimizado.',
                  style: TextStyle(color: HudTheme.textMuted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 14),

                // Métricas Rápidas
                Row(
                  children: [
                    _buildMetricChip(
                      icon: Icons.dns_rounded,
                      label: 'Servidores: ${state.servers.length}',
                      color: HudTheme.accent,
                    ),
                    const SizedBox(width: 12),
                    _buildMetricChip(
                      icon: Icons.people_alt_rounded,
                      label: 'Squad Online: ${state.onlineMembers.length}',
                      color: HudTheme.green,
                    ),
                    const SizedBox(width: 12),
                    _buildMetricChip(
                      icon: Icons.graphic_eq_rounded,
                      label: 'Motor LiveKit: Pronto',
                      color: HudTheme.yellow,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Botão Abrir Conversas
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 4,
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Abrir Conversas', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: state.closeHomePage,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // --- ACTIVE CALL BANNER ---
  Widget _buildActiveCallBanner(BuildContext context, AppState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: HudTheme.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HudTheme.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: HudTheme.green.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.volume_up_rounded, color: HudTheme.green, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Você está em uma chamada de voz ativa',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  'Canal: #${state.activeChannel?.name ?? state.connectedVoiceChannelId}  •  Transmissão RTC em tempo real',
                  style: const TextStyle(color: HudTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: HudTheme.green,
              backgroundColor: HudTheme.green.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.headset_rounded, size: 16),
            label: const Text('Voltar para a Call', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              state.closeHomePage();
              if (state.connectedVoiceChannelId != null) {
                state.selectChannel(state.connectedVoiceChannelId!);
              }
            },
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Desconectar da chamada',
            icon: const Icon(Icons.call_end_rounded, color: HudTheme.red, size: 20),
            onPressed: state.disconnectVoice,
          ),
        ],
      ),
    );
  }

  // --- SEÇÃO MEUS SERVIDORES (GRID TÁTICO) ---
  Widget _buildServersSection(BuildContext context, AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.dns_rounded, color: HudTheme.green, size: 20),
                const SizedBox(width: 10),
                Text(
                  'SEUS SERVIDORES (${state.servers.length})',
                  style: const TextStyle(
                    color: HudTheme.textHeader,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: HudTheme.green,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
              label: const Text('Novo Servidor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              onPressed: () => CreateServerDialog.show(context),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Grid de Servidores
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 1050 ? 3 : (constraints.maxWidth > 650 ? 2 : 1);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.servers.length + 1, // +1 para o cartão de criar
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 2.3,
              ),
              itemBuilder: (context, index) {
                if (index == state.servers.length) {
                  return _buildCreateServerGridCard(context);
                }
                final srv = state.servers[index];
                return _buildServerGridCard(context, state, srv);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildServerGridCard(BuildContext context, AppState state, Server server) {
    final isActive = server.id == state.activeServerId;
    final textChannelsCount = server.channels.where((c) => c.type == ChannelType.text).length;
    final voiceChannelsCount = server.channels.where((c) => c.type == ChannelType.voice).length;

    Color badgeColor = HudTheme.green;
    if (server.colorHex.isNotEmpty) {
      try {
        badgeColor = Color(int.parse('0xFF${server.colorHex}'));
      } catch (_) {}
    }

    final initials = server.name.length >= 2 ? server.name.substring(0, 2).toUpperCase() : server.name.toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HudTheme.bgSidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? badgeColor : HudTheme.divider,
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top Row: Badge + Nome + Ações
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.description.isNotEmpty ? server.description : 'Convite: ${server.inviteCode}',
                      style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Menu de Opções / Excluir
              if (server.isCustom)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: HudTheme.textMuted, size: 18),
                  tooltip: 'Remover Servidor',
                  onPressed: () => _confirmDeleteServer(context, state, server),
                ),
            ],
          ),

          // Bottom Row: Estatísticas + Botão Entrar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildMiniBadge(Icons.tag, '$textChannelsCount', HudTheme.textMuted),
                  const SizedBox(width: 8),
                  _buildMiniBadge(Icons.volume_up, '$voiceChannelsCount', HudTheme.green),
                  const SizedBox(width: 8),
                  // Botão abrir detalhes do convite
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => ServerInviteDialog.show(context, server),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: HudTheme.bgCard,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: HudTheme.divider),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.copy_rounded, size: 10, color: HudTheme.accent),
                          const SizedBox(width: 4),
                          Text(
                            server.inviteCode,
                            style: const TextStyle(color: HudTheme.accent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? HudTheme.bgHover : badgeColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  minimumSize: const Size(64, 28),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: () {
                  state.selectServer(server.id);
                  state.closeHomePage();
                },
                child: Text(
                  isActive ? 'Ativo' : 'Acessar',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreateServerGridCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => CreateServerDialog.show(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HudTheme.bgSidebar.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HudTheme.green.withValues(alpha: 0.4), style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: HudTheme.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: HudTheme.green, size: 24),
            ),
            const SizedBox(width: 14),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Criar Novo Servidor',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                SizedBox(height: 2),
                Text(
                  'Templates rápidos para squad e voz',
                  style: TextStyle(color: HudTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniBadge(IconData icon, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: HudTheme.bgCard,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(count, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- SEÇÃO: SALAS DE VOZ RECOMENDADAS ---
  Widget _buildVoiceLoungesCard(BuildContext context, AppState state) {
    final allVoiceChannels = <Map<String, dynamic>>[];
    for (final srv in state.servers) {
      for (final ch in srv.channels) {
        if (ch.type == ChannelType.voice) {
          allVoiceChannels.add({'server': srv, 'channel': ch});
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HudTheme.bgSidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HudTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded, color: HudTheme.accent, size: 20),
              const SizedBox(width: 10),
              const Text(
                'Salas de Voz Disponíveis',
                style: TextStyle(color: HudTheme.textHeader, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: HudTheme.bgCard,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Opus 48kHz HD', style: TextStyle(color: HudTheme.textMuted, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (allVoiceChannels.isEmpty)
            const Text('Nenhuma sala de voz encontrada.', style: TextStyle(color: HudTheme.textMuted, fontSize: 13))
          else
            ...allVoiceChannels.take(5).map((item) {
              final Server srv = item['server'];
              final Channel ch = item['channel'];
              final isConnected = state.connectedVoiceChannelId == ch.id;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isConnected ? HudTheme.green.withValues(alpha: 0.1) : HudTheme.bgCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isConnected ? HudTheme.green.withValues(alpha: 0.35) : HudTheme.divider),
                ),
                child: Row(
                  children: [
                    Icon(Icons.volume_up_rounded, color: isConnected ? HudTheme.green : HudTheme.textMuted, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ch.name,
                            style: TextStyle(
                              color: isConnected ? Colors.white : HudTheme.textNormal,
                              fontWeight: isConnected ? FontWeight.bold : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Servidor: ${srv.name}  •  Limite: ${ch.userLimit} membros',
                            style: const TextStyle(color: HudTheme.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected ? HudTheme.bgHover : HudTheme.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(64, 30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () {
                        state.selectServer(srv.id);
                        state.selectChannel(ch.id);
                        if (!isConnected) {
                          state.connectVoice(ch.id);
                        }
                        state.closeHomePage();
                      },
                      child: Text(
                        isConnected ? 'Conectado' : 'Entrar',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // --- SEÇÃO: STATUS DO SISTEMA HUD ---
  Widget _buildSystemStatusCard(AppState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HudTheme.bgSidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HudTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.speed_rounded, color: HudTheme.accent, size: 20),
              SizedBox(width: 10),
              Text(
                'Status do Sistema & Desempenho (v${HudTheme.appVersion})',
                style: TextStyle(color: HudTheme.textHeader, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatusPill(
                title: 'LiveKit RTC Voice Engine',
                status: state.connectedVoiceChannelId != null ? 'Conectado (RTC)' : 'Pronto',
                isGood: true,
              ),
              const SizedBox(width: 12),
              _buildStatusPill(
                title: 'Mensageria EMQX MQTT',
                status: 'Ativo (TCP 1883 / WSS)',
                isGood: true,
              ),
              const SizedBox(width: 12),
              _buildStatusPill(
                title: 'Render Inteligente',
                status: 'Modo Eco Streamer Ativo',
                isGood: true,
              ),
              const SizedBox(width: 12),
              _buildStatusPill(
                title: 'Latência do Subsistema',
                status: '< 35ms Ultra Low',
                isGood: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill({required String title, required String status, required bool isGood}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: HudTheme.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: HudTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: HudTheme.textMuted, fontSize: 11)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isGood ? HudTheme.green : HudTheme.yellow,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      color: isGood ? Colors.white : HudTheme.yellow,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- DIALOG: ENTRAR VIA CONVITE ---
  void _showJoinInviteDialog(BuildContext context, AppState state) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgSidebar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: HudTheme.divider),
        ),
        title: Row(
          children: const [
            Icon(Icons.vpn_key_rounded, color: HudTheme.accent, size: 20),
            SizedBox(width: 10),
            Text(
              'Entrar em Servidor',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Insira o código de convite do servidor (ex: papo-a1b2c3d4):',
              style: TextStyle(color: HudTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Código de convite',
                hintStyle: const TextStyle(color: HudTheme.textMuted, fontSize: 13),
                filled: true,
                fillColor: HudTheme.bgCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: HudTheme.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: HudTheme.accent, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isNotEmpty) {
                Navigator.of(ctx).pop();
                final ok = await state.joinServerByInvite(code);
                if (ok && context.mounted) {
                  state.closeHomePage();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: HudTheme.bgSidebar,
                      content: Text('Conectado ao servidor com o código "$code"!'),
                    ),
                  );
                }
              }
            },
            child: const Text('Entrar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- DIALOG: CONFIRMAR EXCLUSÃO DE SERVIDOR ---
  void _confirmDeleteServer(BuildContext context, AppState state, Server server) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgSidebar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: HudTheme.divider),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: HudTheme.red, size: 20),
            SizedBox(width: 10),
            Text('Remover Servidor', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Tem certeza que deseja remover o servidor "${server.name}"? Esta ação não pode ser desfeita.',
          style: const TextStyle(color: HudTheme.textNormal, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: HudTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: HudTheme.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await state.deleteServer(server.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: HudTheme.bgSidebar,
                    content: Text('Servidor "${server.name}" removido.'),
                  ),
                );
              }
            },
            child: const Text('Remover', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
