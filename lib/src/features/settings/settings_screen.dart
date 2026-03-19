import 'package:flutter/material.dart';

import '../../core/branding/app_branding.dart';
import '../../core/notifications/forge_push_controller.dart';
import '../../features/account/presentation/delete_account_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_account.dart';
import '../../features/auth/presentation/guest_gate_dialog.dart';
import '../../features/legal/legal_document_screen.dart';
import '../../features/onboarding/data/onboarding_storage.dart';
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
                        'Manage account access, connected providers, and account removal.',
                  ),
                  const SizedBox(height: 20),
                  if (currentAccount != null)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 460;
                        final walletButton = ForgeSecondaryButton(
                          label: 'Wallet',
                          icon: Icons.account_balance_wallet_rounded,
                          onPressed:
                              currentAccount.isGuest && controller != null
                              ? () => showGuestSignInRequiredDialog(
                                  context,
                                  authController: controller!,
                                  featureName: 'Wallet',
                                )
                              : onOpenWallet,
                          expanded: compact,
                        );
                        final details = Expanded(
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
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        );
                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const ForgeBrandMark(size: 52),
                                  const SizedBox(width: 12),
                                  details,
                                ],
                              ),
                              const SizedBox(height: 14),
                              walletButton,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            const ForgeBrandMark(size: 52),
                            const SizedBox(width: 12),
                            details,
                            const SizedBox(width: 12),
                            walletButton,
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Notifications',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ForgePill(
                        label: switch (pushState?.permissionStatus) {
                          ForgePushPermissionStatus.authorized => 'enabled',
                          ForgePushPermissionStatus.provisional =>
                            'provisional',
                          ForgePushPermissionStatus.denied => 'blocked',
                          _ => 'not asked',
                        },
                        icon: Icons.notifications_active_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Get alerts for checks, git actions, AI work, provider issues, wallet thresholds, and account security.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ForgeSecondaryButton(
                          label: pushState?.canReceivePush == true
                              ? 'Notifications ready'
                              : 'Enable push',
                          icon: Icons.notifications_rounded,
                          onPressed:
                              pushController == null ||
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
                      'Master switch for all $kAppDisplayName push categories.',
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
                        : (value) =>
                              workspaceController!.setNotificationCategory(
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
                        : (value) =>
                              workspaceController!.setNotificationCategory(
                                category: 'git',
                                enabled: value,
                              ),
                  ),
                  _NotificationToggle(
                    title: 'Repository sync',
                    subtitle:
                        'Connect success, sync completion, and repo issues.',
                    value: preferences.repository,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) =>
                              workspaceController!.setNotificationCategory(
                                category: 'repository',
                                enabled: value,
                              ),
                  ),
                  _NotificationToggle(
                    title: 'AI ready',
                    subtitle:
                        'Prompt completions and change requests ready to review.',
                    value: preferences.ai,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) =>
                              workspaceController!.setNotificationCategory(
                                category: 'ai',
                                enabled: value,
                              ),
                  ),
                  _NotificationToggle(
                    title: 'Provider access',
                    subtitle: 'GitHub connection problems and re-auth.',
                    value: preferences.provider,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) =>
                              workspaceController!.setNotificationCategory(
                                category: 'provider',
                                enabled: value,
                              ),
                  ),
                  _NotificationToggle(
                    title: 'Wallet alerts',
                    subtitle:
                        'Low balance, spend thresholds, and token resets.',
                    value: preferences.wallet,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) =>
                              workspaceController!.setNotificationCategory(
                                category: 'wallet',
                                enabled: value,
                              ),
                  ),
                  _NotificationToggle(
                    title: 'Security',
                    subtitle:
                        'Sensitive account events and confirmation notices.',
                    value: preferences.security,
                    enabled: preferences.enabled,
                    onChanged: workspaceController == null
                        ? null
                        : (value) =>
                              workspaceController!.setNotificationCategory(
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
                        : (value) =>
                              workspaceController!.setNotificationCategory(
                                category: 'digest',
                                enabled: value,
                              ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ForgeSectionHeader(
                    title: 'Providers',
                    subtitle: connections.isEmpty
                        ? 'No Git provider connections stored yet.'
                        : 'Connected accounts used for repository sync.',
                    trailing: workspaceController == null
                        ? null
                        : ForgeSecondaryButton(
                            label: 'Connect repo',
                            icon: Icons.link_rounded,
                            onPressed:
                                currentAccount?.isGuest == true &&
                                    controller != null
                                ? () => showGuestSignInRequiredDialog(
                                    context,
                                    authController: controller!,
                                    featureName: 'Connecting repositories',
                                  )
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            RepositoryConnectionScreen(
                                              controller: workspaceController!,
                                            ),
                                      ),
                                    );
                                  },
                          ),
                  ),
                  const SizedBox(height: 10),
                  if (connections.isNotEmpty)
                    ...connections.map(
                      (connection) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ForgePill(
                              label: connection.status.name,
                              icon: Icons.link_rounded,
                            ),
                            Text(
                              '${connection.providerLabel} • ${connection.account}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  const ForgePill(
                    label: 'Dark-first design system',
                    icon: Icons.dark_mode_rounded,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$kAppDisplayName uses a single premium dark theme tuned for repository review, code editing, and high-contrast diffs.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Legal', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Text(
                    'AI suggestions are provided by third-party services. Your prompts and code are sent to these services to generate results. Output is for assistance only; you review and approve all changes before they are applied.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ForgeSecondaryButton(
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
                      const SizedBox(height: 10),
                      ForgeSecondaryButton(
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
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ForgePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account actions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ForgeSecondaryButton(
                        label: 'Account',
                        icon: Icons.person_rounded,
                        onPressed:
                            currentAccount?.isGuest == true &&
                                controller != null
                            ? () => showGuestSignInRequiredDialog(
                                context,
                                authController: controller!,
                                featureName: 'Account settings',
                              )
                            : onOpenAccount,
                        expanded: true,
                      ),
                      const SizedBox(height: 10),
                      ForgeSecondaryButton(
                        label: 'Replay onboarding',
                        icon: Icons.slideshow_rounded,
                        onPressed: () async {
                          final storage = await OnboardingStorage.create();
                          await storage.setOnboardingCompleted(false);
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Onboarding will show again on next app launch.',
                              ),
                            ),
                          );
                        },
                        expanded: true,
                      ),
                      const SizedBox(height: 10),
                      ForgeSecondaryButton(
                        label: 'Sign out',
                        icon: Icons.logout_rounded,
                        onPressed: controller == null
                            ? null
                            : () => controller!.signOut(),
                        expanded: true,
                      ),
                      const SizedBox(height: 10),
                      ForgePrimaryButton(
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
