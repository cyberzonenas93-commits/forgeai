import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/branding/app_branding.dart';
import '../../../core/theme/forge_palette.dart';
import '../../../core/widgets/forge_ui.dart';
import '../../legal/legal_document_screen.dart';
import '../application/auth_controller.dart';
import '../domain/auth_state.dart';
import '../domain/password_strength.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    super.key,
    required this.controller,
  });

  final AuthController controller;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _agreeToTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please accept the Terms of Service and Privacy Policy.')),
      );
      return;
    }
    await widget.controller.signUpWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      displayName: _fullNameController.text.trim().isNotEmpty
          ? _fullNameController.text.trim()
          : null,
    );
    // Sign-up swaps AuthGate to the signed-in shell, but this screen was pushed
    // on the root navigator — it stays on top until we pop it.
    if (!mounted) return;
    if (widget.controller.value.isSignedIn) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('Create account'),
          ),
          body: ForgeScreen(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    ForgePanel(
                      highlight: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create your $kAppDisplayName account',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Enter your details below. Use a strong password to keep your account secure.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (state.failure != null) ...[
                      const SizedBox(height: 12),
                      _MessagePanel(
                        message: state.failure!.message,
                        color: ForgePalette.error,
                        icon: Icons.error_outline_rounded,
                      ),
                    ],
                    if (state.notice != null) ...[
                      const SizedBox(height: 12),
                      _MessagePanel(
                        message: state.notice!,
                        color: ForgePalette.success,
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ],
                    const SizedBox(height: 12),
                    ForgePanel(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your details',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _fullNameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                hintText: 'How we\'ll show your name in the app',
                              ),
                              validator: (value) {
                                final s = (value ?? '').trim();
                                if (s.isEmpty) return 'Enter your full name.';
                                if (s.length < 2) return 'Use at least 2 characters.';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                              validator: (value) {
                                final s = (value ?? '').trim();
                                if (s.isEmpty) return 'Enter your email.';
                                if (!s.contains('@') || !s.contains('.')) {
                                  return 'Enter a valid email address.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Create password',
                                hintText: 'Min ${PasswordStrength.minLength} chars, mixed case, number, symbol',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (value) =>
                                  PasswordStrength.validate(value),
                            ),
                            const SizedBox(height: 10),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _passwordController,
                              builder: (context, value, _) =>
                                  _PasswordRequirements(password: value.text),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              decoration: InputDecoration(
                                labelText: 'Confirm password',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirm = !_obscureConfirm;
                                    });
                                  },
                                ),
                              ),
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Confirm your password.';
                                }
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: Checkbox(
                                    value: _agreeToTerms,
                                    onChanged: (v) =>
                                        setState(() => _agreeToTerms = v ?? false),
                                    fillColor: WidgetStateProperty.resolveWith((states) {
                                      if (states.contains(WidgetState.selected)) {
                                        return ForgePalette.primaryAccent;
                                      }
                                      return null;
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: _TermsText(
                                      onOpenTerms: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const LegalDocumentScreen(
                                              title: 'Terms of Service',
                                              assetPath: 'assets/legal/terms_of_service.md',
                                            ),
                                          ),
                                        );
                                      },
                                      onOpenPrivacy: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => const LegalDocumentScreen(
                                              title: 'Privacy Policy',
                                              assetPath: 'assets/legal/privacy_policy.md',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            ForgePrimaryButton(
                              label: 'Create account',
                              icon: Icons.person_add_rounded,
                              onPressed: state.isBusy ? null : _submit,
                              expanded: true,
                            ),
                            const SizedBox(height: 12),
                            ForgeSecondaryButton(
                              label: 'I already have an account',
                              icon: Icons.login_rounded,
                              onPressed: state.isBusy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              expanded: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PasswordRequirements extends StatelessWidget {
  const _PasswordRequirements({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Password must have:',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: ForgePalette.textSecondary,
              ),
        ),
        const SizedBox(height: 6),
        ...List.generate(5, (i) {
          final satisfied = i == 0
              ? PasswordStrength.hasMinLength(password)
              : i == 1
                  ? PasswordStrength.hasUppercase(password)
                  : i == 2
                      ? PasswordStrength.hasLowercase(password)
                      : i == 3
                          ? PasswordStrength.hasDigit(password)
                          : PasswordStrength.hasSpecialChar(password);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  satisfied ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 16,
                  color: satisfied
                      ? ForgePalette.success
                      : ForgePalette.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    PasswordStrength.requirementLabels[i],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: satisfied
                              ? ForgePalette.textSecondary
                              : ForgePalette.textMuted,
                        ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _TermsText extends StatelessWidget {
  const _TermsText({
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final linkStyle = theme.bodySmall?.copyWith(
      color: ForgePalette.glowAccent,
      decoration: TextDecoration.underline,
    );
    return RichText(
      text: TextSpan(
        style: theme.bodySmall?.copyWith(color: ForgePalette.textSecondary),
        children: [
          const TextSpan(text: 'I agree to the '),
          TextSpan(
            text: 'Terms of Service',
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = onOpenTerms,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = onOpenPrivacy,
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
