import 'package:flutter/material.dart';

import '../../core/notifications/forge_push_controller.dart';
import '../../features/account/presentation/delete_account_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_account.dart';
import '../../features/legal/legal_document_screen.dart';
import '../../shared/forge_models.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../repos/repository_connection_screen.dart';
import '../workspace/application/forge_workspace_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.controller,
    this.account,
    this.workspaceController,
    this.pushController,
    this.onOpenWallet,
    this.onOpenAccount,
  });

  final AuthController? controller;
  final AuthAccount? account;
  final ForgeWorkspaceController? workspaceController;
  final ForgePushController? pushController;
  final VoidCallback? onOpenWallet;
  final VoidCallback? onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final currentAccount = account;
    Widget buildBody(List<ForgeConnection> connections) {
      if (pushController == null) {
        return _buildScaffold(
          context,
          currentAccount: currentAccount,
          connections: connections,
        );
      }
      return ValueListenableBuilder(
        valueListenable: pushController!,
        builder: (context, _, _) {
          return _buildScaffold(
            context,
            currentAccount: currentAccount,
            connections: connections,
          );
        },
      );
    }
    if (workspaceController == null) {
      return buildBody(const []);
    }

    return ValueListenableBuilder(
      valueListenable: workspaceController!,
      builder: (context, _, _) {
        return buildBody(workspaceController!.value.connections);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required AuthAccount? currentAccount,
    required List<ForgeConnection> connections,
  }) {
    final preferences =
        workspaceController?.value.notificationPreferences ??
        ForgeNotificationPreferences.defaults;
    final pushState = pushController?.value;
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
                  const ForgeSectionHeader(
                    title: 'Settings',
                    subtitle:
                        'Manage account access, connected providers, the dark UI system, and destructive account actions.',
                  ),
                  const SizedBox(height: 16),
                  if (currentAccount != null)
                    Row(
                      children: [
                        const ForgeBrandMark(size: 52),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentAccount.displayName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentAccount.email,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
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
            const SizedBox(height: 16),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Notifications',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      ForgePill(
                        label: switch (pushState?.permissionStatus) {
                          ForgePushPermissionStatus.authorized => 'enabled',
                          ForgePushPermissionStatus.provisional => 'provisional',
                          ForgePushPermissionStatus.denied => 'blocked',
                          _ => 'not asked',
                        },
                        icon: Icons.notifications_active_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Get alerts for checks, git actions, AI work, provider issues, wallet thresholds, and account security.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ForgeSecondaryButton(
                          label: pushState?.canReceivePush == true
                              ? 'Notifications ready'
                              : 'Enable push',
                          icon: Icons.notifications_rounded,
                          onPressed: pushController == null ||
                                  pushState?.isRequestingPermission == true
                              ? null
                              : () => pushController!.requestPermission(),
                          expanded: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable notifications'),
                    subtitle: const Text(
                      'Master switch for all ForgeAI push categories.',
                    ),
                    value: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) => workspaceController!
                            .setNotificationsEnabled(value),
                  ),
                  _NotificationToggle(
                    title: 'Checks and workflows',
                    subtitle: 'Tests, lint, builds, and app-run results.',
                    value: preferences.checks,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) => workspaceController!.setNotificationCategory(
                              category: 'checks',
                              enabled: value,
                            ),
                  ),
                  _NotificationToggle(
                    title: 'Git activity',
                    subtitle: 'Commits, PR opens, merges, and failures.',
                    value: preferences.git,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) => workspaceController!.setNotificationCategory(
                              category: 'git',
                              enabled: value,
                            ),
                  ),
                  _NotificationToggle(
                    title: 'Repository sync',
                    subtitle: 'Connect success, sync completion, and repo issues.',
                    value: preferences.repository,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) => workspaceController!.setNotificationCategory(
                              category: 'repository',
                              enabled: value,
                            ),
                  ),
                  _NotificationToggle(
                    title: 'AI ready',
                    subtitle: 'Prompt completions and change requests ready to review.',
                    value: preferences.ai,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) => workspaceController!.setNotificationCategory(
                              category: 'ai',
                              enabled: value,
                            ),
                  ),
                  _NotificationToggle(
                    title: 'Provider access',
                    subtitle: 'GitHub or GitLab connection problems and re-auth.',
                    value: preferences.provider,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) => workspaceController!.setNotificationCategory(
                              category: 'provider',
                              enabled: value,
                            ),
                  ),
                  _NotificationToggle(
                    title: 'Wallet alerts',
                    subtitle: 'Low balance, spend thresholds, and token resets.',
                    value: preferences.wallet,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) => workspaceController!.setNotificationCategory(
                              category: 'wallet',
                              enabled: value,
                            ),
                  ),
                  _NotificationToggle(
                    title: 'Security',
                    subtitle: 'Sensitive account events and confirmation notices.',
                    value: preferences.security,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) => workspaceController!.setNotificationCategory(
                              category: 'security',
                              enabled: value,
                            ),
                  ),
                  _NotificationToggle(
                    title: 'Digest and reminders',
                    subtitle: 'Daily summary and unfinished work nudges.',
                    value: preferences.digest,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) => workspaceController!.setNotificationCategory(
                              category: 'digest',
                              enabled: value,
                            ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Providers',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (workspaceController != null)
                        ForgeSecondaryButton(
                          label: 'Connect repo',
                          icon: Icons.link_rounded,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RepositoryConnectionScreen(
                                  controller: workspaceController!,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (connections.isEmpty)
                    Text(
                      'No Git provider connections stored yet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    ...connections.map(
                      (connection) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            ForgePill(
                              label: connection.status.name,
                              icon: Icons.link_rounded,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${connection.providerLabel} • ${connection.account}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  const ForgePill(
                    label: 'Dark-first design system',
                    icon: Icons.dark_mode_rounded,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ForgeAI uses a single premium dark theme tuned for repository review, code editing, and high-contrast diffs.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Legal',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI suggestions are provided by third-party services. Your prompts and code are sent to these services to generate results. Output is for assistance only; you review and approve all changes before they are applied.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ForgeSecondaryButton(
                          label: 'Privacy Policy',
                          icon: Icons.privacy_tip_outlined,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LegalDocumentScreen(
                                  title: 'Privacy Policy',
                                  assetPath: 'assets/legal/privacy_policy.md',
                                ),
                              ),
                            );
                          },
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ForgeSecondaryButton(
                          label: 'Terms of Service',
                          icon: Icons.description_outlined,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LegalDocumentScreen(
                                  title: 'Terms of Service',
                                  assetPath: 'assets/legal/terms_of_service.md',
                                ),
                              ),
                            );
                          },
                          expanded: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account actions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ForgeSecondaryButton(
                          label: 'Account',
                          icon: Icons.person_rounded,
                          onPressed: onOpenAccount,
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ForgeSecondaryButton(
                          label: 'Logout',
                          icon: Icons.logout_rounded,
                          onPressed: controller == null
                              ? null
                              : () => controller!.signOut(),
                          expanded: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ForgePrimaryButton(
                          label: 'Delete account',
                          icon: Icons.delete_forever_rounded,
                          onPressed: controller == null
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => DeleteAccountScreen(
                                        controller: controller!,
                                      ),
                                    ),
                                  );
                                },
                          expanded: true,
                        ),
                      ),
                    ],
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

class _NotificationToggle extends StatelessWidget {
  const _NotificationToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: !enabled || onChanged == null ? null : onChanged,
    );
  }
}
