import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/channel.dart';
import 'providers/app_state.dart';
import 'theme/hud_layout.dart';
import 'theme/hud_theme.dart';
import 'screens/auth_screen.dart';
import 'services/sound_service.dart';
import 'utils/app_log.dart';
import 'widgets/app_left_panel.dart';
import 'widgets/chat_view.dart';
import 'widgets/home_page_view.dart';
import 'widgets/members_sidebar.dart';
import 'widgets/modals/update_dialog.dart';
import 'widgets/voice_lounge_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Sem isto, um erro fora do fluxo esperado ia para o nada: o aplicativo
  // travava ou fechava sem deixar rastro e não havia o que investigar. O log é
  // o único lugar onde a causa sobrevive ao fechamento da janela.
  FlutterError.onError = (detalhes) {
    FlutterError.presentError(detalhes);
    AppLog.write('Erro', 'na interface: ${detalhes.exception}\n${detalhes.stack}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (erro, trilha) {
    // Um assíncrono perdido não vale fechar uma chamada de voz em andamento,
    // então fica registrado em vez de derrubar o processo.
    AppLog.write('Erro', 'não tratado: $erro\n$trilha');
    return true;
  };
  SoundService.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const PapoCallApp(),
    ),
  );
}

class PapoCallApp extends StatelessWidget {
  const PapoCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PapoCall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: HudTheme.bgChat,
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      // Uma só alavanca para a HUD inteira: o texto escala pela largura da
      // janela, e com ele sobram as colunas de largura fixa. Fica no builder do
      // MaterialApp porque alcança também os diálogos, abertos por cima da tela.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
              HudLayout.of(context).escala * media.textScaler.scale(1),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: Consumer<AppState>(
        builder: (context, state, _) {
          if (state.isCheckingAuth) {
            return const Scaffold(
              backgroundColor: Color(0xFF0B0E14),
              body: Center(
                child: CircularProgressIndicator(color: HudTheme.green),
              ),
            );
          }
          // Na tela de entrada também se atualiza: era justamente ali que
          // ficava preso quem teve o login derrubado por um token velho.
          return state.isAuthenticated
              ? const MainScreen()
              : Column(
                  children: [
                    if (state.atualizacaoDisponivel != null)
                      const _UpdateBanner(),
                    const Expanded(child: AuthScreen()),
                  ],
                );
        },
      ),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isVoiceActive = state.activeChannel?.type == ChannelType.voice;

    // A tela cheia da live é a janela inteira: as duas colunas fixas saem, e o
    // Esc devolve o que era antes. Sem sair dela, nada mais na tela funciona.
    final aoVivoEmTelaCheia = state.activeScreenShareTrack != null &&
        state.isWatchingScreenShare &&
        !state.isHomePageActive &&
        isVoiceActive &&
        state.modoDeExibicao == ModoDeExibicao.telaCheia;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (state.modoDeExibicao != ModoDeExibicao.normal) {
            state.definirModoDeExibicao(ModoDeExibicao.normal);
          }
        },
      },
      child: Scaffold(
        body: Column(
          children: [
            // Faixa de status da malha de sincronização. Enquanto ela estiver
            // fora do ar, nenhuma mensagem, presença ou solicitação de amizade
            // entra ou sai — e o app precisa dizer isso em vez de parecer normal.
            if (!state.isNetworkOnline && !aoVivoEmTelaCheia) const _OfflineBanner(),
            if (state.atualizacaoDisponivel != null && !aoVivoEmTelaCheia)
              const _UpdateBanner(),
            Expanded(
              child: Row(
                children: [
                  // 1. Painel Esquerdo Unificado (rail de servidores + canais +
                  //    perfil e áudio), com a largura acompanhando a janela.
                  if (!aoVivoEmTelaCheia) const AppLeftPanel(),

                  // 2. Área Central Principal (Home de Amigos, Voice Lounge ou Chat de Texto)
                  if (state.isHomePageActive)
                    const Expanded(child: HomePageView())
                  else if (isVoiceActive)
                    const VoiceLoungeView()
                  else
                    const ChatView(),

                  // 3. Barra Lateral de Membros Online (oculta na Home, e cede a
                  //    vez primeiro quando a janela fica estreita).
                  if (!state.isHomePageActive &&
                      !aoVivoEmTelaCheia &&
                      HudLayout.of(context).mostraBarraMembros)
                    const MembersSidebar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final manifesto = state.atualizacaoDisponivel;
    if (manifesto == null) return const SizedBox.shrink();

    final texto = state.baixandoAtualizacao
        ? 'Baixando a versão ${manifesto.version}...'
        : 'Nova versão disponível: ${manifesto.version}';

    return Container(
      width: double.infinity,
      color: const Color(0xFF15243A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.system_update_alt_rounded,
              size: 16, color: HudTheme.accent),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: HudTheme.textNormal,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: HudTheme.accent,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 26),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: state.baixandoAtualizacao
                ? null
                : () => UpdateDialog.show(context),
            child: const Text(
              'Ver',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF7F1D1D),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'Sem conexão com a rede do PapoCall — mensagens, presença e solicitações estão pausadas. Reconectando...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
