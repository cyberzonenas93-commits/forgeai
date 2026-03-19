class AuthFailure implements Exception {
  const AuthFailure({
    required this.code,
    required this.message,
    this.recoverable = true,
  });

  factory AuthFailure.invalidEmail([
    String message = 'Enter a valid email address.',
  ]) {
    return AuthFailure(code: 'invalid-email', message: message);
  }

  factory AuthFailure.invalidPassword([
    String message = 'Use at least 8 characters.',
  ]) {
    return AuthFailure(code: 'invalid-password', message: message);
  }

  factory AuthFailure.invalidConfirmation([
    String message = 'Type DELETE to confirm this action.',
  ]) {
    return AuthFailure(
      code: 'invalid-confirmation',
      message: message,
      recoverable: false,
    );
  }

  factory AuthFailure.authenticationRequired([
    String message = 'Re-authentication is required before this action.',
  ]) {
    return AuthFailure(
      code: 'reauth-required',
      message: message,
      recoverable: false,
    );
  }

  factory AuthFailure.accountNotFound([
    String message = 'No account is currently signed in.',
  ]) {
    return AuthFailure(
      code: 'account-not-found',
      message: message,
      recoverable: false,
    );
  }

  final String code;
  final String message;
  final bool recoverable;

  @override
  String toString() => 'AuthFailure($code): $message';
}
