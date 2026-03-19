import 'package:flutter/material.dart';

import '../application/auth_controller.dart';

/// Shows a dialog explaining that the feature requires signing in.
/// Offers [Sign out and sign in] (returns to auth entry) or [Cancel].
/// Use for guest users when they tap Connect repository, Wallet, Account hub, etc.
Future<void> showGuestSignInRequiredDialog(
  BuildContext context, {
  required AuthController authController,
  required String featureName,
}) async {
  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sign in required'),
      content: Text(
        '$featureName requires a full account. Sign out and sign in with Google, Apple, GitHub, or email to continue.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign out and sign in'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await authController.signOut();
  }
}
