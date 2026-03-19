import 'package:flutter/material.dart';

import '../../shared/forge_models.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';
import '../workspace/domain/forge_workspace_state.dart';

class GitWorkflowScreen extends StatefulWidget {
  const GitWorkflowScreen({super.key, required this.controller});

  final ForgeWorkspaceController controller;

  /// Shows a dialog to choose branch and commit message. Returns (branchName, commitMessage) or null if cancelled.
  static Future<({String branchName, String commitMessage})?> showCommitBranchDialog(
    BuildContext context, {
    required ForgeRepository repo,
    String? initialBranch,
    String? initialMessage,
  }) async {
    return showDialog<({String branchName, String commitMessage})>(
      context: context,
      builder: (context) => _CommitBranchDialog(
        repo: repo,
        initialBranch: initialBranch ?? repo.defaultBranch,
        initialMessage: initialMessage ?? '',
      ),
    );
  }

  @override
  State<GitWorkflowScreen> createState() => _GitWorkflowScreenState();
}

class _GitWorkflowScreenState extends State<GitWorkflowScreen> {
  final _branchController = TextEditingController(
    text: 'feature/mobile-review',
  );
  final _commitController = TextEditingController(
    text: 'feat: improve repository review cards',
  );
  final _prTitleController = TextEditingController(
    text: 'Improve repository review cards',
  );
  final _prDescriptionController = TextEditingController(
    text:
        'Updates the mobile review cards and preserves explicit diff approval before commit.',
  );
  String _mergeMethod = 'merge';

  @override
  void dispose() {
    _branchController.dispose();
    _commitController.dispose();
    _prTitleController.dispose();
    _prDescriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, _) {
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
                        title: 'Commit and PR flow',
                        subtitle:
                            'Branch creation, commit messages, and pull request details all stay explicit and user-controlled. Use "Deploy via Git" to commit and push so CI (e.g. GitHub Actions) can deploy Firebase functions.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _branchController,
                        decoration: const InputDecoration(
                          labelText: 'Branch name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _commitController,
                        decoration: const InputDecoration(
                          labelText: 'Commit message',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _prTitleController,
                        decoration: const InputDecoration(
                          labelText: 'Pull request title',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _prDescriptionController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _mergeMethod,
                        items: const [
                          DropdownMenuItem(
                            value: 'merge',
                            child: Text('Merge commit'),
                          ),
                          DropdownMenuItem(
                            value: 'squash',
                            child: Text('Squash'),
                          ),
                          DropdownMenuItem(
                            value: 'rebase',
                            child: Text('Rebase'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _mergeMethod = value);
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Merge method',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ForgeSecondaryButton(
                            label: state.isSubmittingGitAction
                                ? 'Working...'
                                : 'Create branch',
                            icon: Icons.alt_route_rounded,
                            onPressed: state.isSubmittingGitAction
                                ? null
                                : () => _submit(
                                    context,
                                    ForgeGitActionType.createBranch,
                                  ),
                            expanded: true,
                          ),
                          ForgePrimaryButton(
                            label: 'Commit changes',
                            icon: Icons.commit_rounded,
                            onPressed: state.isSubmittingGitAction ||
                                    state.selectedRepository == null
                                ? null
                                : () => _commitWithBranchPicker(context, state),
                            expanded: true,
                          ),
                          ForgeSecondaryButton(
                            label: 'Deploy via Git',
                            icon: Icons.rocket_launch_rounded,
                            onPressed: state.isSubmittingGitAction ||
                                    state.selectedRepository == null
                                ? null
                                : () => _deployFunctionsViaGit(context, state),
                            expanded: true,
                          ),
                          ForgeSecondaryButton(
                            label: 'Open pull request',
                            icon: Icons.call_split_rounded,
                            onPressed: state.isSubmittingGitAction
                                ? null
                                : () => _submit(
                                    context,
                                    ForgeGitActionType.openPullRequest,
                                  ),
                            expanded: true,
                          ),
                          ForgeSecondaryButton(
                            label: 'Merge pull request',
                            icon: Icons.merge_type_rounded,
                            onPressed: state.isSubmittingGitAction
                                ? null
                                : () => _submit(
                                    context,
                                    ForgeGitActionType.mergePullRequest,
                                  ),
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
      },
    );
  }

  Future<void> _commitWithBranchPicker(
    BuildContext context,
    ForgeWorkspaceState state,
  ) async {
    final repo = state.selectedRepository;
    if (repo == null) return;
    final result = await GitWorkflowScreen.showCommitBranchDialog(
      context,
      repo: repo,
      initialBranch: state.selectedBranch ?? repo.defaultBranch,
      initialMessage: _commitController.text.trim(),
    );
    if (result == null || !context.mounted) return;
    await _submit(
      context,
      ForgeGitActionType.commit,
      branchName: result.branchName,
      commitMessage: result.commitMessage,
    );
  }

  /// Opens branch picker with deploy-focused message, then commits so CI can deploy Firebase functions.
  Future<void> _deployFunctionsViaGit(
    BuildContext context,
    ForgeWorkspaceState state,
  ) async {
    final repo = state.selectedRepository;
    if (repo == null) return;
    const deployMessage = 'chore: deploy functions';
    final result = await GitWorkflowScreen.showCommitBranchDialog(
      context,
      repo: repo,
      initialBranch: state.selectedBranch ?? repo.defaultBranch,
      initialMessage: deployMessage,
    );
    if (result == null || !context.mounted) return;
    await _submit(
      context,
      ForgeGitActionType.commit,
      branchName: result.branchName,
      commitMessage: result.commitMessage.isEmpty ? deployMessage : result.commitMessage,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Committed and pushed. If your repo has CI (e.g. GitHub Actions) that runs Firebase deploy on this branch, functions will deploy automatically.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    ForgeGitActionType action, {
    String? branchName,
    String? commitMessage,
  }) async {
    try {
      await widget.controller.submitGitAction(
        actionType: action,
        draft: ForgeGitDraft(
          branchName: branchName ?? _branchController.text.trim(),
          commitMessage: commitMessage ?? _commitController.text.trim(),
          pullRequestTitle: _prTitleController.text.trim(),
          pullRequestDescription: _prDescriptionController.text.trim(),
          mergeMethod: _mergeMethod,
        ),
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_labelFor(action)} queued successfully.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _labelFor(ForgeGitActionType action) {
    return switch (action) {
      ForgeGitActionType.createBranch => 'Branch creation',
      ForgeGitActionType.commit => 'Commit',
      ForgeGitActionType.openPullRequest => 'Pull request',
      ForgeGitActionType.mergePullRequest => 'Merge',
    };
  }
}

const _newBranchValue = '<< new branch >>';

class _CommitBranchDialog extends StatefulWidget {
  const _CommitBranchDialog({
    required this.repo,
    required this.initialBranch,
    required this.initialMessage,
  });

  final ForgeRepository repo;
  final String initialBranch;
  final String initialMessage;

  @override
  State<_CommitBranchDialog> createState() => _CommitBranchDialogState();
}

class _CommitBranchDialogState extends State<_CommitBranchDialog> {
  late TextEditingController _branchController;
  late TextEditingController _messageController;
  late String? _dropdownValue;

  @override
  void initState() {
    super.initState();
    _branchController = TextEditingController(text: widget.initialBranch);
    _messageController = TextEditingController(text: widget.initialMessage);
    final branches = widget.repo.branches.isEmpty
        ? <String>[widget.repo.defaultBranch]
        : List<String>.from(widget.repo.branches);
    if (!branches.contains(widget.repo.defaultBranch)) {
      branches.insert(0, widget.repo.defaultBranch);
    }
    _dropdownValue = branches.contains(widget.initialBranch)
        ? widget.initialBranch
        : (branches.isNotEmpty ? branches.first : null);
  }

  @override
  void dispose() {
    _branchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  List<String> get _branchList {
    final b = widget.repo.branches.isEmpty
        ? <String>[widget.repo.defaultBranch]
        : List<String>.from(widget.repo.branches);
    if (!b.contains(widget.repo.defaultBranch)) b.insert(0, widget.repo.defaultBranch);
    return b;
  }

  @override
  Widget build(BuildContext context) {
    final branches = _branchList;
    return AlertDialog(
      title: const Text('Commit: choose branch'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Which branch should this commit go to?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            if (branches.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _dropdownValue ?? branches.first,
                decoration: const InputDecoration(
                  labelText: 'Branch',
                  border: OutlineInputBorder(),
                ),
                items: [
                  ...branches.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                  const DropdownMenuItem(value: _newBranchValue, child: Text('New branch…')),
                ],
                onChanged: (v) {
                  setState(() {
                    _dropdownValue = v;
                    if (v != null && v != _newBranchValue) {
                      _branchController.text = v;
                    }
                  });
                },
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _branchController,
              decoration: InputDecoration(
                labelText: branches.isNotEmpty ? 'Branch name (or edit above)' : 'Branch name',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Commit message',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final branch = _branchController.text.trim().isEmpty
                ? widget.repo.defaultBranch
                : _branchController.text.trim();
            final msg = _messageController.text.trim();
            if (msg.isEmpty) return;
            Navigator.of(context).pop((branchName: branch, commitMessage: msg));
          },
          child: const Text('Commit'),
        ),
      ],
    );
  }
}
