import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../core/widgets/forge_ui.dart';
import '../../legal/legal_document_screen.dart';
import '../application/auth_controller.dart';
import '../domain/auth_provider_kind.dart';
import '../domain/auth_state.dart';
import 'create_account_screen.dart';

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
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    await widget.controller.signInWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  void _openCreateAccount() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateAccountScreen(controller: widget.controller),
      ),
    );
  }

  void _openTerms() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LegalDocumentScreen(
          title: 'Terms of Service',
          assetPath: 'assets/legal/terms_of_service.md',
        ),
      ),
    );
  }

  void _openPrivacy() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LegalDocumentScreen(
          title: 'Privacy Policy',
          assetPath: 'assets/legal/privacy_policy.md',
        ),
      ),
    );
  }

  String _busyLabel(AuthOperation operation) {
    switch (operation) {
      case AuthOperation.signingInWithEmail:
        return 'Signing you in with email...';
      case AuthOperation.signingInWithProvider:
        return 'Connecting your provider...';
      case AuthOperation.continuingAsGuest:
        return 'Opening a guest session...';
      case AuthOperation.signingUpWithEmail:
        return 'Creating your account...';
      case AuthOperation.reauthenticating:
        return 'Refreshing your session...';
      case AuthOperation.signingOut:
        return 'Signing you out...';
      case AuthOperation.deletingAccount:
        return 'Processing your account update...';
      case AuthOperation.bootstrapping:
      case AuthOperation.idle:
        return 'Preparing your workspace...';
    }
  }

  Widget _buildIntroPanel(BuildContext context) {
    return ForgePanel(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ForgePill(
                label: 'Mobile Git cockpit',
                icon: Icons.mobile_friendly_rounded,
                color: ForgePalette.sparkAccent,
              ),
              ForgePill(
                label: 'Approval-first workflow',
                icon: Icons.verified_rounded,
                color: ForgePalette.mintAccent,
              ),
            ],
          ),
          const SizedBox(height: 22),
          const ForgeBrandMark(showText: true),
          const SizedBox(height: 24),
          Text(
            'Stay close to your code, even when you are away from the desk.',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(height: 1.08),
          ),
          const SizedBox(height: 12),
          Text(
            'Sign in, inspect diffs, ask AI for help, and approve changes from one clear workflow built for smaller screens.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: ForgePalette.textSecondary),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final cardWidth = compact
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: const _LaunchFeatureCard(
                      icon: Icons.compare_arrows_rounded,
                      accent: ForgePalette.glowAccent,
                      title: 'Readable diffs',
                      subtitle:
                          'Review each change with enough space to understand it before you commit.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: const _LaunchFeatureCard(
                      icon: Icons.auto_awesome_rounded,
                      accent: ForgePalette.sparkAccent,
                      title: 'Repo-aware agent',
                      subtitle:
                          'Describe an edit in plain language and keep every generated repo diff reviewable.',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: const _LaunchFeatureCard(
                      icon: Icons.shield_outlined,
                      accent: ForgePalette.mintAccent,
                      title: 'Safe shipping',
                      subtitle:
                          'Approve, commit, and open PRs without losing control of the final step.',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessPanel(BuildContext context, AuthState state) {
    final buttons = [
      ForgeSecondaryButton(
        label: 'Guest mode',
        icon: Icons.person_outline_rounded,
        onPressed: state.isBusy ? null : widget.controller.continueAsGuest,
        expanded: true,
      ),
      ForgeSecondaryButton(
        label: 'Google',
        icon: Icons.g_mobiledata_rounded,
        onPressed: state.isBusy
            ? null
            : () =>
                  widget.controller.signInWithProvider(AuthProviderKind.google),
        expanded: true,
      ),
      ForgeSecondaryButton(
        label: 'Apple',
        icon: Icons.apple_rounded,
        onPressed: state.isBusy
            ? null
            : () =>
                  widget.controller.signInWithProvider(AuthProviderKind.apple),
        expanded: true,
      ),
      ForgeSecondaryButton(
        label: 'GitHub',
        icon: Icons.code_rounded,
        onPressed: state.isBusy
            ? null
            : () =>
                  widget.controller.signInWithProvider(AuthProviderKind.github),
        expanded: true,
      ),
    ];

    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick access', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Choose the fastest way in. Buttons stack cleanly on smaller screens for easier tapping.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 420) {
                return Column(
                  children: [
                    for (var index = 0; index < buttons.length; index++) ...[
                      buttons[index],
                      if (index != buttons.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                );
              }

              final buttonWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final button in buttons)
                    SizedBox(width: buttonWidth, child: button),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            maxContentWidth: 1120,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wideLayout = constraints.maxWidth >= 920;
                final actions = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (state.failure != null)
                            ForgeReveal(
                              delay: const Duration(milliseconds: 100),
                              child: _MessagePanel(
                                message: state.failure!.message,
                                color: ForgePalette.error,
                                icon: Icons.error_outline_rounded,
                              ),
                            ),
                          if (state.failure != null && state.notice != null)
                            const SizedBox(height: 12),
                          if (state.notice != null)
                            ForgeReveal(
                              delay: const Duration(milliseconds: 100),
                              child: _MessagePanel(
                                message: state.notice!,
                                color: ForgePalette.success,
                                icon: Icons.check_circle_outline_rounded,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (state.failure != null || state.notice != null)
                      const SizedBox(height: 12),
                    ForgeReveal(
                      delay: const Duration(milliseconds: 120),
                      child: ForgePanel(
                        child: Form(
                          key: _formKey,
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sign in',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Use email for the most straightforward sign-in flow.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  autocorrect: false,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                  ),
                                  validator: (value) =>
                                      (value?.trim().contains('@') ?? false)
                                      ? null
                                      : 'Enter a valid email address.',
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                  onFieldSubmitted: (_) {
                                    if (!state.isBusy) {
                                      _submitEmail();
                                    }
                                  },
                                  validator: (value) =>
                                      (value ?? '').trim().isEmpty
                                      ? 'Enter your password.'
                                      : null,
                                ),
                                if (state.isBusy) ...[
                                  const SizedBox(height: 14),
                                  ForgeAiIndicator(
                                    label: _busyLabel(state.operation),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                ForgePrimaryButton(
                                  label:
                                      state.operation ==
                                          AuthOperation.signingInWithEmail
                                      ? 'Signing in...'
                                      : 'Sign in',
                                  icon: Icons.login_rounded,
                                  onPressed: state.isBusy ? null : _submitEmail,
                                  expanded: true,
                                ),
                                const SizedBox(height: 10),
                                ForgeSecondaryButton(
                                  label: 'Create account',
                                  icon: Icons.person_add_rounded,
                                  onPressed: state.isBusy
                                      ? null
                                      : _openCreateAccount,
                                  expanded: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ForgeReveal(
                      delay: const Duration(milliseconds: 220),
                      child: _buildQuickAccessPanel(context, state),
                    ),
                    const SizedBox(height: 18),
                    ForgeReveal(
                      delay: const Duration(milliseconds: 280),
                      child: _LegalFooter(
                        onOpenTerms: _openTerms,
                        onOpenPrivacy: _openPrivacy,
                      ),
                    ),
                  ],
                );

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wideLayout ? 1040 : 560,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: wideLayout ? 20 : 8,
                        ),
                        child: wideLayout
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 11,
                                    child: ForgeReveal(
                                      delay: const Duration(milliseconds: 40),
                                      child: _buildIntroPanel(context),
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(flex: 10, child: actions),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ForgeReveal(
                                    delay: const Duration(milliseconds: 40),
                                    child: _buildIntroPanel(context),
                                  ),
                                  const SizedBox(height: 14),
                                  actions,
                                ],
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter({required this.onOpenTerms, required this.onOpenPrivacy});

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

class _LaunchFeatureCard extends StatelessWidget {
  const _LaunchFeatureCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.12),
            ForgePalette.surface.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ForgePalette.textSecondary,
              ),
            ),
          ],
        ),
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
