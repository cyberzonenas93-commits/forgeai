import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    this.onOpenRepository,
    this.onOpenHub,
    this.onOpenEditor,
    this.onOpenChecks,
    this.onOpenWallet,
    this.onOpenActivity,
  });

  final ForgeWorkspaceController controller;
  final VoidCallback? onOpenRepository;
  final VoidCallback? onOpenHub;
  final VoidCallback? onOpenEditor;
  final VoidCallback? onOpenChecks;
  final VoidCallback? onOpenWallet;
  final VoidCallback? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final repositories = state.repositories;
        final activities = state.activities;
        final checks = state.checks;
        final wallet = state.wallet;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final compactLayout = screenWidth < 380;
        final metricColumns = screenWidth < 360 ? 1 : 2;
        final metricAspectRatio = screenWidth < 360 ? 2.1 : 1.18;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                ForgePanel(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.start,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          const ForgeBrandMark(size: 58),
                          ForgePill(
                            label: state.isBootstrapping
                                ? 'Syncing workspace'
                                : 'Premium mobile Git',
                            icon: state.isBootstrapping
                                ? Icons.sync_rounded
                                : Icons.bolt_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Control your codebase from anywhere.',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        repositories.isEmpty
                            ? 'Connect a GitHub or GitLab repository to start browsing code, reviewing diffs, and triggering CI from mobile.'
                            : 'Browse repositories, pick one, and use Prompt to vibecode changes in plain language.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: ForgePalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ForgePrimaryButton(
                            label: repositories.isEmpty
                                ? 'Connect repository'
                                : 'Open Prompt',
                            icon: repositories.isEmpty
                                ? Icons.link_rounded
                                : Icons.chat_bubble_outline_rounded,
                            onPressed: repositories.isEmpty
                                ? onOpenRepository
                                : onOpenEditor,
                          ),
                          if (onOpenHub != null)
                            ForgeSecondaryButton(
                              label: 'Account hub',
                              icon: Icons.hub_rounded,
                              onPressed: onOpenHub,
                            ),
                          if (onOpenChecks != null)
                            ForgeSecondaryButton(
                              label: 'Run checks',
                              icon: Icons.play_circle_fill_rounded,
                              onPressed: onOpenChecks,
                            ),
                          ForgeSecondaryButton(
                            label: 'Wallet',
                            icon: Icons.account_balance_wallet_rounded,
                            onPressed: onOpenWallet,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  crossAxisCount: metricColumns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: metricAspectRatio,
                  children: [
                    ForgeMetricTile(
                      label: 'Token balance',
                      value: '${wallet.balance.toInt()}',
                      detail:
                          '${wallet.monthlyAllowance.toInt()} monthly allowance',
                      icon: Icons.token_rounded,
                    ),
                    ForgeMetricTile(
                      label: 'Active repos',
                      value: '${repositories.length}',
                      detail: repositories.isEmpty
                          ? 'Connect GitHub or GitLab'
                          : '${repositories.first.changedFiles} staged file changes',
                      icon: Icons.folder_copy_rounded,
                      accent: ForgePalette.primaryAccent,
                    ),
                    ForgeMetricTile(
                      label: 'Checks passing',
                      value: checks.isEmpty
                          ? '0/0'
                          : '${checks.where((check) => check.status == ForgeCheckStatus.passed).length}/${checks.length}',
                      detail: 'CI workflows available from mobile',
                      icon: Icons.verified_rounded,
                      accent: ForgePalette.success,
                    ),
                    ForgeMetricTile(
                      label: 'Recent review',
                      value: activities.isEmpty
                          ? 'No activity'
                          : activities.first.timestamp,
                      detail: activities.isEmpty
                          ? 'Approvals and checks appear here'
                          : activities.first.title,
                      icon: Icons.history_toggle_off_rounded,
                      accent: ForgePalette.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ForgeSectionHeader(
                  title: 'Repositories',
                  subtitle: 'Jump back into the codebases you review most.',
                  trailing: ForgeSecondaryButton(
                    label: repositories.isEmpty ? 'Connect' : 'View all',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: onOpenRepository,
                  ),
                ),
                const SizedBox(height: 12),
                if (repositories.isEmpty)
                  const ForgePanel(
                    child: _EmptySection(
                      title: 'No repositories connected yet',
                      detail:
                          'Use the repository tab to connect GitHub or GitLab and sync the file tree into ForgeAI.',
                    ),
                  )
                else
                  ...repositories.map(
                    (repository) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ForgePanel(
                        onTap: onOpenRepository,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ForgePill(
                                  label: repository.providerLabel,
                                  color:
                                      repository.provider ==
                                          ForgeProvider.github
                                      ? ForgePalette.glowAccent
                                      : ForgePalette.warning,
                                  icon:
                                      repository.provider ==
                                          ForgeProvider.github
                                      ? Icons.code_rounded
                                      : Icons.merge_rounded,
                                ),
                                const Spacer(),
                                ForgePill(
                                  label: repository.status,
                                  color: repository.status == 'Healthy'
                                      ? ForgePalette.success
                                      : ForgePalette.warning,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              repository.repoLabel,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              repository.description,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 14),
                            compactLayout
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        children: [
                                          _RepoMeta(
                                            icon: Icons.commit_rounded,
                                            label: repository.defaultBranch,
                                          ),
                                          _RepoMeta(
                                            icon: Icons.compare_arrows_rounded,
                                            label:
                                                '${repository.changedFiles} changed',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        repository.lastSynced.inMinutes < 60
                                            ? '${repository.lastSynced.inMinutes}m ago'
                                            : '${repository.lastSynced.inHours}h ago',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium,
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      _RepoMeta(
                                        icon: Icons.commit_rounded,
                                        label: repository.defaultBranch,
                                      ),
                                      const SizedBox(width: 12),
                                      _RepoMeta(
                                        icon: Icons.compare_arrows_rounded,
                                        label:
                                            '${repository.changedFiles} changed',
                                      ),
                                      const Spacer(),
                                      Text(
                                        repository.lastSynced.inMinutes < 60
                                            ? '${repository.lastSynced.inMinutes}m ago'
                                            : '${repository.lastSynced.inHours}h ago',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium,
                                      ),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                ForgeSectionHeader(
                  title: 'Recent activity',
                  subtitle:
                      'Everything stays visible, timestamped, and reviewable.',
                  trailing: ForgeSecondaryButton(
                    label: 'Full history',
                    icon: Icons.history_rounded,
                    onPressed: onOpenActivity,
                  ),
                ),
                const SizedBox(height: 12),
                ForgePanel(
                  child: activities.isEmpty
                      ? const _EmptySection(
                          title: 'No activity yet',
                          detail:
                              'Repository connections, AI changes, commits, pull requests, and checks will appear here.',
                        )
                      : Column(
                          children: [
                            for (final entry in activities) ...[
                              _ActivityRow(entry: entry),
                              if (entry != activities.last)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: Divider(height: 1),
                                ),
                            ],
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

class _RepoMeta extends StatelessWidget {
  const _RepoMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: ForgePalette.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ForgeActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLayout = constraints.maxWidth < 340;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: entry.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(entry.icon, color: entry.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (compactLayout) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.timestamp,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ],
              ),
            ),
            if (!compactLayout) ...[
              const SizedBox(width: 12),
              Text(
                entry.timestamp,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(detail, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
