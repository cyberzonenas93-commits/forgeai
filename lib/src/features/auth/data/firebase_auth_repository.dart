import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../../core/branding/app_branding.dart';
import '../../../core/config/forge_runtime_config.dart';
import '../domain/auth_account.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_provider_kind.dart';
import '../domain/auth_reauth_request.dart';
import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  static Future<void>? _googleSignInInitialization;

  String get _githubCallbackUrl {
    final projectId = Firebase.app().options.projectId;
    if (projectId.isEmpty) {
      return 'https://<firebase-project>.firebaseapp.com/__/auth/handler';
    }
    return 'https://$projectId.firebaseapp.com/__/auth/handler';
  }

  @override
  Stream<AuthAccount?> watchCurrentAccount() {
    return _auth.authStateChanges().map(_mapUser);
  }

  @override
  Future<AuthAccount?> bootstrap() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    await user.reload();
    return _mapUser(_auth.currentUser ?? user);
  }

  @override
  Future<AuthAccount> continueAsGuest() async {
    final credential = await _auth.signInAnonymously();
    return _requireAccount(credential.user, fallback: AuthProviderKind.guest);
  }

  @override
  Future<AuthAccount> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _requireAccount(
        credential.user,
        fallback: AuthProviderKind.emailPassword,
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<AuthAccount> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthFailure(
          code: 'account-missing',
          message: 'Account creation succeeded but no user session exists.',
        );
      }
      final trimmedDisplayName = displayName?.trim();
      if (trimmedDisplayName != null && trimmedDisplayName.isNotEmpty) {
        try {
          await user.updateDisplayName(trimmedDisplayName);
          await user.reload();
        } catch (e, stack) {
          // User is already created and signed in; profile sync must not fail signup.
          debugPrint('auth: signup profile sync failed: $e');
          debugPrintStack(stackTrace: stack);
        }
      }
      return _requireAccount(
        _auth.currentUser ?? user,
        fallback: AuthProviderKind.emailPassword,
      );
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<AuthAccount> signInWithProvider(AuthProviderKind provider) async {
    try {
      final credential = await _signInWithProvider(provider);
      if (provider == AuthProviderKind.github) {
        await _syncGithubConnection(credential);
      }
      return _requireAccount(credential.user, fallback: provider);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error, provider: provider);
    }
  }

  @override
  Future<AuthAccount> reauthenticate(AuthReauthRequest request) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AuthFailure.accountNotFound();
    }

    try {
      switch (request.provider) {
        case AuthProviderKind.emailPassword:
          if (!_providerMatches(user, AuthProviderKind.emailPassword)) {
            throw const AuthFailure(
              code: 'provider-not-linked',
              message: 'That account does not have a password credential.',
            );
          }
          final email = (request.email ?? user.email ?? '').trim();
          final password = request.password ?? '';
          final credential = EmailAuthProvider.credential(
            email: email,
            password: password,
          );
          await user.reauthenticateWithCredential(credential);
          await user.reload();
          return _requireAccount(
            _auth.currentUser ?? user,
            fallback: AuthProviderKind.emailPassword,
            reauthenticatedAt: DateTime.now(),
          );
        case AuthProviderKind.google:
          _requireProviderLink(user, AuthProviderKind.google);
          final credential = await _authenticateGoogleUser(
            cancellationMessage: 'Google re-authentication was cancelled.',
          );
          final auth = credential.authentication;
          final firebaseCredential = GoogleAuthProvider.credential(
            idToken: auth.idToken,
          );
          await user.reauthenticateWithCredential(firebaseCredential);
          await user.reload();
          return _requireAccount(
            _auth.currentUser ?? user,
            fallback: AuthProviderKind.google,
            reauthenticatedAt: DateTime.now(),
          );
        case AuthProviderKind.apple:
          _requireProviderLink(user, AuthProviderKind.apple);
          final credential = AppleAuthProvider();
          await user.reauthenticateWithProvider(credential);
          await user.reload();
          return _requireAccount(
            _auth.currentUser ?? user,
            fallback: AuthProviderKind.apple,
            reauthenticatedAt: DateTime.now(),
          );
        case AuthProviderKind.github:
          _requireProviderLink(user, AuthProviderKind.github);
          final credential = GithubAuthProvider();
          await user.reauthenticateWithProvider(credential);
          await user.reload();
          return _requireAccount(
            _auth.currentUser ?? user,
            fallback: AuthProviderKind.github,
            reauthenticatedAt: DateTime.now(),
          );
        case AuthProviderKind.guest:
          if (!user.isAnonymous) {
            throw const AuthFailure(
              code: 'invalid-provider',
              message:
                  'Guest re-authentication only applies to guest sessions.',
            );
          }
          return _requireAccount(
            user,
            fallback: AuthProviderKind.guest,
            reauthenticatedAt: DateTime.now(),
          );
      }
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error, provider: request.provider, isReauth: true);
    }
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  @override
  Future<void> deleteCurrentAccount({
    required String confirmationPhrase,
  }) async {
    if (confirmationPhrase.trim().toUpperCase() != 'DELETE') {
      throw AuthFailure.invalidConfirmation();
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw AuthFailure.accountNotFound();
    }

    try {
      await user.delete();
      await _googleSignIn.signOut();
      await _auth.signOut();
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  Future<UserCredential> _signInWithProvider(AuthProviderKind provider) {
    switch (provider) {
      case AuthProviderKind.google:
        return _signInWithGoogle();
      case AuthProviderKind.apple:
        return _auth.signInWithProvider(AppleAuthProvider());
      case AuthProviderKind.github:
        return _auth.signInWithProvider(_githubProvider());
      case AuthProviderKind.emailPassword:
        throw const AuthFailure(
          code: 'invalid-provider',
          message: 'Use email and password for that sign-in path.',
        );
      case AuthProviderKind.guest:
        throw const AuthFailure(
          code: 'invalid-provider',
          message: 'Guest access uses the continue as guest action.',
        );
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    final googleUser = await _authenticateGoogleUser(
      cancellationMessage: 'Google sign-in was cancelled.',
    );
    final googleAuth = googleUser.authentication;
    if (googleAuth.idToken == null) {
      throw AuthFailure(
        code: 'credential-missing',
        message: 'Google sign-in did not return the required tokens.',
      );
    }
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<GoogleSignInAccount> _authenticateGoogleUser({
    required String cancellationMessage,
  }) async {
    try {
      await _ensureGoogleSignInInitialized();
      return await _googleSignIn.authenticate(
        scopeHint: const ['email', 'profile'],
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted ||
          error.code == GoogleSignInExceptionCode.uiUnavailable) {
        throw AuthFailure(code: 'cancelled', message: cancellationMessage);
      }
      throw AuthFailure(
        code: error.code.name,
        message: error.description ?? cancellationMessage,
      );
    }
  }

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInInitialization ??= _googleSignIn.initialize();
  }

  GithubAuthProvider _githubProvider() {
    return GithubAuthProvider()
      ..addScope('repo')
      ..addScope('workflow')
      ..addScope('read:user')
      ..addScope('user:email');
  }

  Future<void> _syncGithubConnection(UserCredential credential) async {
    final accessToken = credential.credential?.accessToken?.trim();
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    // Bypass the iOS cloud_functions SDK entirely — it persistently fails to
    // include the Firebase Auth token. Instead, call the Cloud Function
    // directly via HTTP with an explicit Authorization header.
    try {
      final idToken = await _auth.currentUser?.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        debugPrint('$kAppDisplayName GitHub sync: no ID token available');
        return;
      }

      final config = ForgeRuntimeConfig.current;
      final uri = Uri.parse(
        'https://${config.firebaseRegion}-${config.firebaseProjectId}.cloudfunctions.net/syncProviderConnection',
      );

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'data': {'provider': 'github', 'accessToken': accessToken},
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          '$kAppDisplayName GitHub connection sync failed: HTTP ${response.statusCode} ${response.body}',
        );
      }
    } catch (error) {
      debugPrint('$kAppDisplayName GitHub connection sync failed: $error');
    }
  }

  void _requireProviderLink(User user, AuthProviderKind provider) {
    if (!_providerMatches(user, provider)) {
      throw AuthFailure(
        code: 'provider-not-linked',
        message: 'That provider is not linked to the current account.',
      );
    }
  }

  bool _providerMatches(User user, AuthProviderKind provider) {
    if (user.isAnonymous) {
      return provider == AuthProviderKind.guest;
    }
    final linkedProviders = user.providerData
        .map((data) => _providerKindFromId(data.providerId))
        .whereType<AuthProviderKind>()
        .toSet();
    return linkedProviders.contains(provider);
  }

  AuthAccount _requireAccount(
    User? user, {
    required AuthProviderKind fallback,
    DateTime? reauthenticatedAt,
  }) {
    if (user == null) {
      throw const AuthFailure(
        code: 'account-missing',
        message: 'The authenticated user is unavailable.',
      );
    }
    final mapped = _mapUser(
      user,
      fallback: fallback,
      reauthenticatedAt: reauthenticatedAt,
    );
    if (mapped == null) {
      throw const AuthFailure(
        code: 'account-missing',
        message: 'The authenticated user is unavailable.',
      );
    }
    return mapped;
  }

  AuthAccount? _mapUser(
    User? user, {
    AuthProviderKind? fallback,
    DateTime? reauthenticatedAt,
  }) {
    if (user == null) {
      return null;
    }
    if (user.isAnonymous) {
      return AuthAccount.guest(
        id: user.uid,
        createdAt: _parseDate(user.metadata.creationTime) ?? DateTime.now(),
      ).copyWith(
        avatarUrl: user.photoURL,
        lastReauthenticatedAt:
            reauthenticatedAt ??
            _parseDate(user.metadata.lastSignInTime) ??
            _parseDate(user.metadata.creationTime),
      );
    }

    final linkedProviders = user.providerData
        .map((data) => _providerKindFromId(data.providerId))
        .whereType<AuthProviderKind>()
        .toSet();
    final provider =
        _primaryProvider(user) ?? fallback ?? AuthProviderKind.guest;
    final displayName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : _displayNameFor(user, provider);
    final email = user.email?.trim().isNotEmpty == true
        ? user.email!.trim()
        : _fallbackEmailFor(user, provider);

    return AuthAccount(
      id: user.uid,
      email: email,
      displayName: displayName,
      provider: provider,
      createdAt: _parseDate(user.metadata.creationTime) ?? DateTime.now(),
      providerLinkedAt:
          _parseDate(user.metadata.creationTime) ??
          _parseDate(user.metadata.lastSignInTime) ??
          DateTime.now(),
      avatarUrl: user.photoURL,
      lastReauthenticatedAt:
          reauthenticatedAt ??
          _parseDate(user.metadata.lastSignInTime) ??
          _parseDate(user.metadata.creationTime),
      emailVerified: user.emailVerified,
      linkedProviders: linkedProviders.isEmpty ? {provider} : linkedProviders,
    );
  }

  AuthProviderKind? _primaryProvider(User user) {
    if (user.isAnonymous) {
      return AuthProviderKind.guest;
    }
    for (final provider in user.providerData) {
      final mapped = _providerKindFromId(provider.providerId);
      if (mapped != null) {
        return mapped;
      }
    }
    return null;
  }

  AuthProviderKind? _providerKindFromId(String providerId) {
    switch (providerId) {
      case 'firebase':
        return AuthProviderKind.guest;
      case 'password':
        return AuthProviderKind.emailPassword;
      case 'google.com':
        return AuthProviderKind.google;
      case 'apple.com':
        return AuthProviderKind.apple;
      case 'github.com':
        return AuthProviderKind.github;
      default:
        return null;
    }
  }

  String _displayNameFor(User user, AuthProviderKind provider) {
    final emailName = user.email;
    if (emailName != null && emailName.contains('@')) {
      final localPart = emailName.split('@').first;
      final words = localPart
          .split(RegExp(r'[._-]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => part[0].toUpperCase() + part.substring(1));
      final result = words.join(' ').trim();
      if (result.isNotEmpty) {
        return result;
      }
    }
    return switch (provider) {
      AuthProviderKind.google => 'Google User',
      AuthProviderKind.apple => 'Apple User',
      AuthProviderKind.github => 'GitHub User',
      AuthProviderKind.emailPassword => '$kAppDisplayName User',
      AuthProviderKind.guest => 'Guest Session',
    };
  }

  String _fallbackEmailFor(User user, AuthProviderKind provider) {
    if (provider == AuthProviderKind.guest) {
      return 'guest@${user.uid}.forgeai.local';
    }
    return '${provider.name}.user@forgeai.dev';
  }

  DateTime? _parseDate(DateTime? value) {
    return value;
  }

  AuthFailure _mapAuthError(
    FirebaseAuthException error, {
    AuthProviderKind? provider,
    bool isReauth = false,
  }) {
    switch (error.code) {
      case 'invalid-email':
        return AuthFailure.invalidEmail(
          error.message ?? 'Enter a valid email address.',
        );
      case 'wrong-password':
      case 'user-not-found':
        return AuthFailure(
          code: error.code,
          message: error.message ?? 'The email or password does not match.',
        );
      case 'weak-password':
        return AuthFailure.invalidPassword(
          error.message ?? 'Use at least 8 characters.',
        );
      case 'email-already-in-use':
      case 'account-exists-with-different-credential':
        return AuthFailure(
          code: error.code,
          message: error.message ?? 'An account already exists for that email.',
        );
      case 'operation-not-allowed':
        if (provider == AuthProviderKind.github) {
          return AuthFailure(
            code: error.code,
            message:
                'GitHub sign-in is not configured yet. Enable GitHub in Firebase Authentication, add your GitHub OAuth client ID and secret, and set the callback URL to $_githubCallbackUrl.',
            recoverable: false,
          );
        }
        return AuthFailure(
          code: error.code,
          message: error.message ?? 'Firebase authentication failed.',
          recoverable: false,
        );
      case 'requires-recent-login':
        return AuthFailure.authenticationRequired(
          error.message ?? 'Re-authentication is required before this action.',
        );
      case 'invalid-credential':
        if (provider == AuthProviderKind.github) {
          return AuthFailure(
            code: error.code,
            message:
                'GitHub sign-in could not complete. Check the GitHub OAuth app client secret and confirm the callback URL matches $_githubCallbackUrl.',
            recoverable: !isReauth,
          );
        }
        return AuthFailure(
          code: error.code,
          message: error.message ?? 'The email or password does not match.',
        );
      case 'user-disabled':
      case 'network-request-failed':
      case 'too-many-requests':
        return AuthFailure(
          code: error.code,
          message: error.message ?? 'Firebase authentication failed.',
          recoverable:
              error.code == 'network-request-failed' ||
              error.code == 'too-many-requests',
        );
      case 'web-context-cancelled':
      case 'popup-closed-by-user':
      case 'canceled':
        return AuthFailure(
          code: 'cancelled',
          message: error.message ?? 'The authentication flow was cancelled.',
        );
      default:
        if (provider == AuthProviderKind.github) {
          return AuthFailure(
            code: error.code,
            message:
                error.message ??
                'GitHub sign-in failed. Verify the GitHub provider is enabled in Firebase Authentication and that the OAuth callback URL is $_githubCallbackUrl.',
          );
        }
        return AuthFailure(
          code: error.code,
          message: error.message ?? 'Firebase authentication failed.',
        );
    }
  }
}
