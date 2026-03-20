import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../auth/application/auth_controller.dart';
import '../auth/domain/auth_account.dart';
import '../auth/presentation/guest_gate_dialog.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';
import '../workspace/domain/forge_workspace_state.dart';
import 'new_ai_project_screen.dart';
import 'repository_browser_screen.dart';
import 'repository_connection_screen.dart';

class RepositoriesScreen extends StatefulWidget {
  const RepositoriesScreen({
    super.key,
    required this.controller,
    this.account,
    this.authController,
    this.onOpenFile,
  });

  final ForgeWorkspaceController controller;
  final AuthAccount? account;
  final AuthController? authController;
  final ValueChanged<ForgeFileNode>? onOpenFile;

  @override
  State<RepositoriesScreen> createState() => _RepositoriesScreenState();
}

class _RepositoriesScreenState extends State<RepositoriesScreen> {
  @override
  Widget build(BuildContext context) {
    final isGuest = widget.account?.isGuest ?? false;

    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final repositories = state.repositories;
        final selectedRepository = state.selectedRepository;
        final selectedBranch =
            state.selectedBranch ?? selectedRepository?.defaultBranch ?? 'main';
        final branchOptions = _branchOptions(
          selectedRepository,
          selectedBranch,
        );

        void onConnectPressed() {
          if (isGuest && widget.authController != null) {
            showGuestSignInRequiredDialog(
              context,
              authController: widget.authController!,
              featureName: 'Connecting repositories',
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    RepositoryConnectionScreen(controller: widget.controller),
              ),
            );
          }
        }

        void onNewAiProjectPressed() {
          if (isGuest && widget.authController != null) {
            showGuestSignInRequiredDialog(
              context,
              authController: widget.authController!,
              featureName: 'Creating a new repository',
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    NewAiProjectScreen(controller: widget.controller),
              ),
            );
          }
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Page purpose
                  ForgePanel(
                    highlight: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ForgeSectionHeader(
                          title: 'Repositories',
                          subtitle:
                              'Connect repos here, then open a file to jump to the Code tab with the file loaded.',
                        ),
                        if (repositories.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ForgeSecondaryButton(
                            label: 'Add repository',
                            icon: Icons.add_rounded,
                            onPressed: onConnectPressed,
                          ),
                          const SizedBox(height: 10),
                          ForgeSecondaryButton(
                            label: 'New project (AI)',
                            icon: Icons.auto_awesome_rounded,
                            onPressed: onNewAiProjectPressed,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Empty state
                  if (repositories.isEmpty) ...[
                    const SizedBox(height: 24),
                    ForgePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.folder_open_rounded,
                                size: 28,
                                color: ForgePalette.glowAccent.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'No repositories yet',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Connect GitHub to browse files, review changes, and run the agent on your codebase.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ForgePrimaryButton(
                            label: isGuest
                                ? 'Sign in to connect'
                                : 'Connect repository',
                            icon: isGuest
                                ? Icons.login_rounded
                                : Icons.link_rounded,
                            onPressed: onConnectPressed,
                            expanded: true,
                          ),
                          const SizedBox(height: 12),
                          ForgeSecondaryButton(
                            label: isGuest
                                ? 'Sign in to create a project'
                                : 'New project (AI)',
                            icon: Icons.auto_awesome_rounded,
                            onPressed: onNewAiProjectPressed,
                            expanded: true,
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Repo list + selected strip + file tree
                  if (repositories.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    // Repository list
                    ForgeSectionHeader(
                      title: 'Your repositories',
                      subtitle: 'Tap one to browse files and use in Agent.',
                    ),
                    const SizedBox(height: 12),
                    ...repositories.map((repo) {
                      final selected = selectedRepository?.id == repo.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ForgePanel(
                          onTap: () => widget.controller.selectRepository(repo),
                          highlight: selected,
                          backgroundColor: selected
                              ? ForgePalette.primaryAccent.withValues(
                                  alpha: 0.08,
                                )
                              : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ForgePill(
                                    label: repo.providerLabel,
                                    icon: repo.provider == ForgeProvider.github
                                        ? Icons.code_rounded
                                        : Icons.merge_rounded,
                                    color: repo.provider == ForgeProvider.github
                                        ? ForgePalette.glowAccent
                                        : ForgePalette.warning,
                                  ),
                                  IconButton(
                                    tooltip: 'Share repository',
                                    onPressed: () => _shareRepository(repo),
                                    icon: const Icon(
                                      Icons.share_rounded,
                                      size: 20,
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: ForgePalette.glowAccent,
                                      size: 20,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                repo.repoLabel,
                                style: Theme.of(context).textTheme.titleMedium,
                                softWrap: true,
                              ),
                              if (repo.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  repo.description,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 220,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.account_tree_rounded,
                                          size: 14,
                                          color: ForgePalette.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            repo.defaultBranch,
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelMedium,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${repo.changedFiles} changed',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    // Selected repo: branch + actions
                    if (selectedRepository != null) ...[
                      const SizedBox(height: 24),
                      ForgePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Working with ${selectedRepository.repoLabel}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  branchOptions.contains(selectedBranch)
                                  ? selectedBranch
                                  : (selectedRepository.defaultBranch),
                              isExpanded: true,
                              selectedItemBuilder: (context) => branchOptions
                                  .map(
                                    (b) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        b,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: branchOptions
                                  .map(
                                    (b) => DropdownMenuItem(
                                      value: b,
                                      child: Text(b, softWrap: true),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  widget.controller.selectBranch(value);
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                ForgePrimaryButton(
                                  label: state.isRunningCheck
                                      ? 'Running app…'
                                      : 'Run app',
                                  icon: Icons.rocket_launch_rounded,
                                  onPressed: state.isRunningCheck
                                      ? null
                                      : () => _runAppFromRepository(
                                          context,
                                          selectedRepository,
                                        ),
                                ),
                                ForgeSecondaryButton(
                                  label: state.isSyncing ? 'Syncing…' : 'Sync',
                                  icon: Icons.sync_rounded,
                                  onPressed: state.isSyncing
                                      ? null
                                      : () async {
                                          try {
                                            await widget.controller
                                                .refreshSelectedRepository();
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Repository synced.',
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Sync failed: ${forgeUserFriendlyMessage(e)}',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                ),
                                ForgeSecondaryButton(
                                  label: 'New branch',
                                  icon: Icons.add_rounded,
                                  onPressed: state.isSubmittingGitAction
                                      ? null
                                      : () => _showNewBranchDialog(
                                          context,
                                          selectedRepository,
                                          selectedBranch,
                                          state,
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${selectedRepository.changedFiles} changed • ${selectedRepository.openPullRequests} open PRs',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],

                    // File tree
                    const SizedBox(height: 24),
                    RepositoryBrowserScreen(
                      files: state.files,
                      selectedPath: state.currentDocument?.path,
                      onOpenFile: (file) async {
                        try {
                          await widget.controller.openFile(file);
                          if (!context.mounted) return;
                          widget.onOpenFile?.call(file);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not open file: ${forgeUserFriendlyMessage(e)}',
                              ),
                            ),
                          );
                        }
                      },
                      onSync: selectedRepository != null
                          ? () async {
                              try {
                                await widget.controller
                                    .refreshSelectedRepository();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Repository synced.'),
                                  ),
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Sync failed: ${forgeUserFriendlyMessage(e)}',
                                    ),
                                  ),
                                );
                              }
                            }
                          : null,
                      isSyncing: state.isSyncing,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<String> _branchOptions(ForgeRepository? repo, String current) {
    if (repo == null) return ['main'];
    final fromRepo = repo.branches.isNotEmpty
        ? repo.branches
        : [repo.defaultBranch];
    final set = {...fromRepo, current};
    return set.toList()..sort((a, b) => a.compareTo(b));
  }

  Future<void> _shareRepository(ForgeRepository repo) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _buildRepositoryShareText(repo);
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: repo.repoLabel),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not share repository: ${forgeUserFriendlyMessage(error)}',
          ),
        ),
      );
    }
  }

  String _buildRepositoryShareText(ForgeRepository repo) {
    final description = repo.description.trim();
    if (description.isEmpty) {
      return '${repo.repoLabel}\n${repo.shareUrl}';
    }
    return '${repo.repoLabel}\n$description\n${repo.shareUrl}';
  }

  Future<void> _runAppFromRepository(
    BuildContext context,
    ForgeRepository repo,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final logsUrl = await widget.controller.runAppWorkflow();
      if (!context.mounted) return;
      final suffix = (logsUrl ?? '').trim().isEmpty
          ? 'Open GitHub Actions in this repo to view logs and artifacts.'
          : 'Logs: $logsUrl';
      messenger.showSnackBar(
        SnackBar(content: Text('Run started for ${repo.repoLabel}. $suffix')),
      );
    } catch (error) {
      if (!context.mounted) return;
      final missingWorkflow = forgeErrorLooksLikeMissingGithubWorkflow(error);
      if (!missingWorkflow) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Could not run app: ${forgeUserFriendlyMessage(error)}',
            ),
          ),
        );
        return;
      }

      final shouldInstall = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Set up run app workflow'),
          content: Text(
            'This repo is missing `.github/workflows/run-app.yml`.\n\n'
            'Install it now on branch `${repo.defaultBranch}` so you can run the app from here?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Install'),
            ),
          ],
        ),
      );

      if (shouldInstall != true) return;

      await widget.controller.installRunAppWorkflowViaGit(
        branchName: repo.defaultBranch,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Installed run-app workflow on ${repo.defaultBranch}. Tap Run app again.',
          ),
        ),
      );
    }
  }

  Future<void> _showNewBranchDialog(
    BuildContext context,
    ForgeRepository repo,
    String fromBranch,
    ForgeWorkspaceState state,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create a new branch from $fromBranch. Enter the branch name.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Branch name',
                hintText: 'e.g. feature/my-change',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                final name = value.trim();
                if (name.isNotEmpty) Navigator.of(context).pop(name);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(name);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !context.mounted) return;
    try {
      await widget.controller.submitGitAction(
        actionType: ForgeGitActionType.createBranch,
        draft: ForgeGitDraft(
          branchName: result,
          commitMessage: 'chore: create branch $result',
          pullRequestTitle: '',
          pullRequestDescription: '',
        ),
      );
      if (!context.mounted) return;
      await widget.controller.selectBranch(result);
      await widget.controller.refreshSelectedRepository();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Branch "$result" created and selected.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text('Could not create branch: ${forgeUserFriendlyMessage(e)}'),
        ),
      );
    }
  }
}
