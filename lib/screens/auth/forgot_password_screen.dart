import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';

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
                    const SizedBox(height: 64),
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
                    const SizedBox(height: 40),
                    _linkSent ? _buildSuccessView(l10n) : _buildFormView(l10n),
                    const Spacer(),
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          context.read<AuthProvider>().clearError();
                          AppNavigator.toAuth(context, '/login');
                        },
                        child: Text(l10n.backToLogin),
                      ),
                    ),
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

  Widget _buildFormView(AppLocalizations l10n) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 28),
          Text(
            l10n.email,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: AppTheme.rowTitle,
            decoration: InputDecoration(
              hintText: l10n.email,
              prefixIcon: const Icon(Icons.mail_outline_rounded,
                  size: 18, color: AppTheme.textSecondary),
            ),
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
          const SizedBox(height: 20),
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              final message = authProvider.errorMessage;
              if (message == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DsCard(
                  radius: AppTheme.radiusControl,
                  color: AppTheme.error.withValues(alpha: 0.10),
                  side: BorderSide(color: AppTheme.error.withValues(alpha: 0.4)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 18, color: AppTheme.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          message,
                          style: AppTheme.caption.copyWith(
                              color: AppTheme.textPrimary, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              return SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: authProvider.isLoading ? null : _handleSubmit,
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
                      : Text(dsSentence(l10n.sendResetLink)),
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
          size: 48,
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
