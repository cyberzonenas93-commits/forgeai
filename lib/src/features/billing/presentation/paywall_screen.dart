import 'package:flutter/material.dart';

import '../../../core/config/forge_economics_config.dart';
import '../../../core/observability/forge_telemetry.dart';
import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../domain/forge_billing_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.billingService,
    this.currentPlanId = ForgePlanId.free,
    this.onUpgrade,
    this.onRestore,
  });

  final ForgeBillingService billingService;
  final ForgePlanId currentPlanId;
  final void Function(ForgePlanId)? onUpgrade;
  final VoidCallback? onRestore;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final Map<ForgePlanId, String> _localizedPrices = <ForgePlanId, String>{};

  @override
  void initState() {
    super.initState();
    ForgeTelemetry.instance.logEvent('forge_paywall_viewed');
    _loadLocalizedPrices();
  }

  Future<void> _loadLocalizedPrices() async {
    final next = <ForgePlanId, String>{};
    for (final plan in forgePlans) {
      final label = await widget.billingService.localizedPriceForPlan(plan.id);
      if (label != null && label.trim().isNotEmpty) {
        next[plan.id] = label.trim();
      }
    }
    if (!mounted) return;
    setState(() {
      _localizedPrices
        ..clear()
        ..addAll(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Upgrade'),
      ),
      body: ForgeScreen(
        child: ListView(
          children: [
            const ForgeSectionHeader(
              title: 'Choose your plan',
              subtitle:
                  'More tokens, higher limits, and better models. Upgrade anytime.',
            ),
            const SizedBox(height: 20),
            ...forgePlans.map((plan) => _PlanCard(
                  plan: plan,
                  localizedPriceLabel: _localizedPrices[plan.id],
                  isCurrent: plan.id == widget.currentPlanId,
                  onSelect: () => widget.onUpgrade?.call(plan.id),
                )),
            const SizedBox(height: 24),
            TextButton(
              onPressed: widget.onRestore,
              child: Text(
                'Restore purchases',
                style: TextStyle(color: ForgePalette.glowAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.localizedPriceLabel,
    required this.isCurrent,
    required this.onSelect,
  });

  final ForgePlanDefinition plan;
  final String? localizedPriceLabel;
  final bool isCurrent;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ForgePanel(
        highlight: isCurrent,
        onTap: plan.id == ForgePlanId.free ? null : onSelect,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  plan.displayName,
                  style: theme.titleMedium?.copyWith(
                    color: ForgePalette.textPrimary,
                  ),
                ),
                const Spacer(),
                if (plan.priceUsd > 0)
                  Text(
                    localizedPriceLabel ??
                        '\$${plan.priceUsd.toStringAsFixed(2)}/mo',
                    style: theme.titleMedium?.copyWith(
                      color: ForgePalette.glowAccent,
                    ),
                  )
                else
                  Text(
                    'Free',
                    style: theme.titleMedium?.copyWith(
                      color: ForgePalette.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${plan.monthlyIncludedTokens} tokens/mo • ${plan.dailyActionCap} actions/day',
              style: theme.bodySmall?.copyWith(color: ForgePalette.textSecondary),
            ),
            if (plan.id != ForgePlanId.free) ...[
              const SizedBox(height: 12),
              ForgePrimaryButton(
                label: isCurrent ? 'Current plan' : 'Upgrade to ${plan.displayName}',
                onPressed: isCurrent ? null : onSelect,
                expanded: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
