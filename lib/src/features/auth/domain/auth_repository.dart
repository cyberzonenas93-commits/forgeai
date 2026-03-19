import 'auth_account.dart';
import 'auth_provider_kind.dart';
import 'auth_reauth_request.dart';

abstract class AuthRepository {
  Stream<AuthAccount?> watchCurrentAccount();

  Future<AuthAccount?> bootstrap();

  Future<AuthAccount> continueAsGuest();

  Future<AuthAccount> signInWithEmail({
    required String email,
    required String password,
  });

  Future<AuthAccount> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AuthAccount> signInWithProvider(AuthProviderKind provider);

  Future<AuthAccount> reauthenticate(AuthReauthRequest request);

  Future<void> signOut();

  Future<void> deleteCurrentAccount({required String confirmationPhrase});
}
