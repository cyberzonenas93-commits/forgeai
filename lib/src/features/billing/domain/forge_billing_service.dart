import '../../../core/config/forge_economics_config.dart';

/// Result of a purchase or restore operation.
enum ForgeBillingResult {
  success,
  cancelled,
  pending,
  error,
  notAvailable,
}

/// Current subscription state (for UI and enforcement).
class ForgeSubscriptionState {
  const ForgeSubscriptionState({
    this.planId = ForgePlanId.free,
    this.productId,
    this.expiresAt,
    this.isActive = true,
    this.billingMode = ForgeBillingMode.none,
  });

  final ForgePlanId planId;
  final String? productId;
  final DateTime? expiresAt;
  final bool isActive;
  final ForgeBillingMode billingMode;
}

/// How the user is billed (IAP, web, dev grant).
enum ForgeBillingMode {
  none,
  appleIap,
  web,
  devGrant,
}

/// Abstraction for in-app purchases and subscription management.
/// Implementations: Apple IAP, web billing, or mock/dev grants.
abstract class ForgeBillingService {
  /// Whether the billing backend is available (e.g. StoreKit configured).
  Future<bool> get isAvailable;

  /// Current subscription state.
  Future<ForgeSubscriptionState> get subscriptionState;

  /// Request purchase of a subscription [planId].
  Future<ForgeBillingResult> purchaseSubscription(ForgePlanId planId);

  /// Request purchase of a token [packId].
  Future<ForgeBillingResult> purchaseTokenPack(ForgeTopUpPackId packId);

  /// Restore previous purchases (e.g. after reinstall).
  Future<ForgeBillingResult> get restorePurchases;

  /// Grant tokens for development/testing (no-op in production).
  Future<void> devGrantTokens(int amount);

  /// Localized storefront price label for a subscription plan (for UI display).
  /// Returns null when unavailable; callers should fall back to config pricing.
  Future<String?> localizedPriceForPlan(ForgePlanId planId);

  /// Localized storefront price label for a token pack (for UI display).
  /// Returns null when unavailable; callers should fall back to config pricing.
  Future<String?> localizedPriceForPack(ForgeTopUpPackId packId);
}
