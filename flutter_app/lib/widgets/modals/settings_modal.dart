import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/app_state.dart';
import '../../services/sound_service.dart';
import '../../theme/hud_theme.dart';
import '../retrato_usuario.dart';
import 'audio_devices_panel.dart';

enum SettingsTab {
  account,
  privacy,
  notifications,
  voiceAudio,
  updates,
}

class SettingsModal extends StatefulWidget {
  const SettingsModal({super.key, this.initialTab = SettingsTab.account});

  /// Aba aberta ao mostrar o modal. O menu de contexto do servidor usa para
  /// levar o usuário direto à configuração que ele pediu.
  final SettingsTab initialTab;

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  late SettingsTab _selectedTab = widget.initialTab;

  late TextEditingController _displayNameController;
  late TextEditingController _usernameController;

  /// A foto escolhida é lida, recortada e comprimida num isolate, e isso leva
  /// um instante: o botão se fecha enquanto dura para a pessoa não escolher
  /// duas imagens e aplicar a primeira por engano.
  bool _escolhendoFoto = false;

  Future<void> _escolherFoto(AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _escolhendoFoto = true);
    try {
      final escolhida = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // GIF entra na lista de propósito: é o formato que permite um perfil
        // que se mexe, e o `FileType.image` de alguns sistemas o deixa de fora.
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif'],
        withData: true,
        dialogTitle: 'Escolher foto de perfil',
      );
      final bytes = (escolhida == null || escolhida.files.isEmpty)
          ? null
          : escolhida.files.first.bytes;
      if (bytes == null) return;
      final erro = await state.definirFotoDePerfil(bytes);
      if (erro != null) {
        messenger.showSnackBar(SnackBar(
          content: Text(erro),
          backgroundColor: HudTheme.red,
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Não deu para abrir essa imagem: $e'),
        backgroundColor: HudTheme.red,
      ));
    } finally {
      if (mounted) setState(() => _escolhendoFoto = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _displayNameController = TextEditingController(text: state.currentUser.displayName);
    _usernameController = TextEditingController(
      text: state.currentUser.username.replaceAll('@', '').trim(),
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: min(880.0, MediaQuery.sizeOf(context).width - 64),
        height: min(620.0, MediaQuery.sizeOf(context).height - 96),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1017),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E2430), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 28,
              spreadRadius: 4,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // BARRA LATERAL ESQUERDA (NAVEGAÇÃO)
            Container(
              width: 240,
              color: const Color(0xFF0B0E14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: HudTheme.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'CONFIGURAÇÕES',
                          style: TextStyle(
                            color: HudTheme.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // A navegação é rolável de propósito: numa janela baixa os
                  // botões não cabem em pé, e antes eles transbordavam para
                  // fora do cartão em vez de ceder espaço.
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildNavCategoryHeader('CONFIGURAÇÕES DE USUÁRIO'),
                                const SizedBox(height: 4),
                                _buildTabButton(
                                  tab: SettingsTab.account,
                                  icon: Icons.person_outline_rounded,
                                  label: 'Conta',
                                ),
                                _buildTabButton(
                                  tab: SettingsTab.privacy,
                                  icon: Icons.shield_outlined,
                                  label: 'Dados e privacidade',
                                ),
                                _buildTabButton(
                                  tab: SettingsTab.notifications,
                                  icon: Icons.volume_up_rounded,
                                  label: 'Sons de aviso',
                                ),
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Divider(color: Color(0xFF1E2330), height: 1),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildNavCategoryHeader('CONFIGURAÇÕES DO APP'),
                                const SizedBox(height: 4),
                                _buildTabButton(
                                  tab: SettingsTab.voiceAudio,
                                  icon: Icons.mic_none_outlined,
                                  label: 'Voz e Áudio',
                                ),
                                _buildTabButton(
                                  tab: SettingsTab.updates,
                                  icon: Icons.system_update_alt_rounded,
                                  label: 'Atualizações',
                                  badge: state.atualizacaoDisponivel != null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(color: Color(0xFF1E2330), height: 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: InkWell(
                      onTap: () async {
                        final nav = Navigator.of(context);
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF131722),
                            title: const Text('Encerrar Sessão', style: TextStyle(color: Colors.white, fontSize: 16)),
                            content: const Text(
                              'Deseja realmente sair da sua conta no PapoCall?',
                              style: TextStyle(color: Color(0xFF9BA3AF), fontSize: 13),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9BA3AF))),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('Sair', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );

                        if (!mounted) return;
                        if (confirm == true) {
                          nav.pop();
                          await state.logout();
                        }
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.logout_rounded, size: 17, color: Colors.redAccent),
                            SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Sair da Conta',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      'PapoCall v${HudTheme.appVersion} • Tático HUD',
                      style: const TextStyle(
                        color: Color(0xFF475267),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, color: const Color(0xFF1B202C)),
            // PAINEL DIREITO (CONTEÚDO)
            Expanded(
              child: Container(
                color: const Color(0xFF121620),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(28, 20, 20, 16),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFF1E2330), width: 1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(_getTabIcon(_selectedTab), color: HudTheme.green, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                _getTabTitle(_selectedTab),
                                style: const TextStyle(
                                  color: HudTheme.textHeader,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B202C),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF282F40)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'ESC',
                                    style: TextStyle(
                                      color: HudTheme.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.close, color: HudTheme.textMuted, size: 15),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(28),
                        child: _buildTabContent(state),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 10, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF5A667E),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required SettingsTab tab,
    required IconData icon,
    required String label,
    bool badge = false,
  }) {
    final isSelected = _selectedTab == tab;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _selectedTab = tab),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1A2130) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? HudTheme.green.withValues(alpha: 0.35) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected ? HudTheme.green : const Color(0xFF8A98B0),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? HudTheme.textHeader : const Color(0xFF8A98B0),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge)
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: HudTheme.accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getTabIcon(SettingsTab tab) {
    switch (tab) {
      case SettingsTab.account:
        return Icons.person_outline_rounded;
      case SettingsTab.privacy:
        return Icons.shield_outlined;
      case SettingsTab.notifications:
        return Icons.volume_up_rounded;
      case SettingsTab.voiceAudio:
        return Icons.mic_none_outlined;
      case SettingsTab.updates:
        return Icons.system_update_alt_rounded;
    }
  }

  String _getTabTitle(SettingsTab tab) {
    switch (tab) {
      case SettingsTab.account:
        return 'Minha Conta';
      case SettingsTab.privacy:
        return 'Dados e Privacidade';
      case SettingsTab.notifications:
        return 'Sons de aviso';
      case SettingsTab.voiceAudio:
        return 'Voz e Transmissão de Áudio';
      case SettingsTab.updates:
        return 'Atualizações';
    }
  }

  Widget _buildTabContent(AppState state) {
    switch (_selectedTab) {
      case SettingsTab.account:
        return _buildAccountTab(state);
      case SettingsTab.privacy:
        return _buildPrivacyTab();
      case SettingsTab.notifications:
        return _buildNotificationsTab(state);
      case SettingsTab.voiceAudio:
        return _buildVoiceAudioTab(state);
      case SettingsTab.updates:
        return _buildUpdatesTab(state);
    }
  }

  Widget _buildAccountTab(AppState state) {
    final user = state.currentUser;
    final sessionUser = state.currentSession?.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF161B26),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF222838)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  RetratoUsuario(
                    avatar: user.avatar,
                    iniciais: user.initials,
                    raio: 34,
                    corQuandoSemFoto: HudTheme.blurple,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 84,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: HudTheme.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _escolhendoFoto ? null : () => _escolherFoto(state),
                      child: Text(
                        _escolhendoFoto
                            ? '...'
                            : (user.avatar.isEmpty ? 'Foto ou GIF' : 'Trocar'),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (user.avatar.isNotEmpty)
                    SizedBox(
                      width: 84,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: HudTheme.red,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => state.removerFotoDePerfil(),
                        child: const Text('Remover', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          user.displayNameOrUsername,
                          style: const TextStyle(
                            color: HudTheme.textHeader,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: HudTheme.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: HudTheme.green.withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'OFICIAL',
                            style: TextStyle(color: HudTheme.green, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${user.handle}${sessionUser != null ? "  •  ${sessionUser.email}" : ""}',
                      style: const TextStyle(color: HudTheme.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          sessionUser?.emailVerified == true ? Icons.check_circle_outline : Icons.info_outline,
                          size: 14,
                          color: sessionUser?.emailVerified == true ? HudTheme.green : Colors.amber,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          sessionUser?.emailVerified == true ? 'E-mail Verificado' : 'Conta Ativa',
                          style: TextStyle(
                            color: sessionUser?.emailVerified == true ? HudTheme.green : Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('NOME DE EXIBIÇÃO', 'Como outros membros verão você nos canais e salas.'),
        const SizedBox(height: 8),
        TextField(
          controller: _displayNameController,
          style: const TextStyle(color: HudTheme.textNormal),
          decoration: InputDecoration(
            hintText: 'Ex: Felipe Miotti',
            hintStyle: const TextStyle(color: HudTheme.textMuted),
            filled: true,
            fillColor: const Color(0xFF0F121A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF222A3A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF222A3A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: HudTheme.green, width: 1.2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionHeader('TAG / @USERNAME ÚNICO', 'Identificador imutável usado para menções e conexões.'),
        const SizedBox(height: 8),
        TextField(
          controller: _usernameController,
          style: const TextStyle(color: HudTheme.textNormal),
          decoration: InputDecoration(
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 14, right: 6),
              child: Text(
                '@',
                style: TextStyle(color: HudTheme.green, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 0),
            hintText: 'tag_do_usuario (ex: feps)',
            hintStyle: const TextStyle(color: HudTheme.textMuted),
            filled: true,
            fillColor: const Color(0xFF0F121A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF222A3A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF222A3A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: HudTheme.green, width: 1.2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('STATUS DE PRESENÇA', 'Altere como você aparece na lista de membros.'),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildStatusCard(state, UserStatus.online, 'Online', HudTheme.statusOnline),
            const SizedBox(width: 10),
            _buildStatusCard(state, UserStatus.idle, 'Ausente', HudTheme.statusIdle),
            const SizedBox(width: 10),
            _buildStatusCard(state, UserStatus.dnd, 'Não Perturbe', HudTheme.statusDnd),
          ],
        ),
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.check, size: 17),
            label: const Text('Salvar Alterações', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await state.setDisplayName(_displayNameController.text);
              await state.setUsername(_usernameController.text.trim().replaceAll('@', '').toLowerCase());
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFF161B26),
                  content: Text('Configurações de perfil atualizadas com sucesso!'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoCard(
          icon: Icons.lock_outline_rounded,
          iconColor: HudTheme.green,
          title: 'Criptografia Ponta a Ponta (E2EE)',
          description:
              'Todas as mensagens e áudio nos servidores do PapoCall utilizam criptografia robusta (AES-256-GCM derivado do código de convite via PBKDF2 e WebRTC seguro). Nem intermediários nem brokers têm acesso às suas conversas.',
          badge: 'ATIVO',
          badgeColor: HudTheme.green,
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          icon: Icons.cloud_off_rounded,
          iconColor: const Color(0xFF60A5FA),
          title: 'Política de Telemetria Zero',
          description:
              'O PapoCall não rastreia seu comportamento, não envia relatórios em segundo plano e não monetiza seus dados. A infraestrutura atua estritamente como ponte de conexão.',
          badge: 'RESPEITADO',
          badgeColor: const Color(0xFF60A5FA),
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          icon: Icons.shield_moon_outlined,
          iconColor: const Color(0xFFA78BFA),
          title: 'Transporte Cifrado Obrigatório',
          description:
              'O tráfego de rede utiliza TLS na porta 8883 e WebRTC sobre DTLS/SRTP. Conexões inseguras ou em texto puro são recusadas por projeto.',
          badge: 'TLS 1.3',
          badgeColor: const Color(0xFFA78BFA),
        ),
      ],
    );
  }

  /// As duas chaves daqui controlam o `SoundService` de verdade, pelo
  /// caminho [`AppState.definirSomDeChamada`] -> `SoundService.definirSons`,
  /// e sobrevivem ao reiniciar porque vão no settings.json. O botão de teste
  /// ignora a chave de propósito: ele existe para confirmar que o áudio sai
  /// mesmo, inclusive com os avisos automáticos calados.
  Widget _buildNotificationsTab(AppState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSwitchTile(
          title: 'Efeitos Sonoros de Entrada e Saída de Voz',
          subtitle: 'Reproduz bipes táticos HUD quando você ou um participante ingressa ou sai da sala.',
          value: state.somDeChamada,
          onChanged: (val) => state.definirSomDeChamada(val),
          action: IconButton(
            icon: const Icon(Icons.volume_up_rounded, color: HudTheme.green, size: 20),
            tooltip: 'Testar som de entrada',
            onPressed: () => SoundService.testar(SoundType.joinCall),
          ),
        ),
        const SizedBox(height: 14),
        _buildSwitchTile(
          title: 'Sons de Compartilhamento de Tela',
          subtitle: 'Alerta sonoro sutil quando uma transmissão de tela for iniciada ou encerrada na chamada.',
          value: state.somDeCompartilhamento,
          onChanged: (val) => state.definirSomDeCompartilhamento(val),
        ),
      ],
    );
  }

  /// Aba de atualizações: o estado real da última consulta e os dois botões
  /// que existem para servir a ela.
  ///
  /// Não há "procure por novidades" decorativo aqui — o que aparece é o que o
  /// servidor respondeu, inclusive quando a resposta foi um erro.
  Widget _buildUpdatesTab(AppState state) {
    final manifesto = state.atualizacaoDisponivel;
    final ocupado = state.verificandoAtualizacao || state.baixandoAtualizacao;

    final String situacao;
    final Color corSituacao;
    if (state.erroAoVerificarAtualizacao != null) {
      situacao = state.erroAoVerificarAtualizacao!;
      corSituacao = HudTheme.red;
    } else if (state.verificandoAtualizacao) {
      situacao = 'Consultando o servidor de atualizações...';
      corSituacao = HudTheme.textMuted;
    } else if (manifesto != null) {
      situacao = 'Versão ${manifesto.version} pronta para instalar.';
      corSituacao = HudTheme.accent;
    } else if (state.atualizacoesConferidas) {
      situacao = 'Você está na versão mais recente.';
      corSituacao = HudTheme.green;
    } else {
      situacao = 'Ainda não conferimos hoje.';
      corSituacao = HudTheme.textMuted;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF222838)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: HudTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.system_update_alt_rounded,
                    color: HudTheme.accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versão instalada: ${HudTheme.appVersion}',
                      style: const TextStyle(
                        color: HudTheme.textHeader,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      situacao,
                      style: TextStyle(
                          color: corSituacao, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (manifesto != null && manifesto.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'O QUE HÁ DE NOVO',
            style: TextStyle(
              color: HudTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            manifesto.notes.trim(),
            style: const TextStyle(
                color: HudTheme.textNormal, fontSize: 12.5, height: 1.5),
          ),
        ],
        if (state.baixandoAtualizacao) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: state.progressoDoDownload,
            minHeight: 6,
            backgroundColor: const Color(0xFF1E2330),
            valueColor: const AlwaysStoppedAnimation(HudTheme.green),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: HudTheme.textNormal,
                side: const BorderSide(color: Color(0xFF222838)),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Verificar agora', style: TextStyle(fontSize: 12)),
              onPressed: ocupado ? null : () => state.verificarAtualizacao(),
            ),
            if (manifesto != null)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HudTheme.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF1E2330),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text(
                  state.baixandoAtualizacao
                      ? 'Baixando...'
                      : 'Atualizar para ${manifesto.version}',
                  style:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: ocupado || state.connectedVoiceChannelId != null
                    ? null
                    : () => state.baixarEInstalarAtualizacao(),
              ),
          ],
        ),
        if (state.connectedVoiceChannelId != null) ...[
          const SizedBox(height: 12),
          const Text(
            'Saia da chamada de voz para atualizar: reiniciar o aplicativo no '
            'meio da conversa derruba a sala para todo mundo.',
            style: TextStyle(
                color: HudTheme.textMuted, fontSize: 11.5, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _buildVoiceAudioTab(AppState state) {
    final isConnected = state.connectedVoiceChannelId != null;

    Widget linhaProcessador({
      required String title,
      required String subtitle,
      required bool value,
      required Future<void> Function(bool) definir,
    }) {
      return _buildSwitchTile(
        title: title,
        subtitle: subtitle,
        value: value,
        // Republicar a faixa é o que faz a chave pegar numa call em andamento:
        // as quatro vão como constraint no instante em que o microfone nasce.
        onChanged: (val) async {
          await definir(val);
          await state.voiceService.aplicarDispositivosEscolhidos();
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B26),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF222838)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: HudTheme.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.wifi_tethering_rounded, color: HudTheme.green, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Motor WebRTC: LiveKit Cloud HD',
                      style: TextStyle(color: HudTheme.textHeader, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isConnected
                          ? 'Conectado no canal: ${state.connectedVoiceChannelId}'
                          : 'Pronto para conexões de voz de baixa latência.',
                      style: TextStyle(
                        color: isConnected ? HudTheme.green : HudTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: HudTheme.green,
                  side: const BorderSide(color: HudTheme.green),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.volume_up, size: 16),
                label: const Text('Testar Áudio'),
                onPressed: () => SoundService.testar(SoundType.joinCall),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const AudioDevicesPanel(),
        const SizedBox(height: 20),
        // As quatro chaves abaixo são as únicas de processamento de microfone
        // que o caminho nativo do Windows lê. As outras opções que o
        // AudioCaptureOptions oferece — os modos, o voiceIsolation e a detecção
        // de digitação — são descartadas no desktop, então não têm linha aqui.
        linhaProcessador(
          title: 'Supressão de ruído de fundo',
          subtitle:
              'Filtra cliques de teclado, vento e estática antes da sua voz subir. Em nível alto '
              'o WebRTC deixa a voz oca, e é aí que ela começa a soar como rádio.',
          value: state.noiseSuppression,
          definir: state.definirSupressaoDeRuido,
        ),
        linhaProcessador(
          title: 'Cancelamento de eco',
          subtitle:
              'Tira do microfone o que está saindo no alto-falante. Com fone no ouvido não há eco '
              'para cancelar, e o filtro pode afinar a voz — vale desligar se você sempre usa fone.',
          value: state.echoCancellation,
          definir: state.definirCancelamentoDeEco,
        ),
        linhaProcessador(
          title: 'Ganho automático',
          subtitle:
              'Aperta os fortes e levanta os fracos para o volume da sua voz ficar estável para os '
              'outros. É o que mais soa como rádio de pilha quando trabalha demais.',
          value: state.autoGainControl,
          definir: state.definirGanhoAutomatico,
        ),
        linhaProcessador(
          title: 'Filtro passa-altas',
          subtitle:
              'Corta o ronco grave — mesa vibrando, ar-condicionado, vento. Tira corpo da voz, então '
              'só vale ligar se esse ronco existir.',
          value: state.highPassFilter,
          definir: state.definirFiltroPassaAltas,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: HudTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF718096), fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildStatusCard(AppState state, UserStatus status, String label, Color color) {
    final isSelected = state.currentUser.status == status;

    return Expanded(
      child: InkWell(
        onTap: () => state.setStatus(status),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E2638) : const Color(0xFF141822),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? color : const Color(0xFF252D3E),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? HudTheme.textHeader : HudTheme.textMuted,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String badge,
    required Color badgeColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF222838)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: HudTheme.textHeader, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(color: Color(0xFF8896AB), fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF222838)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: HudTheme.textHeader, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF7D8B9F), fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            action,
            const SizedBox(width: 10),
          ],
          Switch(
            value: value,
            activeThumbColor: HudTheme.green,
            activeTrackColor: HudTheme.green.withValues(alpha: 0.35),
            inactiveThumbColor: const Color(0xFF718096),
            inactiveTrackColor: const Color(0xFF202634),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
