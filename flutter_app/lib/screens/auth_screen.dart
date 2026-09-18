import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../theme/hud_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoginTab = true;

  // Controladores de Login
  final _loginIdentifierController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _loginObscurePassword = true;

  // Controladores de Cadastro
  final _regDisplayNameController = TextEditingController();
  final _regUsernameController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  bool _regObscurePassword = true;

  // Estado da checagem de @username em tempo real
  Timer? _debounceTimer;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  List<String> _usernameSuggestions = [];
  String? _usernameFormatError;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _loginIdentifierController.dispose();
    _loginPasswordController.dispose();
    _regDisplayNameController.dispose();
    _regUsernameController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    super.dispose();
  }

  void _onUsernameChanged(String val) {
    _debounceTimer?.cancel();
    final clean = val.replaceAll('@', '').trim().toLowerCase();

    if (clean.isEmpty) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = null;
        _usernameSuggestions = [];
        _usernameFormatError = null;
      });
      return;
    }

    if (clean.length < 3 || clean.length > 20) {
      setState(() {
        _usernameFormatError = 'O @username deve ter entre 3 e 20 caracteres.';
        _isUsernameAvailable = null;
      });
      return;
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(clean)) {
      setState(() {
        _usernameFormatError = 'Apenas letras, números e underline (_).';
        _isUsernameAvailable = null;
      });
      return;
    }

    setState(() {
      _usernameFormatError = null;
      _isCheckingUsername = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final res = await AuthService.checkUsernameAvailable(clean);
        if (mounted) {
          setState(() {
            _isCheckingUsername = false;
            _isUsernameAvailable = res.available;
            _usernameSuggestions = res.suggestions;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isCheckingUsername = false);
        }
      }
    });
  }

  Future<void> _handleLogin() async {
    final id = _loginIdentifierController.text.trim();
    final pass = _loginPasswordController.text;

    if (id.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Por favor, preencha todos os campos.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final state = context.read<AppState>();
      await state.login(identifier: id, password: pass);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleRegister() async {
    final name = _regDisplayNameController.text.trim();
    final username = _regUsernameController.text.replaceAll('@', '').trim().toLowerCase();
    final email = _regEmailController.text.trim();
    final pass = _regPasswordController.text;

    if (name.isEmpty || username.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = 'Preencha todos os campos obrigatórios.');
      return;
    }

    if (_usernameFormatError != null || _isUsernameAvailable == false) {
      setState(() => _errorMessage = 'Por favor, escolha um @username válido e disponível.');
      return;
    }

    if (!RegExp(r'^(?=.*[A-Z])(?=.*\d).{8,}$').hasMatch(pass)) {
      setState(() => _errorMessage = 'A senha deve ter no mínimo 8 caracteres, 1 maiúscula e 1 número.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final state = context.read<AppState>();
      await state.register(
        displayName: name,
        username: username,
        email: email,
        password: pass,
      );
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: HudTheme.bgSidebar,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HudTheme.divider, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 36,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Logo & App Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipOval(
                      child: Image.asset('assets/logo.png', width: 42, height: 42),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      'PapoCall',
                      style: TextStyle(
                        color: HudTheme.textHeader,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _isLoginTab ? 'Bem-vindo de volta! Entre na sua conta.' : 'Crie sua conta e entre na chamada.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HudTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Tab Selector (Entrar / Criar Conta)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: HudTheme.bgCard,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabButton('Entrar', _isLoginTab, () {
                          setState(() {
                            _isLoginTab = true;
                            _errorMessage = null;
                          });
                        }),
                      ),
                      Expanded(
                        child: _buildTabButton('Criar Conta', !_isLoginTab, () {
                          setState(() {
                            _isLoginTab = false;
                            _errorMessage = null;
                          });
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Error Banner
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: HudTheme.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: HudTheme.red.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: HudTheme.red, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: HudTheme.red, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Form Body
                if (_isLoginTab) _buildLoginForm() else _buildRegisterForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? HudTheme.bgHover : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : HudTheme.textMuted,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('E-MAIL OU @USERNAME'),
        _buildTextField(
          controller: _loginIdentifierController,
          hintText: 'ex: joao@email.com ou @joaosilva',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 16),

        _buildFieldLabel('SENHA'),
        _buildTextField(
          controller: _loginPasswordController,
          hintText: 'Sua senha',
          icon: Icons.lock_outline,
          obscureText: _loginObscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _loginObscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: HudTheme.textMuted,
              size: 18,
            ),
            onPressed: () => setState(() => _loginObscurePassword = !_loginObscurePassword),
          ),
          onSubmitted: (_) => _handleLogin(),
        ),
        const SizedBox(height: 24),

        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: HudTheme.blurple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 2,
          ),
          onPressed: _isLoading ? null : _handleLogin,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Entrar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ],
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Display Name
        _buildFieldLabel('NOME DE EXIBIÇÃO'),
        _buildTextField(
          controller: _regDisplayNameController,
          hintText: 'Como quer ser chamado (ex: João Silva)',
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: 14),

        // Unique @username
        _buildFieldLabel('NOME DE USUÁRIO ÚNICO (@USERNAME)'),
        _buildTextField(
          controller: _regUsernameController,
          hintText: 'ex: joaosilva',
          prefixText: '@',
          icon: Icons.alternate_email,
          onChanged: _onUsernameChanged,
          suffixIcon: _isCheckingUsername
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: HudTheme.accent),
                  ),
                )
              : (_isUsernameAvailable == true
                  ? const Icon(Icons.check_circle, color: HudTheme.green, size: 20)
                  : (_isUsernameAvailable == false
                      ? const Icon(Icons.cancel, color: HudTheme.red, size: 20)
                      : null)),
        ),
        // Feedback em tempo real do username
        if (_usernameFormatError != null) ...[
          const SizedBox(height: 4),
          Text(
            _usernameFormatError!,
            style: const TextStyle(color: HudTheme.red, fontSize: 11),
          ),
        ] else if (_isUsernameAvailable == true) ...[
          const SizedBox(height: 4),
          const Text(
            '✓ Este @username está disponível!',
            style: TextStyle(color: HudTheme.green, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ] else if (_isUsernameAvailable == false) ...[
          const SizedBox(height: 4),
          const Text(
            '✗ Este @username já está em uso.',
            style: TextStyle(color: HudTheme.red, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          if (_usernameSuggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _usernameSuggestions.map((sug) {
                return InkWell(
                  onTap: () {
                    final cleanSug = sug.replaceAll('@', '');
                    _regUsernameController.text = cleanSug;
                    _onUsernameChanged(cleanSug);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HudTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: HudTheme.accent.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '+ $sug',
                      style: const TextStyle(color: HudTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
        const SizedBox(height: 14),

        // Email
        _buildFieldLabel('E-MAIL'),
        _buildTextField(
          controller: _regEmailController,
          hintText: 'seu@email.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),

        // Password
        _buildFieldLabel('SENHA (MÍN. 8 DÍGITOS, 1 MAIÚSCULA, 1 NÚMERO)'),
        _buildTextField(
          controller: _regPasswordController,
          hintText: 'Crie uma senha forte',
          icon: Icons.lock_outline,
          obscureText: _regObscurePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _regObscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: HudTheme.textMuted,
              size: 18,
            ),
            onPressed: () => setState(() => _regObscurePassword = !_regObscurePassword),
          ),
          onSubmitted: (_) => _handleRegister(),
        ),
        const SizedBox(height: 24),

        // Register Button
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: HudTheme.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 2,
          ),
          onPressed: _isLoading ? null : _handleRegister,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : const Text('Criar Conta no PapoCall', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: HudTheme.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    String? prefixText,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: HudTheme.bgInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HudTheme.divider),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: HudTheme.textHeader, fontSize: 14),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: HudTheme.textMuted, fontSize: 13),
          prefixIcon: Icon(icon, color: HudTheme.textMuted, size: 18),
          prefixText: prefixText,
          prefixStyle: const TextStyle(color: HudTheme.accent, fontWeight: FontWeight.bold, fontSize: 14),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}
