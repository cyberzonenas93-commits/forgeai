import 'auth_provider_kind.dart';

class AuthReauthRequest {
  const AuthReauthRequest({required this.provider, this.email, this.password});

  final AuthProviderKind provider;
  final String? email;
  final String? password;
}
