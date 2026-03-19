import 'package:flutter/material.dart';

import '../../core/branding/app_branding.dart';
import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../auth/application/auth_controller.dart';
import '../auth/domain/auth_account.dart';
import '../auth/presentation/guest_gate_dialog.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';
import '../workspace/domain/forge_workspace_state.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.controller,
    this.account,
    this.authController,
    this.onOpenRepository,
    this.onOpenHub,
    this.onOpenPrompt,
    this.onOpenCodeEditor,
    this.onOpenChecks,
    this.onOpenWallet,
    this.onOpenActivity,
  });

  final ForgeWorkspaceController controller;
  final AuthAccount? account;
  final AuthController? authController;
  final VoidCallback? onOpenRepository;
  final VoidCallback? onOpenHub;
  final VoidCallback? onOpenPrompt;
  final VoidCallback? onOpenCodeEditor;
  final VoidCallback? onOpenChecks;
  final VoidCallback? onOpenWallet;
  final VoidCallback? onOpenActivity;

  bool get _isGuest => account?.isGuest ?? false;

  VoidCallback? _guardedAction(
    BuildContext context, {
    required String featureName,
    required VoidCallback? action,
    bool allowGuest = false,
  }) {
    if (action == null) {
      return null;
    }
    if (allowGuest || !_isGuest || authController == null) {
      return action;
    }
    return () => showGuestSignInRequiredDialog(
      context,
      authController: authController!,
      featureName: featureName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final repositories = state.repositories;
        final activities = state.activities;
        final checks = state.checks;
        final wallet = state.wallet;
        final selectedRepository = state.selectedRepository;
        final featuredRepository =
            selectedRepository ??
            (repositories.isNotEmpty ? repositories.first : null);
        final checksPassing = checks
            .where((check) => check.status == ForgeCheckStatus.passed)
            .length;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            maxContentWidth: 1240,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _DashboardHero(
                  account: account,
                  isGuest: _isGuest,
                  state: state,
                  featuredRepository: featuredRepository,
                  checksPassing: checksPassing,
                  onOpenRepository: _guardedAction(
                    context,
                    featureName: 'Connecting repositories',
                    action: onOpenRepository,
                  ),
                  onOpenPrompt: _guardedAction(
                    context,
                    featureName: 'Prompt',
                    action: onOpenPrompt,
                    allowGuest: true,
                  ),
                  onOpenCodeEditor: _guardedAction(
                    context,
                    featureName: 'Code editor',
                    action: onOpenCodeEditor,
                  ),
                ),
                const SizedBox(height: 24),
                _WorkspacePulseStrip(
                  selectedRepository: featuredRepository,
                  currentDocument: state.currentDocument,
                  wallet: wallet,
                  threadCount: state.promptThreads.length,
                  checksPassing: checksPassing,
                  totalChecks: checks.length,
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wideLayout = constraints.maxWidth >= 1080;
                    final metrics = _MetricsGrid(
                      wallet: wallet,
                      repositories: repositories,
                      activities: activities,
                      checks: checks,
                    );
                    final repositorySection = _RepositorySection(
                      repositories: repositories,
                      compactLayout: constraints.maxWidth < 430,
                      onOpenRepository: _guardedAction(
                        context,
                        featureName: 'Connecting repositories',
                        action: onOpenRepository,
                      ),
                    );
                    final activitySection = _ActivitySection(
                      activities: activities,
                      onOpenActivity: onOpenActivity,
                    );
                    final commandDeck = _CommandDeck(
                      isGuest: _isGuest,
                      onOpenRepository: _guardedAction(
                        context,
                        featureName: 'Connecting repositories',
                        action: onOpenRepository,
                      ),
                      onOpenPrompt: _guardedAction(
                        context,
                        featureName: 'Prompt',
                        action: onOpenPrompt,
                        allowGuest: true,
                      ),
                      onOpenCodeEditor: _guardedAction(
                        context,
                        featureName: 'Code editor',
                        action: onOpenCodeEditor,
                      ),
                      onOpenHub: _guardedAction(
                        context,
                        featureName: 'Account hub',
                        action: onOpenHub,
                      ),
                      onOpenWallet: _guardedAction(
                        context,
                        featureName: 'Wallet',
                        action: onOpenWallet,
                      ),
                      onOpenChecks: onOpenChecks,
                    );

                    if (!wideLayout) {
                      return Column(
                        children: [
                          metrics,
                          const SizedBox(height: 24),
                          repositorySection,
                          const SizedBox(height: 24),
                          activitySection,
                          const SizedBox(height: 24),
                          commandDeck,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: Column(
                            children: [
                              metrics,
                              const SizedBox(height: 24),
                              repositorySection,
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              activitySection,
                              const SizedBox(height: 24),
                              commandDeck,
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.account,
    required this.isGuest,
    required this.state,
    required this.featuredRepository,
    required this.checksPassing,
    required this.onOpenRepository,
    required this.onOpenPrompt,
    required this.onOpenCodeEditor,
  });

  final AuthAccount? account;
  final bool isGuest;
  final ForgeWorkspaceState state;
  final ForgeRepository? featuredRepository;
  final int checksPassing;
  final VoidCallback? onOpenRepository;
  final VoidCallback? onOpenPrompt;
  final VoidCallback? onOpenCodeEditor;

  @override
  Widget build(BuildContext context) {
    final repositories = state.repositories;
    final wallet = state.wallet;
    final currentFile = state.currentDocument?.path.split('/').last;
    final headline = repositories.isEmpty
        ? 'A web-ready command center for your repositories.'
        : 'Operate your codebase from a workspace that finally scales to desktop.';
    final subhead = repositories.isEmpty
        ? 'Connect GitHub, then move from prompt to code review, branch work, and CI without leaving $kAppDisplayName.'
        : 'Jump between AI guidance, code edits, repository health, and wallet controls in one responsive cockpit.';

    return ForgePanel(
      highlight: true,
      padding: const EdgeInsets.all(28),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 920;
          final leading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ForgePill(
                    label: state.isBootstrapping
                        ? 'Syncing workspace'
                        : (isGuest
                              ? 'Guest workspace'
                              : 'Premium control room'),
                    icon: state.isBootstrapping
                        ? Icons.sync_rounded
                        : (isGuest
                              ? Icons.person_outline_rounded
                              : Icons.desktop_windows_rounded),
                    color: state.isBootstrapping
                        ? ForgePalette.sparkAccent
                        : ForgePalette.primaryAccent,
                  ),
                  if (featuredRepository != null)
                    ForgePill(
                      label: featuredRepository!.repoLabel,
                      icon: Icons.folder_open_rounded,
                    ),
                  if (account != null && !account!.isGuest)
                    ForgePill(
                      label: account!.displayName,
                      icon: Icons.verified_user_rounded,
                      color: ForgePalette.success,
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(headline, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 12),
              Text(
                subhead,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ForgePalette.textSecondary,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ForgePrimaryButton(
                    label: repositories.isEmpty
                        ? 'Connect repository'
                        : 'Open Prompt',
                    icon: repositories.isEmpty
                        ? Icons.link_rounded
                        : Icons.auto_awesome_rounded,
                    onPressed: repositories.isEmpty
                        ? onOpenRepository
                        : onOpenPrompt,
                  ),
                  if (repositories.isNotEmpty && !isGuest)
                    ForgeSecondaryButton(
                      label: 'Code editor',
                      icon: Icons.code_rounded,
                      onPressed: onOpenCodeEditor,
                    ),
                  ForgeSecondaryButton(
                    label: 'Manage repositories',
                    icon: Icons.folder_copy_rounded,
                    onPressed: onOpenRepository,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _HeroInsightTile(
                    label: 'Token balance',
                    value: '${wallet.balance.toInt()}',
                    detail: wallet.planName,
                  ),
                  _HeroInsightTile(
                    label: 'Checks passing',
                    value: state.checks.isEmpty
                        ? '0'
                        : '$checksPassing/${state.checks.length}',
                    detail: state.checks.isEmpty
                        ? 'No checks yet'
                        : 'CI signal ready',
                  ),
                  _HeroInsightTile(
                    label: 'Current focus',
                    value: currentFile ?? 'No file open',
                    detail:
                        featuredRepository?.defaultBranch ??
                        'Open the Repo tab',
                  ),
                ],
              ),
            ],
          );

          final preview = _HeroPreviewCard(
            state: state,
            featuredRepository: featuredRepository,
            checksPassing: checksPassing,
          );

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [leading, const SizedBox(height: 24), preview],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: leading),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: preview),
            ],
          );
        },
      ),
    );
  }
}

class _HeroPreviewCard extends StatelessWidget {
  const _HeroPreviewCard({
    required this.state,
    required this.featuredRepository,
    required this.checksPassing,
  });

  final ForgeWorkspaceState state;
  final ForgeRepository? featuredRepository;
  final int checksPassing;

  @override
  Widget build(BuildContext context) {
    final repository = featuredRepository;
    final branch = state.selectedBranch ?? repository?.defaultBranch ?? 'main';
    final isGitHub = repository?.provider == ForgeProvider.github;
    final lines = repository == null
        ? <String>[
            'status: ready for first repository',
            'next: connect github',
            'prompt: ask for a code change or workflow install',
            'review: diff, commit, and ship from one place',
          ]
        : <String>[
            'repo: ${repository.repoLabel}',
            'branch: $branch',
            'checks: $checksPassing/${state.checks.length} passing',
            'tokens: ${state.wallet.balance.toInt()} available',
            'last activity: ${state.activities.isEmpty ? 'awaiting first event' : state.activities.first.title}',
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ForgePalette.heroGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: ForgePalette.border.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: ForgePalette.primaryAccent.withValues(alpha: 0.18),
            blurRadius: 32,
            spreadRadius: -18,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: ForgePalette.buttonGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.auto_graph_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        repository == null
                            ? 'Workspace preview'
                            : 'Live workspace pulse',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        repository == null
                            ? 'See what becomes available once your first repo is connected.'
                            : 'A compact snapshot of the repo currently in focus.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ForgeCodeBlock(lines: lines),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ForgePill(
                  label: repository?.providerLabel ?? 'GitHub',
                  icon: repository == null || isGitHub
                      ? Icons.code_rounded
                      : Icons.merge_rounded,
                  color: repository == null
                      ? ForgePalette.sparkAccent
                      : (isGitHub
                            ? ForgePalette.glowAccent
                            : ForgePalette.sparkAccent),
                ),
                ForgePill(
                  label: state.promptThreads.isEmpty
                      ? 'Prompt inbox ready'
                      : '${state.promptThreads.length} active threads',
                  icon: Icons.chat_bubble_outline_rounded,
                ),
                ForgePill(
                  label: state.currentDocument == null
                      ? 'Editor idle'
                      : 'Editing ${state.currentDocument!.path.split('/').last}',
                  icon: Icons.edit_note_rounded,
                  color: ForgePalette.success,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroInsightTile extends StatelessWidget {
  const _HeroInsightTile({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 156, maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ForgePalette.backgroundSecondary.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ForgePalette.border.withValues(alpha: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspacePulseStrip extends StatelessWidget {
  const _WorkspacePulseStrip({
    required this.selectedRepository,
    required this.currentDocument,
    required this.wallet,
    required this.threadCount,
    required this.checksPassing,
    required this.totalChecks,
  });

  final ForgeRepository? selectedRepository;
  final ForgeFileDocument? currentDocument;
  final ForgeTokenWallet wallet;
  final int threadCount;
  final int checksPassing;
  final int totalChecks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final singleColumn = constraints.maxWidth < 840;
        final tiles = [
          _PulseTile(
            icon: Icons.memory_rounded,
            accent: ForgePalette.primaryAccent,
            label: 'Focused repository',
            value: selectedRepository?.repoLabel ?? 'Not selected yet',
            detail:
                selectedRepository?.language ?? 'Pick one from the Repo tab',
          ),
          _PulseTile(
            icon: Icons.edit_rounded,
            accent: ForgePalette.success,
            label: 'Working file',
            value: currentDocument?.path.split('/').last ?? 'No file open',
            detail: currentDocument?.language ?? 'Open a file to start editing',
          ),
          _PulseTile(
            icon: Icons.chat_bubble_outline_rounded,
            accent: ForgePalette.sparkAccent,
            label: 'Prompt activity',
            value: '$threadCount threads',
            detail: totalChecks == 0
                ? 'Checks will appear after the first workflow run'
                : '$checksPassing/$totalChecks checks healthy',
          ),
          _PulseTile(
            icon: Icons.account_balance_wallet_rounded,
            accent: ForgePalette.glowAccent,
            label: 'Wallet plan',
            value: wallet.planName,
            detail: '${wallet.monthlyAllowance.toInt()} monthly allowance',
          ),
        ];

        if (singleColumn) {
          return Column(
            children: [
              for (final tile in tiles) ...[
                tile,
                if (tile != tiles.last) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < tiles.length; index++) ...[
              Expanded(child: tiles[index]),
              if (index != tiles.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _PulseTile extends StatelessWidget {
  const _PulseTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ForgePalette.backgroundSecondary.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ForgePalette.border.withValues(alpha: 0.78)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.wallet,
    required this.repositories,
    required this.activities,
    required this.checks,
  });

  final ForgeTokenWallet wallet;
  final List<ForgeRepository> repositories;
  final List<ForgeActivityEntry> activities;
  final List<ForgeCheckRun> checks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSingleColumn = constraints.maxWidth < 680;
        final tileWidth = useSingleColumn
            ? constraints.maxWidth
            : (constraints.maxWidth - 16) / 2;
        final tiles = [
          ForgeMetricTile(
            label: 'Token balance',
            value: '${wallet.balance.toInt()}',
            detail: '${wallet.monthlyAllowance.toInt()} monthly allowance',
            icon: Icons.token_rounded,
          ),
          ForgeMetricTile(
            label: 'Active repos',
            value: '${repositories.length}',
            detail: repositories.isEmpty
                ? 'Connect GitHub'
                : '${repositories.first.changedFiles} staged file changes',
            icon: Icons.folder_copy_rounded,
            accent: ForgePalette.primaryAccent,
          ),
          ForgeMetricTile(
            label: 'Checks passing',
            value: checks.isEmpty
                ? '0/0'
                : '${checks.where((check) => check.status == ForgeCheckStatus.passed).length}/${checks.length}',
            detail: 'Workflow health from every connected repo',
            icon: Icons.verified_rounded,
            accent: ForgePalette.success,
          ),
          ForgeMetricTile(
            label: 'Recent review',
            value: activities.isEmpty
                ? 'No activity'
                : activities.first.timestamp,
            detail: activities.isEmpty
                ? 'Approvals and changes appear here'
                : activities.first.title,
            icon: Icons.history_toggle_off_rounded,
            accent: ForgePalette.sparkAccent,
          ),
        ];

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }
}

class _RepositorySection extends StatelessWidget {
  const _RepositorySection({
    required this.repositories,
    required this.compactLayout,
    required this.onOpenRepository,
  });

  final List<ForgeRepository> repositories;
  final bool compactLayout;
  final VoidCallback? onOpenRepository;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ForgeSectionHeader(
          title: 'Repositories',
          subtitle:
              'Re-enter the projects you review most without losing context.',
          trailing: ForgeSecondaryButton(
            label: repositories.isEmpty ? 'Connect' : 'View all',
            icon: Icons.arrow_forward_rounded,
            onPressed: onOpenRepository,
          ),
        ),
        const SizedBox(height: 14),
        if (repositories.isEmpty)
          const ForgePanel(
            child: _EmptySection(
              title: 'No repositories connected yet',
              detail:
                  'Use the repository tab to connect GitHub, sync the tree, and start working from the web workspace.',
            ),
          )
        else
          ...repositories.map(
            (repository) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ForgePanel(
                onTap: onOpenRepository,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ForgePill(
                          label: repository.providerLabel,
                          color: repository.provider == ForgeProvider.github
                              ? ForgePalette.glowAccent
                              : ForgePalette.sparkAccent,
                          icon: repository.provider == ForgeProvider.github
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
                    if (compactLayout)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                label: '${repository.changedFiles} changed',
                              ),
                              _RepoMeta(
                                icon: Icons.star_rounded,
                                label: '${repository.stars} stars',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            repository.lastSynced.inMinutes < 60
                                ? '${repository.lastSynced.inMinutes}m ago'
                                : '${repository.lastSynced.inHours}h ago',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          _RepoMeta(
                            icon: Icons.commit_rounded,
                            label: repository.defaultBranch,
                          ),
                          const SizedBox(width: 12),
                          _RepoMeta(
                            icon: Icons.compare_arrows_rounded,
                            label: '${repository.changedFiles} changed',
                          ),
                          const SizedBox(width: 12),
                          _RepoMeta(
                            icon: Icons.star_rounded,
                            label: '${repository.stars} stars',
                          ),
                          const Spacer(),
                          Text(
                            repository.lastSynced.inMinutes < 60
                                ? '${repository.lastSynced.inMinutes}m ago'
                                : '${repository.lastSynced.inHours}h ago',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.activities,
    required this.onOpenActivity,
  });

  final List<ForgeActivityEntry> activities;
  final VoidCallback? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ForgeSectionHeader(
          title: 'Recent activity',
          subtitle:
              'Everything stays timestamped, visible, and ready for review.',
          trailing: ForgeSecondaryButton(
            label: 'Full history',
            icon: Icons.history_rounded,
            onPressed: onOpenActivity,
          ),
        ),
        const SizedBox(height: 14),
        ForgePanel(
          child: activities.isEmpty
              ? const _EmptySection(
                  title: 'No activity yet',
                  detail:
                      'Repository connections, AI edits, commits, pull requests, and workflow runs will appear here.',
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
    );
  }
}

class _CommandDeck extends StatelessWidget {
  const _CommandDeck({
    required this.isGuest,
    required this.onOpenRepository,
    required this.onOpenPrompt,
    required this.onOpenCodeEditor,
    required this.onOpenHub,
    required this.onOpenWallet,
    required this.onOpenChecks,
  });

  final bool isGuest;
  final VoidCallback? onOpenRepository;
  final VoidCallback? onOpenPrompt;
  final VoidCallback? onOpenCodeEditor;
  final VoidCallback? onOpenHub;
  final VoidCallback? onOpenWallet;
  final VoidCallback? onOpenChecks;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionCardData(
        title: 'Prompt AI',
        detail:
            'Ask for workflow installs, code changes, and deployment steps.',
        icon: Icons.auto_awesome_rounded,
        accent: ForgePalette.primaryAccent,
        onTap: onOpenPrompt,
      ),
      _ActionCardData(
        title: 'Repository manager',
        detail: 'Connect providers, switch projects, and sync file trees.',
        icon: Icons.folder_copy_rounded,
        accent: ForgePalette.glowAccent,
        onTap: onOpenRepository,
      ),
      _ActionCardData(
        title: 'Code editor',
        detail: isGuest
            ? 'Sign in to unlock editing and diff review.'
            : 'Open the editor and move from prompt to saved changes.',
        icon: Icons.code_rounded,
        accent: ForgePalette.success,
        onTap: onOpenCodeEditor,
      ),
      _ActionCardData(
        title: 'Wallet',
        detail: 'Track usage, monthly allowance, and token packs.',
        icon: Icons.account_balance_wallet_rounded,
        accent: ForgePalette.sparkAccent,
        onTap: onOpenWallet,
      ),
      _ActionCardData(
        title: 'Account hub',
        detail: 'Browse provider repos and manage linked accounts.',
        icon: Icons.hub_rounded,
        accent: ForgePalette.primaryAccent,
        onTap: onOpenHub,
      ),
      _ActionCardData(
        title: 'Checks dashboard',
        detail: 'Trigger and inspect builds, lint, and test runs.',
        icon: Icons.verified_rounded,
        accent: ForgePalette.success,
        onTap: onOpenChecks,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ForgeSectionHeader(
          title: 'Quick actions',
          subtitle:
              'Launch the next workflow with one click from any device size.',
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final singleColumn = constraints.maxWidth < 520;
            final tileWidth = singleColumn
                ? constraints.maxWidth
                : (constraints.maxWidth - 16) / 2;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: tileWidth,
                    child: _DashboardActionCard(action: action),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ActionCardData {
  const _ActionCardData({
    required this.title,
    required this.detail,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
}

class _DashboardActionCard extends StatelessWidget {
  const _DashboardActionCard({required this.action});

  final _ActionCardData action;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      onTap: action.onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: action.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(action.icon, color: action.accent),
          ),
          const SizedBox(height: 14),
          Text(action.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(action.detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
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
