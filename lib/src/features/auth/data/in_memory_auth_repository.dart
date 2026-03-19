import 'dart:async';

import '../domain/auth_account.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_provider_kind.dart';
import '../domain/auth_reauth_request.dart';
import '../domain/auth_repository.dart';

class InMemoryAuthRepository implements AuthRepository {
  InMemoryAuthRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final StreamController<AuthAccount?> _accountController =
      StreamController<AuthAccount?>.broadcast();
  final Map<String, String> _passwordsByEmail = <String, String>{};
  final Map<String, AuthAccount> _accountsById = <String, AuthAccount>{};

  AuthAccount? _currentAccount;

  @override
  Stream<AuthAccount?> watchCurrentAccount() async* {
    yield _currentAccount;
    yield* _accountController.stream;
  }

  @override
  Future<AuthAccount?> bootstrap() async {
    await _simulateNetworkDelay();
    return _currentAccount;
  }

  @override
  Future<AuthAccount> continueAsGuest() async {
    await _simulateNetworkDelay();
    final account = AuthAccount.guest(
      id: _buildId('guest'),
      createdAt: _clock(),
    );
    return _activate(account);
  }

  @override
  Future<AuthAccount> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    _validateEmail(normalizedEmail);
    _validatePassword(password);
    await _simulateNetworkDelay();

    final storedPassword = _passwordsByEmail[normalizedEmail];
    if (storedPassword == null) {
      throw const AuthFailure(
        code: 'account-missing',
        message: 'No account found for that email. Create one first.',
      );
    }
    if (storedPassword != password) {
      throw const AuthFailure(
        code: 'wrong-password',
        message: 'The password does not match this account.',
      );
    }
    final account =
        _accountsById[normalizedEmail] ??
        AuthAccount(
          id: normalizedEmail,
          email: normalizedEmail,
          displayName: _displayNameFromEmail(normalizedEmail),
          provider: AuthProviderKind.emailPassword,
          createdAt: _clock(),
          providerLinkedAt: _clock(),
          emailVerified: true,
          linkedProviders: const {AuthProviderKind.emailPassword},
        );
    return _activate(
      account.copyWith(
        provider: AuthProviderKind.emailPassword,
        emailVerified: true,
        lastReauthenticatedAt: _clock(),
        linkedProviders: const {AuthProviderKind.emailPassword},
      ),
    );
  }

  @override
  Future<AuthAccount> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    _validateEmail(normalizedEmail);
    _validatePassword(password);
    await _simulateNetworkDelay();

    if (_passwordsByEmail.containsKey(normalizedEmail)) {
      throw const AuthFailure(
        code: 'account-exists',
        message: 'An account already exists for this email.',
      );
    }

    _passwordsByEmail[normalizedEmail] = password;
    final account = AuthAccount(
      id: normalizedEmail,
      email: normalizedEmail,
      displayName: (displayName == null || displayName.trim().isEmpty)
          ? _displayNameFromEmail(normalizedEmail)
          : displayName.trim(),
      provider: AuthProviderKind.emailPassword,
      createdAt: _clock(),
      providerLinkedAt: _clock(),
      emailVerified: false,
      linkedProviders: const {AuthProviderKind.emailPassword},
    );
    return _activate(account);
  }

  @override
  Future<AuthAccount> signInWithProvider(AuthProviderKind provider) async {
    if (provider == AuthProviderKind.emailPassword ||
        provider == AuthProviderKind.guest) {
      throw const AuthFailure(
        code: 'invalid-provider',
        message: 'Use an email/password form for that authentication path.',
      );
    }
    await _simulateNetworkDelay();

    final email = '${provider.name}.user@forgeai.dev';
    final account = AuthAccount(
      id: email,
      email: email,
      displayName: '${provider.label} User',
      provider: provider,
      createdAt: _clock(),
      providerLinkedAt: _clock(),
      emailVerified: true,
      linkedProviders: {provider},
    );
    return _activate(account.copyWith(lastReauthenticatedAt: _clock()));
  }

  @override
  Future<AuthAccount> reauthenticate(AuthReauthRequest request) async {
    final account = _currentAccount;
    if (account == null) {
      throw AuthFailure.accountNotFound();
    }
    await _simulateNetworkDelay();

    if (request.provider == AuthProviderKind.emailPassword) {
      final email = _normalizeEmail(request.email ?? account.email);
      final password = request.password ?? '';
      _validateEmail(email);
      _validatePassword(password);
      final storedPassword = _passwordsByEmail[email];
      if (storedPassword == null || storedPassword != password) {
        throw const AuthFailure(
          code: 'reauth-failed',
          message: 'The password did not match the signed-in account.',
        );
      }
      return _activate(
        account.copyWith(
          lastReauthenticatedAt: _clock(),
          provider: AuthProviderKind.emailPassword,
        ),
      );
    }

    if (request.provider == AuthProviderKind.guest) {
      return _activate(
        account.copyWith(
          lastReauthenticatedAt: _clock(),
          provider: AuthProviderKind.guest,
        ),
      );
    }

    if (!account.linkedProviders.contains(request.provider) &&
        account.provider != request.provider) {
      throw const AuthFailure(
        code: 'provider-not-linked',
        message: 'That provider is not linked to the current account.',
      );
    }

    return _activate(
      account.copyWith(
        lastReauthenticatedAt: _clock(),
        provider: request.provider,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    await _simulateNetworkDelay();
    _currentAccount = null;
    _emit(null);
  }

  @override
  Future<void> deleteCurrentAccount({
    required String confirmationPhrase,
  }) async {
    final account = _currentAccount;
    if (account == null) {
      throw AuthFailure.accountNotFound();
    }
    if (confirmationPhrase.trim().toUpperCase() != 'DELETE') {
      throw AuthFailure.invalidConfirmation();
    }
    if (!account.isGuest && !account.canDeleteNow(now: _clock())) {
      throw AuthFailure.authenticationRequired();
    }

    await _simulateNetworkDelay();
    _passwordsByEmail.remove(account.email);
    _accountsById.remove(account.id);
    _currentAccount = null;
    _emit(null);
  }

  AuthAccount _activate(AuthAccount account) {
    _currentAccount = account;
    _accountsById[account.id] = account;
    _emit(account);
    return account;
  }

  void _emit(AuthAccount? account) {
    if (!_accountController.isClosed) {
      _accountController.add(account);
    }
  }

  Future<void> _simulateNetworkDelay() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
  }

  String _buildId(String seed) {
    final timestamp = _clock().microsecondsSinceEpoch.toRadixString(36);
    final normalized = seed
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')
        .toLowerCase();
    return '$normalized-$timestamp';
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  void _validateEmail(String email) {
    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      throw AuthFailure.invalidEmail();
    }
  }

  void _validatePassword(String password) {
    if (password.trim().length < 8) {
      throw AuthFailure.invalidPassword();
    }
  }

  String _displayNameFromEmail(String email) {
    final localPart = email.split('@').first;
    return localPart
        .split(RegExp(r'[._-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}
