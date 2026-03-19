import 'package:flutter/material.dart';

import '../../../core/widgets/forge_ui.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/domain/auth_provider_kind.dart';
import '../../auth/domain/auth_state.dart';
import 'delete_account_screen.dart';

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final account = state.account;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: ListView(
              children: [
                if (account != null)
                  ForgePanel(
                    highlight: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.displayName,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          account.email,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        ForgePill(
                          label: account.provider.reviewCopy,
                          icon: Icons.verified_user_rounded,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                _ActionCard(
                  title: 'Re-authenticate',
                  subtitle: 'Confirm identity before a sensitive action.',
                  onPressed: account == null
                      ? null
                      : () {
                          showDialog<void>(
                            context: context,
                            builder: (_) => _ReauthDialog(
                              controller: controller,
                              account: account,
                            ),
                          );
                        },
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  title: 'Delete account',
                  subtitle: 'Requires a fresh re-auth and typed confirmation.',
                  onPressed: account == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  DeleteAccountScreen(controller: controller),
                            ),
                          );
                        },
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  title: 'Sign out',
                  subtitle: 'Leave the current ForgeAI session.',
                  onPressed: state.isBusy ? null : controller.signOut,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          ForgeSecondaryButton(
            label: title,
            onPressed: onPressed,
            expanded: true,
          ),
        ],
      ),
    );
  }
}

class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog({required this.controller, required this.account});

  final AuthController controller;
  final AuthAccount account;

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.account.email;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      if (widget.account.provider == AuthProviderKind.emailPassword) {
        await widget.controller.reauthenticateWithProvider(
          AuthProviderKind.emailPassword,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await widget.controller.reauthenticateWithProvider(
          widget.account.provider,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmail = widget.account.provider == AuthProviderKind.emailPassword;
    return AlertDialog(
      title: const Text('Re-authenticate'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEmail) ...[
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ] else
            Text(
              '${widget.account.provider.label} will be used for confirmation.',
            ),
        ],
      ),
      actions: [
        ForgeSecondaryButton(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        ForgePrimaryButton(label: 'Confirm', onPressed: _busy ? null : _submit),
      ],
    );
  }
}
