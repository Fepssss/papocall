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
      body: Row(
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
    );
  }
}
