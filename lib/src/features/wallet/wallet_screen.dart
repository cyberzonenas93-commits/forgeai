import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key, required this.controller});

  final ForgeWorkspaceController controller;

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

        return Scaffold(
          backgroundColor: Colors.transparent,
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
                        '${wallet.spentThisWeek.toInt()} used this week • resets ${wallet.nextReset}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ForgeMetricTile(
                        label: 'Monthly allowance',
                        value: '${wallet.monthlyAllowance.toInt()}',
                        detail: wallet.planName,
                        icon: Icons.shield_outlined,
                        accent: ForgePalette.glowAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ForgeMetricTile(
                        label: 'Average task',
                        value: logs.isEmpty
                            ? '0'
                            : '${(logs.map((entry) => int.tryParse(entry.cost) ?? 0).reduce((a, b) => a + b) / logs.length).round()}',
                        detail: 'tokens per run',
                        icon: Icons.auto_awesome_rounded,
                        accent: ForgePalette.success,
                      ),
                    ),
                  ],
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
