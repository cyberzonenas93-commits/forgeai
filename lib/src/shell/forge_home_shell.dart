import 'package:flutter/material.dart';

import '../core/notifications/forge_push_controller.dart';
import '../features/account/presentation/account_settings_screen.dart';
import '../features/activity/activity_timeline_screen.dart';
import '../features/ask/ask_screen.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/domain/auth_account.dart';
import '../features/checks/checks_dashboard_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/repos/account_hub_screen.dart';
import '../features/repos/repositories_screen.dart';
import '../features/settings/settings_screen.dart';
import '../shared/forge_models.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/workspace/application/forge_workspace_controller.dart';

class ForgeHomeShell extends StatefulWidget {
  const ForgeHomeShell({
    super.key,
    required this.controller,
    required this.account,
    required this.workspaceController,
    required this.pushController,
  });

  final AuthController controller;
  final AuthAccount account;
  final ForgeWorkspaceController workspaceController;
  final ForgePushController pushController;

  @override
  State<ForgeHomeShell> createState() => _ForgeHomeShellState();
}

class _ForgeHomeShellState extends State<ForgeHomeShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.pushController.attachRouteHandler(_handlePushRoute);
  }

  @override
  void dispose() {
    widget.pushController.detachRouteHandler();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.workspaceController,
      builder: (context, state, _) {
        final pages = <Widget>[
          DashboardScreen(
            controller: widget.workspaceController,
            onOpenRepository: () => setState(() => _currentIndex = 3),
            onOpenHub: () => setState(() => _currentIndex = 1),
            onOpenEditor: () => setState(() => _currentIndex = 2),
            onOpenChecks: null,
            onOpenWallet: () =>
                _open(WalletScreen(controller: widget.workspaceController)),
            onOpenActivity: () => _open(
              ActivityTimelineScreen(controller: widget.workspaceController),
            ),
          ),
          AccountHubScreen(
            controller: widget.workspaceController,
            onSwitchToRepoTab: () => setState(() => _currentIndex = 3),
            onSwitchToAskTab: () => setState(() => _currentIndex = 2),
          ),
          AskScreen(
            controller: widget.workspaceController,
            onSwitchToEditorTab: () => setState(() => _currentIndex = 3),
          ),
          RepositoriesScreen(
            controller: widget.workspaceController,
            onOpenFile: (_) => setState(() => _currentIndex = 2),
          ),
          SettingsScreen(
            controller: widget.controller,
            account: widget.account,
            workspaceController: widget.workspaceController,
            pushController: widget.pushController,
            onOpenWallet: () =>
                _open(WalletScreen(controller: widget.workspaceController)),
            onOpenAccount: () =>
                _open(AccountSettingsScreen(controller: widget.controller)),
          ),
        ];

        return Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
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
            child: KeyedSubtree(
              key: ValueKey<int>(_currentIndex),
              child: pages[_currentIndex],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() => _currentIndex = index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_rounded),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.hub_rounded),
                label: 'Hub',
              ),
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                label: 'Prompt',
              ),
              NavigationDestination(
                icon: Icon(Icons.folder_copy_rounded),
                label: 'Repo',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
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
        setState(() => _currentIndex = 3);
        return;
      case ForgeNotificationDestination.settings:
        setState(() => _currentIndex = 4);
        return;
      case ForgeNotificationDestination.wallet:
        await _open(WalletScreen(controller: widget.workspaceController));
        return;
      case ForgeNotificationDestination.activity:
        await _open(
          ActivityTimelineScreen(controller: widget.workspaceController),
        );
        return;
      case ForgeNotificationDestination.checks:
        await _open(ChecksDashboardScreen(controller: widget.workspaceController));
        return;
    }
  }
}
