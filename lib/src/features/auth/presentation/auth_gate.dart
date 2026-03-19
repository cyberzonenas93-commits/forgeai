import 'package:flutter/material.dart';

import '../../../core/widgets/forge_ui.dart';
import '../application/auth_controller.dart';
import '../domain/auth_account.dart';
import '../domain/auth_state.dart';
import 'auth_entry_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.signedInBuilder,
    this.loadingBuilder,
  });

  final AuthController controller;
  final Widget Function(BuildContext context, AuthAccount account)
  signedInBuilder;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AuthState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final Widget child;
        if (state.operation == AuthOperation.bootstrapping) {
          child = KeyedSubtree(
            key: const ValueKey('auth-loading'),
            child:
                loadingBuilder?.call(context) ??
                const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
          );
        } else if (state.account != null) {
          child = KeyedSubtree(
            key: ValueKey('auth-signed-in-${state.account!.id}'),
            child: signedInBuilder(context, state.account!),
          );
        } else {
          child = KeyedSubtree(
            key: const ValueKey('auth-signed-out'),
            child: AuthEntryScreen(controller: controller),
          );
        }

        return ForgeAnimatedSwap(child: child);
      },
    );
  }
}
