import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/channel.dart';
import 'providers/app_state.dart';
import 'theme/hud_theme.dart';
import 'screens/auth_screen.dart';
import 'services/sound_service.dart';
import 'widgets/app_left_panel.dart';
import 'widgets/chat_view.dart';
import 'widgets/home_page_view.dart';
import 'widgets/members_sidebar.dart';
import 'widgets/voice_lounge_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
          return state.isAuthenticated ? const MainScreen() : const AuthScreen();
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

    return Scaffold(
      body: Column(
        children: [
          // Faixa de status da malha de sincronização. Enquanto ela estiver
          // fora do ar, nenhuma mensagem, presença ou solicitação de amizade
          // entra ou sai — e o app precisa dizer isso em vez de parecer normal.
          if (!state.isNetworkOnline) const _OfflineBanner(),
          Expanded(
            child: Row(
              children: [
                // 1. Painel Esquerdo Unificado (312px = Server Rail + Channels/Home Sidebar + Perfil e Áudio)
                const AppLeftPanel(),

                // 2. Área Central Principal (Home de Amigos, Voice Lounge ou Chat de Texto)
                if (state.isHomePageActive)
                  const Expanded(child: HomePageView())
                else if (isVoiceActive)
                  const VoiceLoungeView()
                else
                  const ChatView(),

                // 3. Barra Lateral de Membros Online (oculta na Home)
                if (!state.isHomePageActive) const MembersSidebar(),
              ],
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
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
          SizedBox(width: 10),
          Text(
            'Sem conexão com a rede do PapoCall — mensagens, presença e solicitações estão pausadas. Reconectando...',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
