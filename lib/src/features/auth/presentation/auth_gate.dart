import 'package:flutter/material.dart';

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
        if (state.operation == AuthOperation.bootstrapping) {
          return loadingBuilder?.call(context) ??
              const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (state.account != null) {
          return signedInBuilder(context, state.account!);
        }
        return AuthEntryScreen(controller: controller);
      },
    );
  }
}
