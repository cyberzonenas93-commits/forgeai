enum AuthProviderKind { guest, emailPassword, google, apple, github }

extension AuthProviderKindX on AuthProviderKind {
  String get label {
    switch (this) {
      case AuthProviderKind.guest:
        return 'Guest';
      case AuthProviderKind.emailPassword:
        return 'Email';
      case AuthProviderKind.google:
        return 'Google';
      case AuthProviderKind.apple:
        return 'Apple';
      case AuthProviderKind.github:
        return 'GitHub';
    }
  }

  String get reviewCopy {
    switch (this) {
      case AuthProviderKind.guest:
        return 'Limited guest session';
      case AuthProviderKind.emailPassword:
        return 'Email and password identity';
      case AuthProviderKind.google:
        return 'Google identity convenience sign-in';
      case AuthProviderKind.apple:
        return 'Sign in with Apple';
      case AuthProviderKind.github:
        return 'GitHub identity convenience sign-in';
    }
  }

  bool get requiresSecret {
    switch (this) {
      case AuthProviderKind.guest:
      case AuthProviderKind.google:
      case AuthProviderKind.apple:
      case AuthProviderKind.github:
        return false;
      case AuthProviderKind.emailPassword:
        return true;
    }
  }
}
