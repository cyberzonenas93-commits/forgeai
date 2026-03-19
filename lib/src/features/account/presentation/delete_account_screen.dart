import 'package:flutter/material.dart';

import '../../../core/widgets/forge_ui.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_failure.dart';
import '../../auth/domain/auth_provider_kind.dart';
import '../../auth/domain/auth_state.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();
  late AuthProviderKind _reauthProvider;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final provider = widget.controller.value.account?.provider;
    _reauthProvider = provider == null || provider == AuthProviderKind.guest
        ? AuthProviderKind.emailPassword
        : provider;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _reauthenticate() async {
    setState(() => _isSubmitting = true);
    try {
      if (_reauthProvider == AuthProviderKind.emailPassword) {
        await widget.controller.reauthenticateWithProvider(
          _reauthProvider,
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await widget.controller.reauthenticateWithProvider(_reauthProvider);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deleteAccount() async {
    setState(() => _isSubmitting = true);
    try {
      await widget.controller.deleteAccount(
        confirmationPhrase: _confirmationController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on AuthFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final account = state.account;
        final canDelete =
            account != null &&
            (_confirmationController.text.trim().toUpperCase() == 'DELETE') &&
            (account.isGuest || account.canDeleteNow(now: DateTime.now()));
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: ListView(
              children: [
                ForgePanel(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ForgeSectionHeader(
                        title: 'Delete account',
                        subtitle:
                            'This permanently removes the ForgeAI account and requires explicit confirmation.',
                      ),
                      const SizedBox(height: 14),
                      const ForgePill(
                        label: 'Destructive action',
                        icon: Icons.warning_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ForgePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step 1. Re-authenticate',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AuthProviderKind>(
                        initialValue: _reauthProvider,
                        items: AuthProviderKind.values
                            .where(
                              (provider) => provider != AuthProviderKind.guest,
                            )
                            .map(
                              (provider) => DropdownMenuItem(
                                value: provider,
                                child: Text(provider.label),
                              ),
                            )
                            .toList(),
                        onChanged: _isSubmitting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _reauthProvider = value);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      if (_reauthProvider ==
                          AuthProviderKind.emailPassword) ...[
                        TextField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ForgeSecondaryButton(
                        label: 'Confirm identity',
                        onPressed: _isSubmitting ? null : _reauthenticate,
                        expanded: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ForgePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step 2. Type DELETE',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmationController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Confirmation phrase',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      ForgePrimaryButton(
                        label: 'Delete account',
                        onPressed: _isSubmitting || !canDelete
                            ? null
                            : _deleteAccount,
                        expanded: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
