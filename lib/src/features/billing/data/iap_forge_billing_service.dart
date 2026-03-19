import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/config/forge_economics_config.dart';
import '../domain/forge_billing_service.dart';

/// Product IDs for StoreKit / Play Billing. Must match App Store Connect and Play Console.
const Set<String> _subscriptionIds = <String>{
  'com.forgeai.app.subscription.pro',
  'com.forgeai.app.subscription.power',
};
const Set<String> _consumableIds = <String>{
  'com.forgeai.app.tokens.small',
  'com.forgeai.app.tokens.medium',
  'com.forgeai.app.tokens.large',
};

/// IAP-backed billing service. Uses in_app_purchase and syncs with backend for wallet/subscription state.
class IAPForgeBillingService implements ForgeBillingService {
  IAPForgeBillingService({
    required FirebaseFunctions functions,
    required String? Function() getCurrentUserId,
  })  : _functions = functions,
        _getCurrentUserId = getCurrentUserId {
    _subscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdated,
      onError: _onPurchaseError,
    );
  }

  final FirebaseFunctions _functions;
  final String? Function() _getCurrentUserId;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final Map<String, ProductDetails> _products = {};
  bool _productsLoaded = false;
  ForgeSubscriptionState _cachedState = const ForgeSubscriptionState();

  @override
  Future<bool> get isAvailable async {
    return await InAppPurchase.instance.isAvailable();
  }

  @override
  Future<ForgeSubscriptionState> get subscriptionState async {
    await _loadProductsIfNeeded();
    final uid = _getCurrentUserId();
    if (uid == null || uid.isEmpty) return _cachedState;
    try {
      final result = await _functions.httpsCallable('getSubscriptionState').call<Map<dynamic, dynamic>>();
      final data = Map<String, dynamic>.from(result.data);
      _cachedState = _subscriptionStateFromMap(data);
      return _cachedState;
    } catch (_) {
      // Backend may not be deployed yet; use cache
    }
    return _cachedState;
  }

  Future<void> _loadProductsIfNeeded() async {
    if (_productsLoaded) return;
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      _productsLoaded = true;
      return;
    }
    final ids = <String>{..._subscriptionIds, ..._consumableIds};
    final response = await InAppPurchase.instance.queryProductDetails(ids);
    if (response.notFoundIDs.isNotEmpty && kDebugMode) {
      debugPrint('IAP: product IDs not found: ${response.notFoundIDs}');
    }
    for (final p in response.productDetails) {
      _products[p.id] = p;
    }
    _productsLoaded = true;
  }

  ProductDetails? _productForPlan(ForgePlanId planId) {
    String? productId;
    for (final p in forgePlans) {
      if (p.id == planId && p.productId != null) {
        productId = p.productId;
        break;
      }
    }
    return productId != null ? _products[productId] : null;
  }

  ProductDetails? _productForPack(ForgeTopUpPackId packId) {
    String? productId;
    for (final p in forgeTopUpPacks) {
      if (p.id == packId) {
        productId = p.productId;
        break;
      }
    }
    return productId != null ? _products[productId] : null;
  }

  @override
  Future<ForgeBillingResult> purchaseSubscription(ForgePlanId planId) async {
    await _loadProductsIfNeeded();
    final product = _productForPlan(planId);
    if (product == null) return ForgeBillingResult.notAvailable;
    try {
      final param = PurchaseParam(productDetails: product);
      final success = await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
      if (!success) return ForgeBillingResult.cancelled;
      return ForgeBillingResult.pending; // actual result via purchaseStream -> syncPurchase
    } catch (e) {
      if (kDebugMode) debugPrint('IAP purchaseSubscription: $e');
      return ForgeBillingResult.error;
    }
  }

  @override
  Future<ForgeBillingResult> purchaseTokenPack(ForgeTopUpPackId packId) async {
    await _loadProductsIfNeeded();
    final product = _productForPack(packId);
    if (product == null) return ForgeBillingResult.notAvailable;
    try {
      final param = PurchaseParam(productDetails: product);
      final success = await InAppPurchase.instance.buyConsumable(purchaseParam: param);
      if (!success) return ForgeBillingResult.cancelled;
      return ForgeBillingResult.pending;
    } catch (e) {
      if (kDebugMode) debugPrint('IAP purchaseTokenPack: $e');
      return ForgeBillingResult.error;
    }
  }

  @override
  Future<ForgeBillingResult> get restorePurchases async {
    await _loadProductsIfNeeded();
    try {
      await InAppPurchase.instance.restorePurchases();
      return ForgeBillingResult.success; // restore triggers purchaseStream; backend syncs
    } catch (e) {
      if (kDebugMode) debugPrint('IAP restorePurchases: $e');
      return ForgeBillingResult.error;
    }
  }

  @override
  Future<void> devGrantTokens(int amount) async {
    // No-op for IAP; use backend/admin for dev grants
  }

  @override
  Future<String?> localizedPriceForPlan(ForgePlanId planId) async {
    await _loadProductsIfNeeded();
    return _productForPlan(planId)?.price;
  }

  @override
  Future<String?> localizedPriceForPack(ForgeTopUpPackId packId) async {
    await _loadProductsIfNeeded();
    return _productForPack(packId)?.price;
  }

  void _onPurchaseUpdated(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _deliverPurchase(purchase);
          if (purchase.pendingCompletePurchase) {
            InAppPurchase.instance.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.error:
          if (kDebugMode) {
            debugPrint('IAP purchase error: ${purchase.error}');
          }
          break;
        case PurchaseStatus.canceled:
          break;
      }
    }
  }

  void _onPurchaseError(dynamic error) {
    if (kDebugMode) debugPrint('IAP purchaseStream error: $error');
  }

  Future<void> _deliverPurchase(PurchaseDetails purchase) async {
    final uid = _getCurrentUserId();
    if (uid == null || uid.isEmpty) return;
    final verification = purchase.verificationData;
    try {
      final callable = _functions.httpsCallable('syncPurchase');
      final result = await callable.call<Map<dynamic, dynamic>>({
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'productId': purchase.productID,
        'purchaseId': purchase.purchaseID,
        'verificationData': verification.serverVerificationData,
        'source': purchase.status == PurchaseStatus.restored ? 'restore' : 'purchase',
      });
      final data = Map<String, dynamic>.from(result.data);
      _cachedState = _subscriptionStateFromMap(data);
    } catch (e) {
      if (kDebugMode) debugPrint('IAP syncPurchase: $e');
    }
  }

  ForgeSubscriptionState _subscriptionStateFromMap(Map<String, dynamic> data) {
    final planIdStr = data['planId'] as String?;
    ForgePlanId planId = ForgePlanId.free;
    for (final p in ForgePlanId.values) {
      if (p.name == planIdStr) {
        planId = p;
        break;
      }
    }
    DateTime? expiresAt;
    final exp = data['expiresAt'];
    if (exp is int) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(exp);
    } else if (exp is String) {
      expiresAt = DateTime.tryParse(exp);
    }
    return ForgeSubscriptionState(
      planId: planId,
      productId: data['productId'] as String?,
      expiresAt: expiresAt,
      isActive: data['isActive'] as bool? ?? true,
      billingMode: ForgeBillingMode.appleIap,
    );
  }

  void dispose() {
    _subscription?.cancel();
  }
}
