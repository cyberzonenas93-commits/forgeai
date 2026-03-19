import 'package:flutter/material.dart';

import '../../../core/config/forge_economics_config.dart';
import '../../../core/observability/forge_telemetry.dart';
import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../domain/forge_billing_service.dart';

class TokenPacksScreen extends StatefulWidget {
  const TokenPacksScreen({
    super.key,
    required this.billingService,
    this.onPurchase,
  });

  final ForgeBillingService billingService;
  final void Function(ForgeTopUpPackId packId)? onPurchase;

  @override
  State<TokenPacksScreen> createState() => _TokenPacksScreenState();
}

class _TokenPacksScreenState extends State<TokenPacksScreen> {
  ForgeTopUpPackId? _purchasingPackId;
  final Map<ForgeTopUpPackId, String> _localizedPrices =
      <ForgeTopUpPackId, String>{};

  @override
  void initState() {
    super.initState();
    ForgeTelemetry.instance.logEvent('forge_token_packs_viewed');
    _loadLocalizedPrices();
  }

  Future<void> _loadLocalizedPrices() async {
    final next = <ForgeTopUpPackId, String>{};
    for (final pack in forgeTopUpPacks) {
      final label = await widget.billingService.localizedPriceForPack(pack.id);
      if (label != null && label.trim().isNotEmpty) {
        next[pack.id] = label.trim();
      }
    }
    if (!mounted) return;
    setState(() {
      _localizedPrices
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _handlePurchase(ForgeTopUpPackId packId) async {
    if (widget.onPurchase != null) {
      widget.onPurchase!(packId);
      return;
    }
    setState(() => _purchasingPackId = packId);
    final result = await widget.billingService.purchaseTokenPack(packId);
    if (!mounted) return;
    setState(() => _purchasingPackId = null);

    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case ForgeBillingResult.success:
        messenger.showSnackBar(
          const SnackBar(content: Text('Token pack purchase completed.')),
        );
      case ForgeBillingResult.pending:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Purchase in progress. Your wallet updates when the store confirms.',
            ),
          ),
        );
      case ForgeBillingResult.cancelled:
        break;
      case ForgeBillingResult.error:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Purchase failed. Try again later.'),
          ),
        );
      case ForgeBillingResult.notAvailable:
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Store purchases are not available. On iOS Simulator, open the '
              'scheme’s StoreKit configuration in Xcode, or test on a device with '
              'a Sandbox Apple ID. Mock billing uses a dev-only simulated purchase.',
            ),
          ),
        );
    }
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
        title: const Text('Token packs'),
      ),
      body: ForgeScreen(
        child: ListView(
          children: [
            const ForgeSectionHeader(
              title: 'Get more tokens',
              subtitle:
                  'Top up when you need extra. Tokens never expire and stack with your plan.',
            ),
            const SizedBox(height: 20),
            ...forgeTopUpPacks.map((pack) => _PackCard(
                  pack: pack,
                  localizedPriceLabel: _localizedPrices[pack.id],
                  busy: _purchasingPackId == pack.id,
                  anyBusy: _purchasingPackId != null,
                  onPurchase: () => _handlePurchase(pack.id),
                )),
          ],
        ),
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.localizedPriceLabel,
    required this.onPurchase,
    required this.busy,
    required this.anyBusy,
  });

  final ForgeTopUpPackDefinition pack;
  final String? localizedPriceLabel;
  final VoidCallback onPurchase;
  final bool busy;
  final bool anyBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final valuePerToken = pack.priceUsd / pack.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ForgePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${pack.tokens} tokens',
                  style: theme.titleMedium?.copyWith(
                    color: ForgePalette.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  localizedPriceLabel ?? '\$${pack.priceUsd.toStringAsFixed(0)}',
                  style: theme.titleLarge?.copyWith(
                    color: ForgePalette.glowAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '\$${valuePerToken.toStringAsFixed(3)} per token',
              style: theme.bodySmall?.copyWith(color: ForgePalette.textSecondary),
            ),
            const SizedBox(height: 12),
            ForgePrimaryButton(
              label: busy ? 'Processing…' : 'Buy ${pack.tokens} tokens',
              onPressed: anyBusy ? null : onPurchase,
              expanded: true,
            ),
          ],
        ),
      ),
    );
  }
}
