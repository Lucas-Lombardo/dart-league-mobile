import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _linkSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.forgotPassword(
        email: _emailController.text.trim(),
      );

      if (success && mounted) {
        setState(() {
          _linkSent = true;
        });
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
                    width: 160,
                    height: 160,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 48),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _linkSent ? _buildSuccessView(l10n) : _buildFormView(l10n),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () {
                      context.read<AuthProvider>().clearError();
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    child: Text(l10n.backToLogin),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.lock_reset,
            size: 48,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.forgotPasswordTitle,
            style: AppTheme.displayMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.forgotPasswordDescription,
            style: AppTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
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
              if (!value.contains('@')) {
                return l10n.emailInvalid;
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
                  onPressed: authProvider.isLoading ? null : _handleSubmit,
                  child: authProvider.isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(l10n.sendResetLink.toUpperCase()),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(AppLocalizations l10n) {
    return Column(
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: AppTheme.success,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.resetLinkSent,
          style: AppTheme.displayMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.resetLinkSentDescription,
          style: AppTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
