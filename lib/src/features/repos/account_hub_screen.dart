import 'package:flutter/material.dart';

import '../../core/branding/app_branding.dart';
import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../auth/application/auth_controller.dart';
import '../auth/domain/auth_account.dart';
import '../auth/presentation/guest_gate_dialog.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';

/// Account hub: shows all repos in the GitHub account so the user
/// and AI can work with them. Lists connected repos and all available
/// account repos with Connect / Select for AI. Guests see a sign-in CTA.
class AccountHubScreen extends StatefulWidget {
  const AccountHubScreen({
    super.key,
    required this.controller,
    this.account,
    this.authController,
    this.onSwitchToRepoTab,
    this.onSwitchToAskTab,
  });

  final ForgeWorkspaceController controller;
  final AuthAccount? account;
  final AuthController? authController;
  final VoidCallback? onSwitchToRepoTab;
  final VoidCallback? onSwitchToAskTab;

  @override
  State<AccountHubScreen> createState() => _AccountHubScreenState();
}

class _AccountHubScreenState extends State<AccountHubScreen> {
  List<ForgeAvailableRepository> _githubRepos = const [];
  bool _loadingGitHub = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAllAccountRepos();
  }

  Future<void> _loadAllAccountRepos() async {
    setState(() {
      _loadError = null;
      _loadingGitHub = true;
    });
    try {
      final results = await Future.wait([
        widget.controller
            .listProviderRepositories(provider: 'github')
            .catchError((e) => <ForgeAvailableRepository>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _githubRepos = results[0];
        _loadingGitHub = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = forgeUserFriendlyMessage(e);
        _loadingGitHub = false;
      });
    }
  }

  bool _isConnected(
    ForgeRepository connected,
    String provider,
    String fullName,
  ) {
    return connected.provider.name == provider &&
        connected.repoLabel == fullName;
  }

  ForgeRepository? _findConnected(
    List<ForgeRepository> connected,
    String provider,
    String fullName,
  ) {
    for (final c in connected) {
      if (_isConnected(c, provider, fullName)) return c;
    }
    return null;
  }

  Future<void> _connectRepo(ForgeAvailableRepository repo) async {
    try {
      await widget.controller.connectRepository(
        ForgeConnectRepositoryDraft(
          provider: repo.provider,
          repository: repo.fullName,
          defaultBranch: repo.defaultBranch,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connected ${repo.fullName}. Use Ask or Repo to work with it.',
          ),
        ),
      );
      await _loadAllAccountRepos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(forgeUserFriendlyMessage(e))));
    }
  }

  Future<({String branchName, String commitMessage})?> _askBranchAndCommit({
    required String defaultBranch,
    String defaultMessage = 'chore: add run-app workflow',
  }) async {
    final branchController = TextEditingController(text: defaultBranch);
    final commitController = TextEditingController(text: defaultMessage);
    return showDialog<({String branchName, String commitMessage})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Install run-app workflow'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: branchController,
              decoration: const InputDecoration(
                labelText: 'Branch',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commitController,
              decoration: const InputDecoration(
                labelText: 'Commit message',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop((
              branchName: branchController.text.trim().isEmpty
                  ? defaultBranch
                  : branchController.text.trim(),
              commitMessage: commitController.text.trim().isEmpty
                  ? defaultMessage
                  : commitController.text.trim(),
            )),
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }

  Future<void> _installWorkflowForSelected(ForgeRepository repo) async {
    final draft = await _askBranchAndCommit(
      defaultBranch:
          widget.controller.value.selectedBranch ?? repo.defaultBranch,
    );
    if (draft == null) return;
    try {
      await widget.controller.installRunAppWorkflowViaGit(
        branchName: draft.branchName,
        commitMessage: draft.commitMessage,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Installed run-app.yml on ${draft.branchName} for ${repo.name}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(forgeUserFriendlyMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = widget.account?.isGuest ?? false;

    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        if (isGuest && widget.authController != null) {
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
                          title: 'Account hub',
                          subtitle:
                              'Link GitHub to see and connect repositories from your account.',
                        ),
                        const SizedBox(height: 20),
                        ForgePrimaryButton(
                          label: 'Sign in to link accounts',
                          icon: Icons.login_rounded,
                          expanded: true,
                          onPressed: () => showGuestSignInRequiredDialog(
                            context,
                            authController: widget.authController!,
                            featureName: 'Account hub',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final connected = state.repositories;
        final connections = state.connections;
        final selectedRepo = state.selectedRepository;
        final hasGitHub = connections.any(
          (c) => c.providerLabel.toLowerCase() == 'github',
        );
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                ForgePanel(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ForgeSectionHeader(
                        title: 'Account hub',
                        subtitle:
                            'All repos in your GitHub account. Connect any repo so the AI and editor can work with it.',
                      ),
                      if (_loadError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _loadError!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: ForgePalette.error),
                        ),
                        const SizedBox(height: 8),
                        ForgeSecondaryButton(
                          label: 'Retry',
                          icon: Icons.refresh_rounded,
                          onPressed: _loadAllAccountRepos,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Connected in app (see kAppDisplayName in UI)
                ForgePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ForgeSectionHeader(
                        title: 'Connected in $kAppDisplayName',
                        subtitle:
                            'These repos are synced. Select one to use in Ask or the Editor.',
                        trailing: ForgePill(
                          label: '${connected.length}',
                          icon: Icons.folder_rounded,
                          color: ForgePalette.glowAccent,
                        ),
                      ),
                      if (selectedRepo != null) ...[
                        const SizedBox(height: 12),
                        ForgeSecondaryButton(
                          label: 'Install run-app.yml',
                          icon: Icons.download_rounded,
                          onPressed: state.isSubmittingGitAction
                              ? null
                              : () => _installWorkflowForSelected(selectedRepo),
                          expanded: true,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (connected.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No repos connected yet. Connect from the list below or use the Repo tab.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      else
                        ...connected.map((repo) {
                          final selected = selectedRepo?.id == repo.id;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ForgePanel(
                              onTap: () =>
                                  widget.controller.selectRepository(repo),
                              highlight: selected,
                              backgroundColor: selected
                                  ? ForgePalette.glowAccent.withValues(
                                      alpha: 0.12,
                                    )
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compact =
                                          constraints.maxWidth < 340;
                                      final title = Text(
                                        repo.name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                      );
                                      if (compact) {
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  repo.provider ==
                                                          ForgeProvider.github
                                                      ? Icons.code_rounded
                                                      : Icons
                                                            .merge_type_rounded,
                                                  color:
                                                      ForgePalette.glowAccent,
                                                  size: 22,
                                                ),
                                                if (selected) ...[
                                                  const SizedBox(width: 8),
                                                  const Icon(
                                                    Icons.check_circle_rounded,
                                                    color:
                                                        ForgePalette.glowAccent,
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            title,
                                          ],
                                        );
                                      }

                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            repo.provider ==
                                                    ForgeProvider.github
                                                ? Icons.code_rounded
                                                : Icons.merge_type_rounded,
                                            color: ForgePalette.glowAccent,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(child: title),
                                          if (selected)
                                            const Icon(
                                              Icons.check_circle_rounded,
                                              color: ForgePalette.glowAccent,
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  ForgeSecondaryButton(
                                    label: 'Use in Repo',
                                    icon: Icons.folder_open_rounded,
                                    onPressed: () {
                                      widget.controller.selectRepository(repo);
                                      widget.onSwitchToRepoTab?.call();
                                    },
                                    expanded: true,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // All from GitHub
                ForgePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'All from GitHub',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_loadingGitHub)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            ForgePill(
                              label: '${_githubRepos.length}',
                              icon: Icons.code_rounded,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasGitHub
                            ? 'Connect any repo so the AI can work with it.'
                            : 'Sign in with GitHub to see your repos here.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ForgePalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!hasGitHub)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Connect GitHub in the Repo tab to list your account repos.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      else if (_githubRepos.isEmpty && !_loadingGitHub)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No GitHub repos returned. Try the Repo tab to connect manually.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      else
                        ..._githubRepos.take(50).map((repo) {
                          final existing = _findConnected(
                            connected,
                            'github',
                            repo.fullName,
                          );
                          final displayName = repo.name.isNotEmpty
                              ? repo.name
                              : repo.fullName;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 10),
                                if (existing != null)
                                  ForgeSecondaryButton(
                                    label: 'Select',
                                    icon: Icons.check_rounded,
                                    onPressed: () {
                                      widget.controller.selectRepository(
                                        existing,
                                      );
                                      widget.onSwitchToAskTab?.call();
                                    },
                                    expanded: true,
                                  )
                                else
                                  ForgePrimaryButton(
                                    label: 'Connect',
                                    icon: Icons.link_rounded,
                                    onPressed: state.isConnectingRepository
                                        ? null
                                        : () => _connectRepo(repo),
                                    expanded: true,
                                  ),
                              ],
                            ),
                          );
                        }),
                      if (_githubRepos.length > 50)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '+ ${_githubRepos.length - 50} more. Use Repo tab to search.',
                            style: Theme.of(context).textTheme.bodySmall,
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
