import 'auth_account.dart';
import 'auth_failure.dart';
import 'auth_provider_kind.dart';

enum AuthOperation {
  idle,
  bootstrapping,
  continuingAsGuest,
  signingInWithEmail,
  signingUpWithEmail,
  signingInWithProvider,
  reauthenticating,
  signingOut,
  deletingAccount,
}

class AuthState {
  const AuthState({
    this.account,
    this.operation = AuthOperation.idle,
    this.failure,
    this.notice,
  });

  final AuthAccount? account;
  final AuthOperation operation;
  final AuthFailure? failure;
  final String? notice;

  bool get isBusy => operation != AuthOperation.idle;
  bool get isSignedIn => account != null;
  bool get isGuest => account?.isGuest ?? false;
  bool get requiresReauthentication => account?.canDeleteNow() == false;
  AuthProviderKind? get primaryProvider => account?.provider;

  AuthState copyWith({
    AuthAccount? account,
    AuthOperation? operation,
    AuthFailure? failure,
    String? notice,
    bool clearAccount = false,
    bool clearFailure = false,
    bool clearNotice = false,
  }) {
    return AuthState(
      account: clearAccount ? null : (account ?? this.account),
      operation: operation ?? this.operation,
      failure: clearFailure ? null : (failure ?? this.failure),
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }

  static const AuthState empty = AuthState();
}
