import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../ai/ai_task_screen.dart';
import '../diff/diff_review_screen.dart';
import '../git/git_workflow_screen.dart';
import '../workspace/application/forge_workspace_controller.dart';

class EditorWorkflowScreen extends StatefulWidget {
  const EditorWorkflowScreen({
    super.key,
    required this.controller,
    this.onSwitchToRepoTab,
  });

  final ForgeWorkspaceController controller;
  final VoidCallback? onSwitchToRepoTab;

  @override
  State<EditorWorkflowScreen> createState() => _EditorWorkflowScreenState();
}

class _EditorWorkflowScreenState extends State<EditorWorkflowScreen> {
  late final TextEditingController _textController = TextEditingController();
  String? _syncedPath;
  bool _isApplyingExternalText = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_handleTextChanged);
    widget.controller.addListener(_syncFromWorkspace);
    _syncFromWorkspace();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromWorkspace);
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (_isApplyingExternalText) {
      return;
    }
    widget.controller.updateDraft(_textController.text);
  }

  void _syncFromWorkspace() {
    final document = widget.controller.value.currentDocument;
    final nextPath = document?.path;
    final nextContent = document?.content ?? '';
    if (_syncedPath == nextPath && _textController.text == nextContent) {
      return;
    }
    _syncedPath = nextPath;
    _isApplyingExternalText = true;
    _textController.value = TextEditingValue(
      text: nextContent,
      selection: TextSelection.collapsed(offset: nextContent.length),
    );
    _isApplyingExternalText = false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final document = state.currentDocument;
        final selectedRepository = state.selectedRepository;
        final lineCount = document == null
            ? 0
            : '\n'.allMatches(_textController.text).length + 1;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.errorMessage != null &&
                    state.errorMessage!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: ForgePalette.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: ForgePalette.error,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                state.errorMessage!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: ForgePalette.error),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ForgePanel(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Editor',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  document?.path ??
                                      'Open a repository file to start editing',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          ForgePill(
                            label:
                                state.selectedBranch ??
                                selectedRepository?.defaultBranch ??
                                'main',
                            icon: Icons.commit_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ForgePrimaryButton(
                            label: state.isSavingFile ? 'Saving...' : 'Save',
                            icon: Icons.save_rounded,
                            onPressed: document == null || state.isSavingFile
                                ? null
                                : () => _save(context),
                          ),
                          ForgeSecondaryButton(
                            label: 'Ask AI to edit',
                            icon: Icons.auto_awesome_rounded,
                            onPressed: document == null
                                ? null
                                : () => _open(
                                    context,
                                    AiTaskScreen(controller: widget.controller),
                                  ),
                          ),
                          ForgeSecondaryButton(
                            label: 'Diff',
                            icon: Icons.compare_arrows_rounded,
                            onPressed: state.currentChangeRequest == null
                                ? null
                                : () => _open(
                                    context,
                                    DiffReviewScreen(
                                      controller: widget.controller,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ForgePanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Row(
                            children: [
                              ForgeAiIndicator(
                                label: document == null
                                    ? 'Select a file to begin'
                                    : (state.currentChangeRequest == null
                                          ? 'Describe your change in plain language, then use Ask AI to edit'
                                          : 'AI diff ready for review'),
                              ),
                              const Spacer(),
                              Text(
                                '$lineCount lines',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: ForgePalette.surfaceElevated,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: document == null
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'No file open. Open a file from the Repo tab to edit, then use Ask AI to edit with plain language.',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodyMedium,
                                            textAlign: TextAlign.center,
                                          ),
                                          if (widget.onSwitchToRepoTab != null) ...[
                                            const SizedBox(height: 20),
                                            ForgeSecondaryButton(
                                              label: 'Go to Repo tab',
                                              icon: Icons.folder_open_rounded,
                                              onPressed: widget.onSwitchToRepoTab,
                                            ),
                                          ],
                                        ],
                                      ),
                                    )
                                  : TextField(
                                      controller: _textController,
                                      expands: true,
                                      maxLines: null,
                                      minLines: null,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 14,
                                        height: 1.65,
                                        color: ForgePalette.textPrimary,
                                      ),
                                      decoration:
                                          const InputDecoration.collapsed(
                                            hintText: 'Start editing code',
                                          ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ForgeSecondaryButton(
                        label: 'Open Git flow',
                        icon: Icons.call_split_rounded,
                        onPressed: selectedRepository == null
                            ? null
                            : () => _open(
                                context,
                                GitWorkflowScreen(
                                  controller: widget.controller,
                                ),
                              ),
                        expanded: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save(BuildContext context) async {
    try {
      await widget.controller.saveCurrentFile();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Draft saved.')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _open(BuildContext context, Widget screen) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => screen));
  }
}
