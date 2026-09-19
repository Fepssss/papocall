import 'package:flutter/material.dart';

/// Tema HUD Sóbrio para o PapoCall.
/// Design tático, limpo e dedicado, focado em alta legibilidade e ergonomia visual.
class HudTheme {
  // Versão Oficial da Aplicação
  static const String appVersion = '1.0.0o';

  // Painéis e Superfícies
  static const Color bgServerRail = Color(0xFF0F1117);
  static const Color bgSidebar = Color(0xFF141821);
  static const Color bgChat = Color(0xFF181C26);
  static const Color bgCard = Color(0xFF1E2330);
  static const Color bgProfile = Color(0xFF11141C);
  static const Color bgInput = Color(0xFF131720);
  static const Color bgHover = Color(0xFF232938);
  static const Color bgActive = Color(0xFF283042);

  // Cores de Acento (Sóbrias e Refinadas)
  static const Color accent = Color(0xFF38BDF8); // Azul Aço / Ice Blue sóbrio
  static const Color accentHover = Color(0xFF0284C7);
  static const Color green = Color(0xFF22C55E); // Verde natural para voz ativa e status
  static const Color greenHover = Color(0xFF16A34A);
  static const Color red = Color(0xFFEF4444); // Vermelho sóbrio para mudo e desligamento
  static const Color yellow = Color(0xFFF59E0B); // Âmbar para ausente

  // Compatibilidade semântica
  static const Color blurple = accent;
  static const Color blurpleHover = accentHover;

  // Indicadores de Status
  static const Color statusOnline = Color(0xFF22C55E);
  static const Color statusIdle = Color(0xFFF59E0B);
  static const Color statusDnd = Color(0xFFEF4444);
  static const Color statusOffline = Color(0xFF64748B);

  // Tipografia
  static const Color textHeader = Color(0xFFF8FAFC);
  static const Color textNormal = Color(0xFFCBD5E1);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textInteractive = Color(0xFF94A3B8);

  // Linhas e Delimitadores HUD
  static const Color divider = Color(0xFF242C3D);
  static const Color borderSubtle = Color(0xFF1F2635);
}
