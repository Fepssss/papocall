import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import '../theme/hud_theme.dart';

class ScreenShareDialog extends StatefulWidget {
  const ScreenShareDialog({super.key});

  static Future<String?> show(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => const ScreenShareDialog(),
    );
  }

  @override
  State<ScreenShareDialog> createState() => _ScreenShareDialogState();
}

class _ScreenShareDialogState extends State<ScreenShareDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Map<String, rtc.DesktopCapturerSource> _sources = {};
  rtc.DesktopCapturerSource? _selectedSource;
  final List<StreamSubscription> _subscriptions = [];
  bool _isLoading = true;
  String _selectedQuality = '1080p';
  String _selectedFps = '30 FPS';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    _loadSources();
    _setupCapturerListeners();
  }

  void _setupCapturerListeners() {
    _subscriptions.add(
      rtc.desktopCapturer.onAdded.stream.listen((source) {
        if (!mounted) return;
        setState(() {
          _sources[source.id] = source;
        });
      }),
    );

    _subscriptions.add(
      rtc.desktopCapturer.onRemoved.stream.listen((source) {
        if (!mounted) return;
        setState(() {
          _sources.remove(source.id);
          if (_selectedSource?.id == source.id) {
            _selectedSource = null;
          }
        });
      }),
    );

    _subscriptions.add(
      rtc.desktopCapturer.onThumbnailChanged.stream.listen((source) {
        if (!mounted) return;
        setState(() {
          _sources[source.id] = source;
        });
      }),
    );
  }

  Future<void> _loadSources() async {
    try {
      final list = await rtc.desktopCapturer.getSources(
        types: [rtc.SourceType.Screen, rtc.SourceType.Window],
      );
      if (!mounted) return;
      setState(() {
        _sources.clear();
        for (final s in list) {
          _sources[s.id] = s;
        }
        _isLoading = false;
        // Selecionar primeira tela por padrão se disponível
        final screens = _sources.values.where((s) => s.type == rtc.SourceType.Screen);
        if (screens.isNotEmpty && _selectedSource == null) {
          _selectedSource = screens.first;
        }
      });
    } catch (e) {
      debugPrint('Erro ao obter fontes de captura: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = _sources.values.where((s) => s.type == rtc.SourceType.Screen).toList();
    final windows = _sources.values.where((s) => s.type == rtc.SourceType.Window).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Container(
        width: 720,
        height: 560,
        decoration: BoxDecoration(
          color: HudTheme.bgSidebar,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HudTheme.borderSubtle, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top Header
            _buildHeader(context),

            // Tab Bar
            _buildTabBar(screens.length, windows.length),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: HudTheme.green,
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSourcesGrid(screens, isScreen: true),
                        _buildSourcesGrid(windows, isScreen: false),
                      ],
                    ),
            ),

            // Options & Action Footer
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
      decoration: BoxDecoration(
        color: HudTheme.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(bottom: BorderSide(color: HudTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: HudTheme.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HudTheme.green.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.screen_share_rounded, color: HudTheme.green, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Compartilhar Tela',
                style: TextStyle(
                  color: HudTheme.textHeader,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Selecione um monitor ou aplicativo para transmitir aos participantes',
                style: TextStyle(
                  color: HudTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: HudTheme.textMuted, size: 20),
            tooltip: 'Fechar',
            splashRadius: 18,
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(int screenCount, int windowCount) {
    return Container(
      color: HudTheme.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: HudTheme.bgSidebar,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: HudTheme.borderSubtle),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: HudTheme.bgCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: HudTheme.accent.withValues(alpha: 0.4)),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: HudTheme.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.desktop_windows_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text('Telas ($screenCount)'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.apps_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text('Aplicativos ($windowCount)'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesGrid(List<rtc.DesktopCapturerSource> sources, {required bool isScreen}) {
    if (sources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isScreen ? Icons.desktop_access_disabled : Icons.browser_not_supported,
              size: 48,
              color: HudTheme.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              isScreen ? 'Nenhuma tela detectada' : 'Nenhuma janela de aplicativo aberta',
              style: const TextStyle(color: HudTheme.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isScreen ? 2 : 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: isScreen ? 1.45 : 1.15,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        final isSelected = _selectedSource?.id == source.id;

        return _SourceItemCard(
          source: source,
          isSelected: isSelected,
          isScreen: isScreen,
          onTap: () {
            setState(() {
              _selectedSource = source;
            });
          },
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: HudTheme.bgCard,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        border: Border(top: BorderSide(color: HudTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Quality & FPS selectors
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: HudTheme.bgSidebar,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: HudTheme.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQualityChip('720p'),
                const SizedBox(width: 4),
                _buildQualityChip('1080p'),
                Container(
                  width: 1,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: HudTheme.divider,
                ),
                _buildFpsChip('30 FPS'),
                const SizedBox(width: 4),
                _buildFpsChip('60 FPS'),
              ],
            ),
          ),
          const Spacer(),

          // Cancel Button
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: HudTheme.textMuted,
              side: BorderSide(color: HudTheme.borderSubtle),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),

          // Transmit Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedSource != null ? HudTheme.green : HudTheme.divider,
              foregroundColor: Colors.white,
              elevation: _selectedSource != null ? 4 : 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.sensors, size: 18),
            label: const Text(
              'Transmitir ao Vivo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            onPressed: _selectedSource != null
                ? () {
                    Navigator.of(context).pop(_selectedSource!.id);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildQualityChip(String text) {
    final active = _selectedQuality == text;
    return InkWell(
      onTap: () => setState(() => _selectedQuality = text),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? HudTheme.accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? HudTheme.accent : HudTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildFpsChip(String text) {
    final active = _selectedFps == text;
    return InkWell(
      onTap: () => setState(() => _selectedFps = text),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? HudTheme.green.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? HudTheme.green : HudTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _SourceItemCard extends StatefulWidget {
  final rtc.DesktopCapturerSource source;
  final bool isSelected;
  final bool isScreen;
  final VoidCallback onTap;

  const _SourceItemCard({
    required this.source,
    required this.isSelected,
    required this.isScreen,
    required this.onTap,
  });

  @override
  State<_SourceItemCard> createState() => _SourceItemCardState();
}

class _SourceItemCardState extends State<_SourceItemCard> {
  bool _isHovered = false;
  Uint8List? _thumb;
  late StreamSubscription _thumbSub;

  @override
  void initState() {
    super.initState();
    _thumb = widget.source.thumbnail;
    _thumbSub = widget.source.onThumbnailChanged.stream.listen((thumbnail) {
      if (!mounted) return;
      setState(() {
        _thumb = thumbnail;
      });
    });
  }

  @override
  void dispose() {
    _thumbSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: HudTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isSelected
                  ? HudTheme.green
                  : _isHovered
                      ? HudTheme.accent.withValues(alpha: 0.6)
                      : HudTheme.borderSubtle,
              width: widget.isSelected ? 2.0 : 1.0,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: HudTheme.green.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Thumbnail View
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: Colors.black,
                        child: _thumb != null && _thumb!.isNotEmpty
                            ? Image.memory(
                                _thumb!,
                                gaplessPlayback: true,
                                fit: BoxFit.contain,
                              )
                            : Center(
                                child: Icon(
                                  widget.isScreen ? Icons.desktop_windows : Icons.window,
                                  color: HudTheme.textMuted.withValues(alpha: 0.4),
                                  size: 36,
                                ),
                              ),
                      ),

                      // Selection Checkmark Badge
                      if (widget.isSelected)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: HudTheme.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),

                // Name & Type Label
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  color: HudTheme.bgSidebar,
                  child: Row(
                    children: [
                      Icon(
                        widget.isScreen ? Icons.monitor : Icons.web_asset,
                        size: 14,
                        color: widget.isSelected ? HudTheme.green : HudTheme.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
                            color: widget.isSelected ? Colors.white : HudTheme.textNormal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
