import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../../core/observability/forge_telemetry.dart';
import '../data/firebase_auth_repository.dart';
import '../data/in_memory_auth_repository.dart';
import '../domain/auth_account.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_provider_kind.dart';
import '../domain/auth_reauth_request.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_state.dart';

class AuthController extends ValueNotifier<AuthState> {
  AuthController({AuthRepository? repository, ForgeTelemetry? telemetry})
    : _repository = repository ?? _defaultRepository(),
      _telemetry = telemetry ?? ForgeTelemetry.instance,
      super(AuthState.empty) {
    _bootstrap();
  }

  final AuthRepository _repository;
  final ForgeTelemetry _telemetry;
  StreamSubscription<AuthAccount?>? _subscription;

  static AuthRepository _defaultRepository() {
    if (Firebase.apps.isNotEmpty) {
      return FirebaseAuthRepository();
    }
    return InMemoryAuthRepository();
  }

  Future<void> _bootstrap() async {
    _subscription?.cancel();
    value = value.copyWith(
      operation: AuthOperation.bootstrapping,
      clearFailure: true,
      clearNotice: true,
    );
    _subscription = _repository.watchCurrentAccount().listen(
      _handleExternalAccount,
    );
    try {
      final account = await _repository.bootstrap();
      value = AuthState(account: account, operation: AuthOperation.idle);
      unawaited(_telemetry.attachUser(account));
    } on AuthFailure catch (failure) {
      value = value.copyWith(operation: AuthOperation.idle, failure: failure);
      unawaited(
        _telemetry.logEvent(
          'forge_auth_bootstrap_failure',
          parameters: <String, Object?>{'code': failure.code},
        ),
      );
    } catch (error) {
      value = value.copyWith(
        operation: AuthOperation.idle,
        failure: AuthFailure(
          code: 'bootstrap-failed',
          message: error.toString(),
        ),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'auth_bootstrap',
        ),
      );
    }
  }

  void _handleExternalAccount(AuthAccount? account) {
    unawaited(_telemetry.attachUser(account));
    value = value.copyWith(
      account: account,
      clearAccount: account == null,
      operation: AuthOperation.idle,
      clearFailure: true,
    );
  }

  Future<void> continueAsGuest() => _runAction(
    operation: AuthOperation.continuingAsGuest,
    action: _repository.continueAsGuest,
    successNotice: 'Guest session started. You can connect a repository next.',
  );

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) => _runAction(
    operation: AuthOperation.signingInWithEmail,
    action: () => _repository.signInWithEmail(email: email, password: password),
    successNotice: 'Welcome back. Your account is ready.',
  );

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) => _runAction(
    operation: AuthOperation.signingUpWithEmail,
    action: () => _repository.signUpWithEmail(
      email: email,
      password: password,
      displayName: displayName,
    ),
    successNotice: 'Account created. You are signed in.',
  );

  Future<void> signInWithProvider(AuthProviderKind provider) => _runAction(
    operation: AuthOperation.signingInWithProvider,
    action: () => _repository.signInWithProvider(provider),
    successNotice: '${provider.label} sign-in completed.',
  );

  Future<void> reauthenticateWithProvider(
    AuthProviderKind provider, {
    String? email,
    String? password,
  }) => _runAction(
    operation: AuthOperation.reauthenticating,
    action: () => _repository.reauthenticate(
      AuthReauthRequest(provider: provider, email: email, password: password),
    ),
    successNotice: 'Identity confirmed. You can continue.',
  );

  Future<void> signOut() => _runAction(
    operation: AuthOperation.signingOut,
    action: _repository.signOut,
    successNotice: 'Signed out.',
    preserveAccountOnSuccess: false,
  );

  Future<void> deleteAccount({required String confirmationPhrase}) =>
      _runAction(
        operation: AuthOperation.deletingAccount,
        action: () => _repository.deleteCurrentAccount(
          confirmationPhrase: confirmationPhrase,
        ),
        successNotice: 'Account deleted.',
        preserveAccountOnSuccess: false,
      );

  Future<void> _runAction({
    required AuthOperation operation,
    required Future<dynamic> Function() action,
    required String successNotice,
    bool preserveAccountOnSuccess = true,
  }) async {
    value = value.copyWith(
      operation: operation,
      clearFailure: true,
      clearNotice: true,
    );
    try {
      final result = await action();
      final account = result is AuthAccount
          ? result
          : (preserveAccountOnSuccess ? value.account : null);
      value = value.copyWith(
        account: account,
        clearAccount: !preserveAccountOnSuccess && account == null,
        operation: AuthOperation.idle,
        notice: successNotice,
        clearFailure: true,
      );
      unawaited(
        _telemetry.logEvent(
          'forge_auth_action_success',
          parameters: <String, Object?>{
            'operation': operation.name,
            'provider': account?.provider.name ?? 'signed_out',
          },
        ),
      );
    } on AuthFailure catch (failure) {
      value = value.copyWith(operation: AuthOperation.idle, failure: failure);
      unawaited(
        _telemetry.logEvent(
          'forge_auth_action_failure',
          parameters: <String, Object?>{
            'operation': operation.name,
            'code': failure.code,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        operation: AuthOperation.idle,
        failure: AuthFailure(code: 'unknown-error', message: error.toString()),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'auth_action_${operation.name}',
        ),
      );
    }
  }

  void clearMessages() {
    value = value.copyWith(clearFailure: true, clearNotice: true);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
