/// Centralized token economics and monetization config (see `app_branding.dart` for display name).
/// Single source for action prices, plan/pack definitions, and display values.
/// Backend pricing lives in functions/src/pricing.ts and economics-config.ts.
library;

/// Plan identifier.
enum ForgePlanId {
  free,
  pro,
  power,
}

/// Model tier for routing (basic = cheapest, priority = premium).
enum ForgeModelTier {
  basic,
  standard,
  priority,
}

/// Top-up pack identifier.
enum ForgeTopUpPackId {
  packSmall,
  packMedium,
  packLarge,
}

/// User-facing value: 1 Forge token ≈ \$0.05 effective value (actions).
const double forgeTokenValueUsd = 0.05;

/// Target gross margin multiplier on AI cost (minimum).
const int marginTargetMultiplier = 5;

/// Preferred margin multiplier where feasible.
const int marginTargetMultiplierPreferred = 8;

/// Apple IAP cut assumption (worst case).
const int appleCutPercent = 30;

/// Default action token costs. Backend is source of truth; this is for UI preview and display.
const Map<String, int> actionTokenCosts = <String, int>{
  'explain_code': 2,
  'fix_bug': 6,
  'generate_tests': 8,
  'refactor_code': 10,
  'deep_repo_analysis': 25,
  'ai_suggestion': 8,
  'ai_project_scaffold': 40,
  'create_branch': 12,
  'commit': 24,
  'open_pr': 16,
  'merge_pr': 18,
  'run_tests': 30,
  'run_lint': 10,
  'build_project': 40,
};

/// Human-readable action labels for UI.
const Map<String, String> actionLabels = <String, String>{
  'explain_code': 'Explain code',
  'fix_bug': 'Fix bug',
  'generate_tests': 'Generate tests',
  'refactor_code': 'Refactor code',
  'deep_repo_analysis': 'Deep repo analysis',
  'ai_suggestion': 'Agent run',
  'ai_project_scaffold': 'New project (AI)',
  'create_branch': 'Create branch',
  'commit': 'Commit',
  'open_pr': 'Open PR',
  'merge_pr': 'Merge PR',
  'run_tests': 'Run tests',
  'run_lint': 'Run lint',
  'build_project': 'Build project',
};

/// Plan definition for paywall and settings.
class ForgePlanDefinition {
  const ForgePlanDefinition({
    required this.id,
    required this.displayName,
    required this.priceUsd,
    required this.appleNetUsdAt30,
    required this.monthlyIncludedTokens,
    required this.dailyActionCap,
    required this.allowedModelTier,
    this.productId,
  });

  final ForgePlanId id;
  final String displayName;
  final double priceUsd;
  final double appleNetUsdAt30;
  final int monthlyIncludedTokens;
  final int dailyActionCap;
  final ForgeModelTier allowedModelTier;
  final String? productId;
}

/// Top-up pack for token purchase UI.
class ForgeTopUpPackDefinition {
  const ForgeTopUpPackDefinition({
    required this.id,
    required this.productId,
    required this.tokens,
    required this.priceUsd,
    required this.appleNetUsdAt30,
  });

  final ForgeTopUpPackId id;
  final String productId;
  final int tokens;
  final double priceUsd;
  final double appleNetUsdAt30;
}

/// All subscription plans (Free, Pro, Power).
const List<ForgePlanDefinition> forgePlans = <ForgePlanDefinition>[
  ForgePlanDefinition(
    id: ForgePlanId.free,
    displayName: 'Free',
    priceUsd: 0,
    appleNetUsdAt30: 0,
    monthlyIncludedTokens: 20,
    dailyActionCap: 10,
    allowedModelTier: ForgeModelTier.basic,
    productId: null,
  ),
  ForgePlanDefinition(
    id: ForgePlanId.pro,
    displayName: 'Pro',
    priceUsd: 14.99,
    appleNetUsdAt30: 10.49,
    monthlyIncludedTokens: 300,
    dailyActionCap: 50,
    allowedModelTier: ForgeModelTier.standard,
    productId: 'com.forgeai.app.subscription.pro',
  ),
  ForgePlanDefinition(
    id: ForgePlanId.power,
    displayName: 'Power',
    priceUsd: 29.99,
    appleNetUsdAt30: 20.99,
    monthlyIncludedTokens: 800,
    dailyActionCap: 150,
    allowedModelTier: ForgeModelTier.priority,
    productId: 'com.forgeai.app.subscription.power',
  ),
];

/// All top-up packs.
const List<ForgeTopUpPackDefinition> forgeTopUpPacks = <ForgeTopUpPackDefinition>[
  ForgeTopUpPackDefinition(
    id: ForgeTopUpPackId.packSmall,
    productId: 'com.forgeai.app.tokens.small',
    tokens: 100,
    priceUsd: 5.99,
    appleNetUsdAt30: 4.19,
  ),
  ForgeTopUpPackDefinition(
    id: ForgeTopUpPackId.packMedium,
    productId: 'com.forgeai.app.tokens.medium',
    tokens: 300,
    priceUsd: 14.99,
    appleNetUsdAt30: 10.49,
  ),
  ForgeTopUpPackDefinition(
    id: ForgeTopUpPackId.packLarge,
    productId: 'com.forgeai.app.tokens.large',
    tokens: 1000,
    priceUsd: 34.99,
    appleNetUsdAt30: 24.49,
  ),
];

/// Returns token cost for an action type (for UI preview). Returns null if unknown.
int? tokenCostForAction(String actionType) => actionTokenCosts[actionType];

/// Returns display label for an action type.
String labelForAction(String actionType) =>
    actionLabels[actionType] ?? actionType;
