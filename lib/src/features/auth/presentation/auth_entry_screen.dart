import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../core/widgets/forge_ui.dart';
import '../../legal/legal_document_screen.dart';
import '../application/auth_controller.dart';
import '../domain/auth_provider_kind.dart';
import '../domain/auth_state.dart';

class AuthEntryScreen extends StatefulWidget {
  const AuthEntryScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<AuthEntryScreen> createState() => _AuthEntryScreenState();
}

class _AuthEntryScreenState extends State<AuthEntryScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    if (_isSignUp) {
      await widget.controller.signUpWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _displayNameController.text,
      );
    } else {
      await widget.controller.signInWithEmail(
        email: _emailController.text,
        password: _passwordController.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ForgePanel(
                      highlight: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ForgeBrandMark(showText: true),
                          const SizedBox(height: 18),
                          Text(
                            _isSignUp
                                ? 'Create your ForgeAI account'
                                : 'Welcome back',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Premium mobile Git operations with visible diffs, AI review, and approval-based shipping.',
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
                              _isSignUp ? 'Email sign up' : 'Email sign in',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            if (_isSignUp) ...[
                              TextFormField(
                                controller: _displayNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Display name',
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                              validator: (value) =>
                                  (value?.contains('@') ?? false)
                                  ? null
                                  : 'Enter a valid email address.',
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: _isSignUp
                                    ? 'Create password'
                                    : 'Password',
                              ),
                              validator: (value) =>
                                  ((value ?? '').trim().length >= 8)
                                  ? null
                                  : 'Use at least 8 characters.',
                            ),
                            const SizedBox(height: 16),
                            ForgePrimaryButton(
                              label: _isSignUp ? 'Create account' : 'Sign in',
                              icon: Icons.login_rounded,
                              onPressed: state.isBusy ? null : _submitEmail,
                              expanded: true,
                            ),
                            const SizedBox(height: 10),
                            ForgeSecondaryButton(
                              label: _isSignUp
                                  ? 'I already have an account'
                                  : 'Need an account? Create one',
                              onPressed: state.isBusy
                                  ? null
                                  : () =>
                                        setState(() => _isSignUp = !_isSignUp),
                              expanded: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ForgePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick access',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              ForgeSecondaryButton(
                                label: 'Guest',
                                icon: Icons.person_outline_rounded,
                                onPressed: state.isBusy
                                    ? null
                                    : widget.controller.continueAsGuest,
                              ),
                              ForgeSecondaryButton(
                                label: 'Google',
                                icon: Icons.g_mobiledata_rounded,
                                onPressed: state.isBusy
                                    ? null
                                    : () =>
                                          widget.controller.signInWithProvider(
                                            AuthProviderKind.google,
                                          ),
                              ),
                              ForgeSecondaryButton(
                                label: 'Apple',
                                icon: Icons.apple_rounded,
                                onPressed: state.isBusy
                                    ? null
                                    : () =>
                                          widget.controller.signInWithProvider(
                                            AuthProviderKind.apple,
                                          ),
                              ),
                              ForgeSecondaryButton(
                                label: 'GitHub',
                                icon: Icons.code_rounded,
                                onPressed: state.isBusy
                                    ? null
                                    : () =>
                                          widget.controller.signInWithProvider(
                                            AuthProviderKind.github,
                                          ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _LegalFooter(
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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter({
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
      textAlign: TextAlign.center,
      text: TextSpan(
        style: theme.bodySmall?.copyWith(color: ForgePalette.textSecondary),
        children: [
          const TextSpan(text: 'By continuing you agree to our '),
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
