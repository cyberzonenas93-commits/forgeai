import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({
    super.key,
    required this.controller,
    this.onUpgrade,
    this.onGetTokens,
  });

  final ForgeWorkspaceController controller;
  final VoidCallback? onUpgrade;
  final VoidCallback? onGetTokens;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final wallet = state.wallet;
        final logs = state.tokenLogs;
        final usageRatio = wallet.monthlyAllowance == 0
            ? 0.0
            : (wallet.spentThisWeek / wallet.monthlyAllowance).clamp(0.0, 1.0);

        final canPop = Navigator.of(context).canPop();

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: canPop
              ? AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                )
              : null,
          body: ForgeScreen(
            child: ListView(
              children: [
                ForgePanel(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ForgeSectionHeader(
                        title: 'Wallet',
                        subtitle:
                            'Track token usage, understand cost before AI runs, and keep team usage inside predictable limits.',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${wallet.balance.toInt()} ${wallet.currencySymbol}',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: usageRatio,
                        minHeight: 10,
                        backgroundColor: ForgePalette.surfaceElevated,
                        color: ForgePalette.glowAccent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${wallet.spentThisWeek.toInt()} used this period • next refresh ${wallet.nextReset}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (onUpgrade != null || onGetTokens != null) ...[
                        const SizedBox(height: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (onUpgrade != null)
                              ForgeSecondaryButton(
                                label: 'Upgrade plan',
                                icon: Icons.workspace_premium_rounded,
                                onPressed: onUpgrade,
                                expanded: true,
                              ),
                            if (onUpgrade != null && onGetTokens != null)
                              const SizedBox(height: 12),
                            if (onGetTokens != null)
                              ForgePrimaryButton(
                                label: 'Get tokens',
                                icon: Icons.add_rounded,
                                onPressed: onGetTokens,
                                expanded: true,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final useSingleColumn = constraints.maxWidth < 640;
                    final tileWidth = useSingleColumn
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 12) / 2;
                    final tiles = [
                      ForgeMetricTile(
                        label: 'Monthly allowance',
                        value: '${wallet.monthlyAllowance.toInt()}',
                        detail: wallet.planName,
                        icon: Icons.shield_outlined,
                        accent: ForgePalette.glowAccent,
                      ),
                      ForgeMetricTile(
                        label: 'Average task',
                        value: logs.isEmpty
                            ? '0'
                            : '${(logs.map((entry) => int.tryParse(entry.cost) ?? 0).reduce((a, b) => a + b) / logs.length).round()}',
                        detail: 'tokens per run',
                        icon: Icons.auto_awesome_rounded,
                        accent: ForgePalette.success,
                      ),
                    ];
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final tile in tiles)
                          SizedBox(width: tileWidth, child: tile),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                ForgePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Usage history',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (logs.isEmpty)
                        Text(
                          'Token reservations and captures will appear here after AI actions.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        ...logs.map(
                          (log) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: ForgePalette.primaryAccentSoft,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long_rounded,
                                    color: ForgePalette.glowAccent,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        log.action,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${log.repo} • ${log.timestamp}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '-${log.cost}',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(color: ForgePalette.error),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
