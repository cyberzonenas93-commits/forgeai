import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/config/forge_economics_config.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/forge_palette.dart';
import '../core/notifications/forge_push_controller.dart';
import '../features/account/presentation/account_settings_screen.dart';
import '../features/activity/activity_timeline_screen.dart';
import '../features/agent/agent_mode_screen.dart';
import '../features/agent/chat_prompt_screen.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/auth_account.dart';
import '../features/auth/presentation/guest_gate_dialog.dart';
import '../features/billing/data/iap_forge_billing_service.dart';
import '../features/billing/data/mock_forge_billing_service.dart';
import '../features/billing/domain/forge_billing_service.dart';
import '../features/billing/presentation/paywall_screen.dart';
import '../features/billing/presentation/token_packs_screen.dart';
import '../features/checks/checks_dashboard_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/editor/editor_workflow_screen.dart';
import '../features/repos/account_hub_screen.dart';
import '../features/repos/repositories_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/workspace/application/forge_workspace_controller.dart';
import '../features/workspace/domain/forge_workspace_state.dart';
import '../shared/forge_models.dart';
import '../shared/widgets/forge_widgets.dart';
import '../features/wallet/wallet_screen.dart';

class ForgeHomeShell extends StatefulWidget {
  const ForgeHomeShell({
    super.key,
    required this.controller,
    required this.account,
    required this.workspaceController,
    required this.pushController,
    this.firebaseFunctions,
  });

  final AuthController controller;
  final AuthAccount account;
  final ForgeWorkspaceController workspaceController;
  final ForgePushController pushController;
  final FirebaseFunctions? firebaseFunctions;

  @override
  State<ForgeHomeShell> createState() => _ForgeHomeShellState();
}

class _ForgeHomeShellState extends State<ForgeHomeShell> {
  int _currentIndex = 0;
  late ForgeBillingService _billingService;
  IAPForgeBillingService? _iapBillingService;

  bool get _billingActionsEnabled =>
      _billingService is IAPForgeBillingService || !kReleaseMode;

  static const List<_ShellDestination> _destinations = [
    _ShellDestination(
      label: 'Home',
      subtitle: 'Workspace signal, activity, and launch controls.',
      icon: Icons.dashboard_rounded,
    ),
    _ShellDestination(
      label: 'Hub',
      subtitle: 'Connected accounts, provider repos, and setup flow.',
      icon: Icons.hub_rounded,
    ),
    _ShellDestination(
      label: 'Agent',
      subtitle: 'Chat-style prompt entry — type a task and the agent executes it.',
      icon: Icons.smart_toy_rounded,
    ),
    _ShellDestination(
      label: 'Code',
      subtitle: 'File explorer, live edits, and diff-ready workflows.',
      icon: Icons.code_rounded,
    ),
    _ShellDestination(
      label: 'Repo',
      subtitle: 'Repository switching, sync, and branch management.',
      icon: Icons.folder_copy_rounded,
    ),
    _ShellDestination(
      label: 'Settings',
      subtitle: 'Account, wallet, notifications, and provider access.',
      icon: Icons.settings_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _billingService = MockForgeBillingService();
    widget.pushController.attachRouteHandler(_handlePushRoute);
    _tryUseIAP();
  }

  Future<void> _tryUseIAP() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final functions = widget.firebaseFunctions;
    if (functions == null) return;

    String? getCurrentUserId() => widget.account.id;

    final iap = IAPForgeBillingService(
      functions: functions,
      getCurrentUserId: getCurrentUserId,
    );
    final available = await iap.isAvailable;
    if (available && mounted) {
      setState(() {
        _iapBillingService = iap;
        _billingService = iap;
      });
    }
  }

  @override
  void dispose() {
    _iapBillingService?.dispose();
    widget.pushController.detachRouteHandler();
    super.dispose();
  }

  void _openPaywall() {
    _open(
      PaywallScreen(
        billingService: _billingService,
        currentPlanId: ForgePlanId.free,
        onUpgrade: (planId) async {
          final result = await _billingService.purchaseSubscription(planId);
          if (!mounted) return;
          if (result == ForgeBillingResult.success) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Subscription updated.')),
            );
          } else if (result == ForgeBillingResult.pending) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Purchase in progress. Your account will update when complete.',
                ),
              ),
            );
          } else if (result == ForgeBillingResult.cancelled) {
            return;
          } else if (result == ForgeBillingResult.notAvailable) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'In-app purchases are not available. Use the web app to subscribe.',
                ),
              ),
            );
          } else if (result == ForgeBillingResult.error) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Purchase failed. Try again later.'),
              ),
            );
          }
        },
        onRestore: () async {
          final result = await _billingService.restorePurchases;
          if (!mounted) return;
          if (result == ForgeBillingResult.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Purchases restored.')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No purchases to restore.')),
            );
          }
        },
      ),
    );
  }

  void _openWallet() {
    if (widget.account.isGuest) {
      showGuestSignInRequiredDialog(
        context,
        authController: widget.controller,
        featureName: 'Wallet',
      );
      return;
    }
    _open(
      WalletScreen(
        controller: widget.workspaceController,
        onUpgrade: _billingActionsEnabled ? _openPaywall : null,
        onGetTokens: _billingActionsEnabled
            ? () => _open(TokenPacksScreen(billingService: _billingService))
            : null,
      ),
    );
  }

  VoidCallback _switchTo(int index) {
    return () => setState(() => _currentIndex = index);
  }

  /// Opens the full task-queue/AgentModeScreen as a pushed route on top of
  /// the current shell page.  This preserves backward navigation to the chat
  /// tab cleanly.
  Future<void> _openAgentQueue() {
    return _open(
      AgentModeScreen(
        controller: widget.workspaceController,
        onSwitchToEditorTab: _switchTo(3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ForgeWorkspaceState>(
      valueListenable: widget.workspaceController,
      builder: (context, state, _) {
        final pages = <Widget>[
          DashboardScreen(
            controller: widget.workspaceController,
            account: widget.account,
            authController: widget.controller,
            onOpenRepository: _switchTo(4),
            onOpenHub: _switchTo(1),
            onOpenPrompt: _switchTo(2),
            onOpenCodeEditor: _switchTo(3),
            onOpenChecks: () => _open(
              ChecksDashboardScreen(controller: widget.workspaceController),
            ),
            onOpenWallet: _openWallet,
            onOpenActivity: () => _open(
              ActivityTimelineScreen(controller: widget.workspaceController),
            ),
          ),
          AccountHubScreen(
            controller: widget.workspaceController,
            account: widget.account,
            authController: widget.controller,
            onSwitchToRepoTab: _switchTo(4),
            onSwitchToAgentTab: _switchTo(2),
          ),
          // Chat-first agent entry point.  The full task queue is one tap
          // away via the queue icon in the app bar (→ AgentModeScreen).
          ChatPromptScreen(
            controller: widget.workspaceController,
            onSwitchToEditorTab: _switchTo(3),
            onOpenTaskQueue: _openAgentQueue,
          ),
          EditorWorkflowScreen(
            controller: widget.workspaceController,
            onSwitchToRepoTab: _switchTo(4),
          ),
          RepositoriesScreen(
            controller: widget.workspaceController,
            account: widget.account,
            authController: widget.controller,
            onOpenFile: (_) => setState(() => _currentIndex = 3),
          ),
          SettingsScreen(
            controller: widget.controller,
            account: widget.account,
            workspaceController: widget.workspaceController,
            pushController: widget.pushController,
            onOpenWallet: _openWallet,
            onOpenAccount: () =>
                _open(AccountSettingsScreen(controller: widget.controller)),
          ),
        ];

        final width = MediaQuery.sizeOf(context).width;
        final showDesktopShell = width >= 1180;
        final showRailShell = width >= 760;
        final content = KeyedSubtree(
          key: ValueKey<int>(_currentIndex),
          child: pages[_currentIndex],
        );

        if (showRailShell) {
          return _buildAdaptiveShell(
            context,
            state: state,
            content: content,
            collapsedSidebar: !showDesktopShell,
          );
        }

        return _buildMobileShell(content);
      },
    );
  }

  Widget _buildMobileShell(Widget content) {
    return Scaffold(
      extendBody: false,
      backgroundColor: Colors.transparent,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.02, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: content,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: ForgePalette.border.withValues(alpha: 0.9),
            ),
            gradient: ForgePalette.surfaceGradient,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 28,
                spreadRadius: -12,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
              },
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    label: destination.label,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdaptiveShell(
    BuildContext context, {
    required ForgeWorkspaceState state,
    required Widget content,
    required bool collapsedSidebar,
  }) {
    final current = _destinations[_currentIndex];
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: ForgeAiTheme.backgroundGradient,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                width: collapsedSidebar ? 108 : 300,
                child: _ShellSidebar(
                  collapsed: collapsedSidebar,
                  account: widget.account,
                  state: state,
                  destinations: _destinations,
                  currentIndex: _currentIndex,
                  onDestinationSelected: (index) {
                    setState(() => _currentIndex = index);
                  },
                  onOpenPrompt: _switchTo(2),
                  onOpenRepository: _switchTo(4),
                  onOpenWallet: _openWallet,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    _ShellHeader(
                      title: current.label,
                      subtitle: current.subtitle,
                      account: widget.account,
                      state: state,
                      onOpenPrompt: _switchTo(2),
                      onOpenWallet: _openWallet,
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: _ShellStage(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.015, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: content,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(Widget screen) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _handlePushRoute(ForgePushRoute route) async {
    if (!mounted) {
      return;
    }

    if (route.repoId != null) {
      final repositories = widget.workspaceController.value.repositories;
      for (final repository in repositories) {
        if (repository.id == route.repoId) {
          await widget.workspaceController.selectRepository(repository);
          break;
        }
      }
    }

    switch (route.destination) {
      case ForgeNotificationDestination.home:
        setState(() => _currentIndex = 0);
        return;
      case ForgeNotificationDestination.prompt:
        setState(() => _currentIndex = 2);
        return;
      case ForgeNotificationDestination.repo:
        setState(() => _currentIndex = 4);
        return;
      case ForgeNotificationDestination.settings:
        setState(() => _currentIndex = 5);
        return;
      case ForgeNotificationDestination.wallet:
        _openWallet();
        return;
      case ForgeNotificationDestination.activity:
        await _open(
          ActivityTimelineScreen(controller: widget.workspaceController),
        );
        return;
      case ForgeNotificationDestination.checks:
        await _open(
          ChecksDashboardScreen(controller: widget.workspaceController),
        );
        return;
    }
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  final String label;
  final String subtitle;
  final IconData icon;
}

class _ShellSidebar extends StatelessWidget {
  const _ShellSidebar({
    required this.collapsed,
    required this.account,
    required this.state,
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onOpenPrompt,
    required this.onOpenRepository,
    required this.onOpenWallet,
  });

  final bool collapsed;
  final AuthAccount account;
  final ForgeWorkspaceState state;
  final List<_ShellDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onOpenPrompt;
  final VoidCallback onOpenRepository;
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    final selectedRepo = state.selectedRepository;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ForgePalette.surfaceGradient,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: ForgePalette.border.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 30,
            spreadRadius: -16,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(collapsed ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (collapsed)
              const Center(child: ForgeBrandMark(size: 54))
            else
              Row(
                children: [
                  const ForgeBrandMark(size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CodeCatalystAI',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Responsive command center for repos, runs, and releases.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            SizedBox(height: collapsed ? 18 : 22),
            if (!collapsed) ...[
              ForgePanel(
                highlight: true,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ForgePill(
                          label: state.isBootstrapping ? 'Syncing' : 'Online',
                          icon: state.isBootstrapping
                              ? Icons.sync_rounded
                              : Icons.bolt_rounded,
                          color: state.isBootstrapping
                              ? ForgePalette.sparkAccent
                              : ForgePalette.primaryAccent,
                        ),
                        if (selectedRepo != null)
                          ForgePill(
                            label: selectedRepo.providerLabel,
                            icon: selectedRepo.provider == ForgeProvider.github
                                ? Icons.code_rounded
                                : Icons.merge_rounded,
                            color: selectedRepo.provider == ForgeProvider.github
                                ? ForgePalette.glowAccent
                                : ForgePalette.sparkAccent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      selectedRepo?.repoLabel ?? 'No repository selected',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedRepo == null
                          ? 'Connect a repository to unlock the full workflow.'
                          : 'Branch ${state.selectedBranch ?? selectedRepo.defaultBranch} is ready for review and edits.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _SidebarMetric(
                            label: 'Repos',
                            value: '${state.repositories.length}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SidebarMetric(
                            label: 'Runs',
                            value: '${state.promptThreads.length}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SidebarMetric(
                            label: 'Tokens',
                            value: '${state.wallet.balance.toInt()}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            for (var index = 0; index < destinations.length; index++) ...[
              _SidebarNavButton(
                destination: destinations[index],
                selected: currentIndex == index,
                collapsed: collapsed,
                onTap: () => onDestinationSelected(index),
              ),
              const SizedBox(height: 8),
            ],
            const Spacer(),
            if (collapsed) ...[
              _SidebarIconAction(
                icon: Icons.auto_awesome_motion_rounded,
                tooltip: 'Open Agent',
                onTap: onOpenPrompt,
              ),
              const SizedBox(height: 10),
              _SidebarIconAction(
                icon: Icons.folder_copy_rounded,
                tooltip: 'Open repositories',
                onTap: onOpenRepository,
              ),
              const SizedBox(height: 10),
              _SidebarIconAction(
                icon: Icons.account_balance_wallet_rounded,
                tooltip: 'Open wallet',
                onTap: onOpenWallet,
              ),
              const SizedBox(height: 14),
              _AccountOrb(account: account),
            ] else ...[
              ForgePanel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick launch',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Move between live runs, repos, and wallet controls without losing context.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    ForgePrimaryButton(
                      label: 'Open Agent',
                      icon: Icons.auto_awesome_rounded,
                      onPressed: onOpenPrompt,
                      expanded: true,
                    ),
                    const SizedBox(height: 10),
                    ForgeSecondaryButton(
                      label: 'Browse repositories',
                      icon: Icons.folder_copy_rounded,
                      onPressed: onOpenRepository,
                      expanded: true,
                    ),
                    const SizedBox(height: 10),
                    ForgeSecondaryButton(
                      label: 'Wallet & usage',
                      icon: Icons.account_balance_wallet_rounded,
                      onPressed: onOpenWallet,
                      expanded: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _AccountCard(account: account),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({
    required this.title,
    required this.subtitle,
    required this.account,
    required this.state,
    required this.onOpenPrompt,
    required this.onOpenWallet,
  });

  final String title;
  final String subtitle;
  final AuthAccount account;
  final ForgeWorkspaceState state;
  final VoidCallback onOpenPrompt;
  final VoidCallback onOpenWallet;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ForgePalette.surfaceGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: ForgePalette.border.withValues(alpha: 0.9)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 980;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.min(constraints.maxWidth, 520),
                      ),
                      child: Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    ForgePill(
                      label: state.isBootstrapping
                          ? 'Syncing workspace'
                          : '${state.repositories.length} repositories ready',
                      icon: state.isBootstrapping
                          ? Icons.sync_rounded
                          : Icons.cloud_done_rounded,
                      color: state.isBootstrapping
                          ? ForgePalette.sparkAccent
                          : ForgePalette.primaryAccent,
                    ),
                    if (state.selectedRepository != null)
                      ForgePill(
                        label: state.selectedRepository!.repoLabel,
                        icon: Icons.folder_open_rounded,
                      ),
                  ],
                ),
              ],
            );
            final actions = Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ForgeSecondaryButton(
                  label: 'Wallet',
                  icon: Icons.account_balance_wallet_rounded,
                  onPressed: onOpenWallet,
                ),
                ForgePrimaryButton(
                  label: 'Start Run',
                  icon: Icons.auto_awesome_rounded,
                  onPressed: onOpenPrompt,
                ),
                _AccountChip(account: account),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: 16), actions],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 16),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ShellStage extends StatelessWidget {
  const _ShellStage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: ForgePalette.border.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 34,
            spreadRadius: -14,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(32), child: child),
    );
  }
}

class _SidebarNavButton extends StatelessWidget {
  const _SidebarNavButton({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final _ShellDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected
        ? ForgePalette.textPrimary
        : ForgePalette.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 10 : 14,
            vertical: collapsed ? 14 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: selected
                ? ForgePalette.primaryAccentSoft
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? ForgePalette.primaryAccent.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: collapsed
              ? Tooltip(
                  message: destination.label,
                  child: Icon(destination.icon, color: iconColor),
                )
              : Row(
                  children: [
                    Icon(destination.icon, color: iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            destination.label,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            destination.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(
                        Icons.arrow_outward_rounded,
                        size: 16,
                        color: ForgePalette.primaryAccent,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SidebarMetric extends StatelessWidget {
  const _SidebarMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ForgePalette.backgroundSecondary.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ForgePalette.border.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _SidebarIconAction extends StatelessWidget {
  const _SidebarIconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: ForgePalette.surfaceElevated.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: ForgePalette.border.withValues(alpha: 0.85),
              ),
            ),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, color: ForgePalette.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});

  final AuthAccount account;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ForgePalette.backgroundSecondary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ForgePalette.border.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _AccountOrb(account: account),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.displayName,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    account.email,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.account});

  final AuthAccount account;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ForgePalette.backgroundSecondary.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ForgePalette.border.withValues(alpha: 0.85)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AccountOrb(account: account, size: 34),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    account.isGuest ? 'Guest mode' : account.email,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountOrb extends StatelessWidget {
  const _AccountOrb({required this.account, this.size = 44});

  final AuthAccount account;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: account.isGuest
            ? ForgePalette.warmGradient
            : ForgePalette.buttonGradient,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: [
          BoxShadow(
            color:
                (account.isGuest
                        ? ForgePalette.sparkAccent
                        : ForgePalette.primaryAccent)
                    .withValues(alpha: 0.28),
            blurRadius: 20,
            spreadRadius: -10,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        account.initials,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
