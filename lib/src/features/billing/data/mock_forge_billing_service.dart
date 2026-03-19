import 'package:flutter/foundation.dart';

import '../../../core/config/forge_release_config.dart';
import '../../../core/config/forge_economics_config.dart';
import '../domain/forge_billing_service.dart';

/// Mock billing service for development and when StoreKit is not configured.
/// In production, returns notAvailable for purchase attempts until a real
/// implementation (e.g. in_app_purchase or RevenueCat) is wired; subscription
/// state is free. Backend enforces limits for all users except the allowlisted
/// email (unlimited); others must subscribe or buy tokens via paywall.
class MockForgeBillingService implements ForgeBillingService {
  MockForgeBillingService({ForgeSubscriptionState? initialState})
      : _state = initialState ?? const ForgeSubscriptionState();

  ForgeSubscriptionState _state;

  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<ForgeSubscriptionState> get subscriptionState async => _state;

  @override
  Future<ForgeBillingResult> purchaseSubscription(ForgePlanId planId) async {
    if (kReleaseMode || ForgeReleaseConfig.environment.toLowerCase() == 'production') {
      return ForgeBillingResult.notAvailable;
    }
    ForgePlanDefinition? plan;
    for (final p in forgePlans) {
      if (p.id == planId) {
        plan = p;
        break;
      }
    }
    plan ??= forgePlans.first;
    _state = ForgeSubscriptionState(
      planId: planId,
      productId: plan.productId,
      expiresAt: DateTime.now().add(const Duration(days: 30)),
      isActive: true,
      billingMode: ForgeBillingMode.devGrant,
    );
    return ForgeBillingResult.success;
  }

  @override
  Future<ForgeBillingResult> purchaseTokenPack(ForgeTopUpPackId packId) async {
    if (kReleaseMode || ForgeReleaseConfig.environment.toLowerCase() == 'production') {
      return ForgeBillingResult.notAvailable;
    }
    // Dev / simulator: mirror subscription mock so taps give visible feedback.
    // Wallet balance still comes from the backend; use admin or live IAP to credit.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return ForgeBillingResult.success;
  }

  @override
  Future<ForgeBillingResult> get restorePurchases async =>
      ForgeBillingResult.notAvailable;

  @override
  Future<void> devGrantTokens(int amount) async {
    if (kReleaseMode || ForgeReleaseConfig.environment.toLowerCase() == 'production') {
      return;
    }
    // Actual balance update is done via backend / admin; this is a no-op
    // or could call a dev-only Cloud Function.
  }

  @override
  Future<String?> localizedPriceForPlan(ForgePlanId planId) async {
    for (final plan in forgePlans) {
      if (plan.id == planId) {
        if (plan.priceUsd <= 0) return 'Free';
        return '\$${plan.priceUsd.toStringAsFixed(2)}/mo';
      }
    }
    return null;
  }

  @override
  Future<String?> localizedPriceForPack(ForgeTopUpPackId packId) async {
    for (final pack in forgeTopUpPacks) {
      if (pack.id == packId) {
        return '\$${pack.priceUsd.toStringAsFixed(0)}';
      }
    }
    return null;
  }
}
