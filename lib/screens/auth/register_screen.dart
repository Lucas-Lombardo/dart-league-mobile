import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      final localeProvider = context.read<LocaleProvider>();
      final success = await authProvider.register(
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        language: localeProvider.languageCode,
      );

      if (success && mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.mark_email_read_outlined, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.checkYourEmail)),
              ],
            ),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.surfaceGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/logo/logo.png',
                    width: 180,
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.dartRivals,
                    style: AppTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _usernameController,
                              style: const TextStyle(color: Colors.white),
                              decoration: AppTheme.inputDecoration(
                                label: l10n.username,
                                prefixIcon: Icons.person_outline,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.usernameRequired;
                                }
                                if (value.length < 3) {
                                  return l10n.usernameTooShort;
                                }
                                if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                                  return l10n.usernameInvalid;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: Colors.white),
                              decoration: AppTheme.inputDecoration(
                                label: l10n.email,
                                prefixIcon: Icons.email_outlined,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.emailRequired;
                                }
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                  return l10n.emailInvalid;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: const TextStyle(color: Colors.white),
                              decoration: AppTheme.inputDecoration(
                                label: l10n.password,
                                prefixIcon: Icons.lock_outline,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.passwordRequired;
                                }
                                if (value.length < 6) {
                                  return l10n.passwordTooShort;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirmPassword,
                              style: const TextStyle(color: Colors.white),
                              decoration: AppTheme.inputDecoration(
                                label: l10n.confirmPassword,
                                prefixIcon: Icons.lock_outline,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    color: AppTheme.textSecondary,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirmPassword = !_obscureConfirmPassword;
                                    });
                                  },
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.confirmPasswordRequired;
                                }
                                if (value != _passwordController.text) {
                                  return l10n.passwordMismatch;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            Consumer<AuthProvider>(
                              builder: (context, authProvider, _) {
                                if (authProvider.errorMessage != null) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.error.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppTheme.error),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              authProvider.errorMessage!,
                                              style: const TextStyle(color: AppTheme.error),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                            Consumer<AuthProvider>(
                              builder: (context, authProvider, _) {
                                return SizedBox(
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: authProvider.isLoading ? null : _handleRegister,
                                    child: authProvider.isLoading
                                        ? const SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          )
                                        : Text(l10n.registerButton.toUpperCase()),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${l10n.alreadyHaveAccount} ',
                        style: AppTheme.bodyLarge,
                      ),
                      TextButton(
                        onPressed: () {
                          context.read<AuthProvider>().clearError();
                          Navigator.pushReplacementNamed(context, '/login');
                        },
                        child: Text(l10n.login),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
