import 'auth_provider_kind.dart';

class AuthAccount {
  const AuthAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.provider,
    required this.createdAt,
    required this.providerLinkedAt,
    this.isGuest = false,
    this.avatarUrl,
    this.lastReauthenticatedAt,
    this.emailVerified = false,
    this.linkedProviders = const <AuthProviderKind>{},
  });

  factory AuthAccount.guest({required String id, DateTime? createdAt}) {
    final now = createdAt ?? DateTime.now();
    return AuthAccount(
      id: id,
      email: 'guest@$id.forgeai.local',
      displayName: 'Guest Session',
      provider: AuthProviderKind.guest,
      createdAt: now,
      providerLinkedAt: now,
      isGuest: true,
      emailVerified: false,
      linkedProviders: const {AuthProviderKind.guest},
    );
  }

  final String id;
  final String email;
  final String displayName;
  final AuthProviderKind provider;
  final DateTime createdAt;
  final DateTime providerLinkedAt;
  final bool isGuest;
  final String? avatarUrl;
  final DateTime? lastReauthenticatedAt;
  final bool emailVerified;
  final Set<AuthProviderKind> linkedProviders;

  bool get supportsDeletionByConfirmation => true;

  bool canDeleteNow({DateTime? now}) {
    if (isGuest) {
      return true;
    }
    final reauthAt = lastReauthenticatedAt;
    if (reauthAt == null) {
      return false;
    }
    final current = now ?? DateTime.now();
    return current.difference(reauthAt).inMinutes < 10;
  }

  AuthAccount copyWith({
    String? id,
    String? email,
    String? displayName,
    AuthProviderKind? provider,
    DateTime? createdAt,
    DateTime? providerLinkedAt,
    bool? isGuest,
    String? avatarUrl,
    DateTime? lastReauthenticatedAt,
    bool? emailVerified,
    Set<AuthProviderKind>? linkedProviders,
  }) {
    return AuthAccount(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      provider: provider ?? this.provider,
      createdAt: createdAt ?? this.createdAt,
      providerLinkedAt: providerLinkedAt ?? this.providerLinkedAt,
      isGuest: isGuest ?? this.isGuest,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastReauthenticatedAt:
          lastReauthenticatedAt ?? this.lastReauthenticatedAt,
      emailVerified: emailVerified ?? this.emailVerified,
      linkedProviders: linkedProviders ?? this.linkedProviders,
    );
  }

  String get initials {
    final words = displayName.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) {
      return 'F';
    }
    if (words.length == 1) {
      final first = words.first.trim();
      return first.isEmpty ? 'F' : first.substring(0, 1).toUpperCase();
    }
    final first = words.first.isNotEmpty ? words.first.substring(0, 1) : 'F';
    final last = words.last.isNotEmpty ? words.last.substring(0, 1) : 'A';
    return '$first$last'.toUpperCase();
  }
}
