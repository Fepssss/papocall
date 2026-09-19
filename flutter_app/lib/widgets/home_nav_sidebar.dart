import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../providers/app_state.dart';
import '../theme/hud_theme.dart';
import 'modals/create_server_dialog.dart';
import 'modals/add_friend_dialog.dart';

/// Barra lateral de navegação da Home (240px de largura).
/// Fica ao lado do ServerRail (72px) quando a Home está ativa, mantendo a UserProfileBar
/// no rodapé unificado de 312px.
class HomeNavSidebar extends StatelessWidget {
  const HomeNavSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final onlineCount = state.friendsWithLiveStatus
        .where((f) => f.status != UserStatus.offline)
        .length;
    final pendingCount = state.pendingRequestsCount;

    return Container(
      color: HudTheme.bgSidebar,
      child: Column(
        children: [
          // Cabeçalho da Home
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: HudTheme.divider, width: 1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: HudTheme.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.home_rounded, color: HudTheme.green, size: 16),
                ),
                const SizedBox(width: 10),
                const Text(
                  'INÍCIO',
                  style: TextStyle(
                    color: HudTheme.textHeader,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // Itens de Navegação da Home
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              children: [
                // Item Ativo: Amigos
                InkWell(
                  onTap: () {
                    if (!state.isHomePageActive) {
                      state.openHomePage();
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: HudTheme.bgActive,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: HudTheme.green.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.people_alt_rounded, color: HudTheme.green, size: 20),
                        const SizedBox(width: 12),
                        const Text(
                          'Amigos',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        if (pendingCount > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: HudTheme.green,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.mail_rounded, size: 10, color: Colors.black),
                                const SizedBox(width: 3),
                                Text(
                                  '$pendingCount',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (onlineCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: HudTheme.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: HudTheme.green.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              '$onlineCount',
                              style: const TextStyle(
                                color: HudTheme.green,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Atalho rápido: Adicionar Amigo
                InkWell(
                  onTap: () => AddFriendDialog.show(context),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: HudTheme.bgCard,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: HudTheme.divider),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.person_add_alt_1_rounded, color: HudTheme.accent, size: 18),
                        SizedBox(width: 12),
                        Text(
                          'Adicionar Amigo',
                          style: TextStyle(
                            color: HudTheme.textNormal,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Categoria: Servidores
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SEUS SERVIDORES',
                        style: TextStyle(
                          color: HudTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      InkWell(
                        onTap: () => CreateServerDialog.show(context),
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.add, color: HudTheme.textMuted, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Lista compacta de servidores
                ...state.servers.map((srv) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: InkWell(
                      onTap: () {
                        state.selectServer(srv.id);
                        state.closeHomePage();
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: HudTheme.bgHover,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                srv.name.isNotEmpty ? srv.name[0].toUpperCase() : 'S',
                                style: const TextStyle(
                                  color: HudTheme.textNormal,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                srv.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: HudTheme.textNormal,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: HudTheme.textMuted, size: 16),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
