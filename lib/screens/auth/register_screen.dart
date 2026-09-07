import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import 'referral_onboarding_screen.dart';

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
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          // Main route into the referral program: right after signup, while
          // "install it and put my code" is still fresh. It sends the user on
          // to /home itself, whichever branch they take.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const ReferralOnboardingScreen(),
            ),
          );
        }
      }
    }
  }

  Widget _eyeToggle(bool obscured, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size: 18,
        color: AppTheme.textSecondary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),
                    Image.asset(
                      'assets/logo/logo-without-letters.png',
                      width: 60,
                      height: 60,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.dartRivals,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: AppTheme.textPrimary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildForm(l10n),
                    const Spacer(),
                    const SizedBox(height: 24),
                    _buildFooter(l10n),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LabeledField(
            label: l10n.username,
            controller: _usernameController,
            icon: Icons.person_outline_rounded,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.usernameRequired;
              }
              if (value.length < 3) {
                return l10n.usernameTooShort;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _LabeledField(
            label: l10n.email,
            controller: _emailController,
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.emailRequired;
              }
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                return l10n.emailInvalid;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _LabeledField(
            label: l10n.password,
            controller: _passwordController,
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            suffix: _eyeToggle(_obscurePassword, () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            }),
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
          _LabeledField(
            label: l10n.confirmPassword,
            controller: _confirmPasswordController,
            icon: Icons.lock_outline_rounded,
            obscureText: _obscureConfirmPassword,
            suffix: _eyeToggle(_obscureConfirmPassword, () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            }),
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
          const SizedBox(height: 20),
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final message = authProvider.errorMessage;
              if (message == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _ErrorBanner(message: message),
              );
            },
          ),
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              return SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: authProvider.isLoading ? null : _handleRegister,
                  child: authProvider.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(dsSentence(l10n.registerButton)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l10n) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.alreadyHaveAccount,
          style: AppTheme.caption.copyWith(fontSize: 14),
        ),
        TextButton(
          onPressed: () {
            context.read<AuthProvider>().clearError();
            AppNavigator.toAuth(context, '/login');
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            l10n.login,
            style: AppTheme.labelLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryLight,
            ),
          ),
        ),
      ],
    );
  }
}

/// 12 / 600 label above a themed field; the placeholder repeats the label.
class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: AppTheme.rowTitle,
          decoration: InputDecoration(
            hintText: label,
            prefixIcon: Icon(icon, size: 18, color: AppTheme.textSecondary),
            suffixIcon: suffix,
          ),
          validator: validator,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return DsCard(
      radius: AppTheme.radiusControl,
      color: AppTheme.error.withValues(alpha: 0.10),
      side: BorderSide(color: AppTheme.error.withValues(alpha: 0.4)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppTheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.caption
                  .copyWith(color: AppTheme.textPrimary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
