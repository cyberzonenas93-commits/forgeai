import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../ai/ai_task_screen.dart';
import '../diff/diff_review_screen.dart';
import '../git/git_workflow_screen.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';
import '../workspace/domain/forge_workspace_state.dart';
import 'widgets/forge_file_explorer.dart';

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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final TextEditingController _textController = TextEditingController();
  String? _syncedPath;
  String? _focusedFolderPath;
  bool _isApplyingExternalText = false;

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

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

  Future<void> _openFileFromExplorer(ForgeFileNode file) async {
    final doc = widget.controller.value.currentDocument;
    if (doc != null && doc.hasUnsavedChanges) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: Text(
            'Save edits to ${doc.path.split('/').last} before opening another file?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == 'cancel') {
        return;
      }
      if (choice == 'save') {
        try {
          await widget.controller.saveCurrentFile();
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not save; still on the same file.'),
              ),
            );
          }
          return;
        }
      }
    }
    try {
      await widget.controller.openFile(file);
      if (mounted) {
        _scaffoldKey.currentState?.closeDrawer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open file: $e')));
      }
    }
  }

  void _focusFolderInExplorer(String folderPath) {
    final normalized = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    setState(() {
      _focusedFolderPath = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _focusedFolderPath = normalized;
      });
    });
    _scaffoldKey.currentState?.openDrawer();
  }

  Widget _buildPathBreadcrumb(BuildContext context, String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return Text(
        path,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: ForgePalette.textSecondary),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '/',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ForgePalette.textMuted,
                  ),
                ),
              ),
            InkWell(
              onTap: i == parts.length - 1
                  ? null
                  : () {
                      final folderPath = parts.take(i + 1).join('/');
                      _focusFolderInExplorer(folderPath);
                    },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Text(
                  parts[i],
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: i == parts.length - 1
                        ? ForgePalette.textSecondary
                        : ForgePalette.glowAccent,
                    decoration: i == parts.length - 1
                        ? TextDecoration.none
                        : TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExplorerContents(
    BuildContext context, {
    required ForgeWorkspaceState state,
    required ForgeFileDocument? document,
    required bool showCloseButton,
  }) {
    final selectedRepository = state.selectedRepository;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Files',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (selectedRepository != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        selectedRepository.repoLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (showCloseButton)
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => _scaffoldKey.currentState?.closeDrawer(),
                  icon: const Icon(Icons.close_rounded),
                )
              else if (selectedRepository != null)
                ForgePill(
                  label:
                      state.selectedBranch ?? selectedRepository.defaultBranch,
                  icon: Icons.commit_rounded,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ForgeFileExplorer(
            roots: state.files,
            selectedPath: document?.path,
            focusedFolderPath: _focusedFolderPath,
            onFileSelected: _openFileFromExplorer,
            onCreateFileRequested: _createFile,
            onCreateFolderRequested: _createFolder,
            onRenameRequested: _renameNode,
            onDeleteRequested: _deleteNode,
          ),
        ),
      ],
    );
  }

  Future<String?> _askForPath({
    required String title,
    required String hint,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isEmpty == true ? null : result?.trim();
  }

  Future<void> _createFile(String? parentFolderPath) async {
    final relative = await _askForPath(
      title: 'Create file',
      hint: parentFolderPath == null
          ? 'e.g. lib/src/new_file.dart'
          : 'e.g. ${parentFolderPath}new_file.dart',
    );
    if (!mounted || relative == null) {
      return;
    }
    final fullPath = parentFolderPath == null
        ? relative
        : '${parentFolderPath.endsWith('/') ? parentFolderPath : '$parentFolderPath/'}$relative';
    try {
      await widget.controller.createFile(path: fullPath);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create file: $error')));
    }
  }

  Future<void> _createFolder(String? parentFolderPath) async {
    final relative = await _askForPath(
      title: 'Create folder',
      hint: parentFolderPath == null
          ? 'e.g. lib/src/new_folder'
          : 'e.g. ${parentFolderPath}new_folder',
    );
    if (!mounted || relative == null) {
      return;
    }
    final fullPath = parentFolderPath == null
        ? relative
        : '${parentFolderPath.endsWith('/') ? parentFolderPath : '$parentFolderPath/'}$relative';
    try {
      await widget.controller.createFolder(path: fullPath);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create folder: $error')),
      );
    }
  }

  Future<void> _renameNode(ForgeFileNode node) async {
    final next = await _askForPath(
      title: node.isFolder ? 'Rename folder' : 'Rename file',
      hint: 'New name or path',
      initialValue: node.isFolder
          ? node.path.split('/').where((part) => part.isNotEmpty).last
          : node.name,
    );
    if (!mounted || next == null) {
      return;
    }
    try {
      await widget.controller.renameNode(node: node, newNameOrPath: next);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not rename: $error')));
    }
  }

  Future<void> _deleteNode(ForgeFileNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(node.isFolder ? 'Delete folder?' : 'Delete file?'),
        content: Text(
          node.isFolder
              ? 'This removes the folder and all files inside:\n${node.path}'
              : 'This removes ${node.path}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.controller.deleteNode(node);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete: $error')));
    }
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
        final balance = state.wallet.balance.toInt();
        final usePersistentExplorer =
            MediaQuery.sizeOf(context).width >= 1140 &&
            selectedRepository != null;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.transparent,
          drawer: usePersistentExplorer
              ? null
              : Drawer(
                  backgroundColor: ForgePalette.surfaceElevated,
                  child: SafeArea(
                    child: _buildExplorerContents(
                      context,
                      state: state,
                      document: document,
                      showCloseButton: true,
                    ),
                  ),
                ),
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _dismissKeyboard,
            child: ForgeScreen(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final branchLabel =
                      state.selectedBranch ??
                      selectedRepository?.defaultBranch ??
                      'main';

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.errorMessage != null &&
                          state.errorMessage!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
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
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ForgePanel(
                        highlight: true,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  tooltip: 'Browse files',
                                  onPressed:
                                      selectedRepository == null ||
                                          usePersistentExplorer
                                      ? null
                                      : () => _scaffoldKey.currentState
                                            ?.openDrawer(),
                                  icon: const Icon(Icons.menu_open_rounded),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Code',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      if (document?.path != null)
                                        _buildPathBreadcrumb(
                                          context,
                                          document!.path,
                                        )
                                      else
                                        Text(
                                          'Open a file from Files or Repo settings.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color:
                                                    ForgePalette.textSecondary,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ForgePill(
                                  label: '$lineCount lines',
                                  icon: Icons.format_list_numbered_rounded,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ForgePill(
                                  label: '$balance tokens',
                                  icon: Icons.token_rounded,
                                ),
                                ForgePill(
                                  label: branchLabel,
                                  icon: Icons.commit_rounded,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ForgePrimaryButton(
                                  label: state.isSavingFile
                                      ? 'Saving...'
                                      : 'Save',
                                  icon: Icons.save_rounded,
                                  onPressed:
                                      document == null || state.isSavingFile
                                      ? null
                                      : () => _save(context),
                                ),
                                ForgeSecondaryButton(
                                  label: 'AI edit (uses tokens)',
                                  icon: Icons.auto_awesome_rounded,
                                  onPressed: document == null
                                      ? null
                                      : () => _open(
                                          context,
                                          AiTaskScreen(
                                            controller: widget.controller,
                                          ),
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
                                ForgeSecondaryButton(
                                  label: 'Hide keyboard',
                                  icon: Icons.keyboard_hide_rounded,
                                  onPressed: _dismissKeyboard,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (usePersistentExplorer) ...[
                              SizedBox(
                                width: 320,
                                child: ForgePanel(
                                  padding: EdgeInsets.zero,
                                  child: _buildExplorerContents(
                                    context,
                                    state: state,
                                    document: document,
                                    showCloseButton: false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: ForgePanel(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        12,
                                        14,
                                        10,
                                      ),
                                      child: ForgeAiIndicator(
                                        label: document == null
                                            ? 'Select a file to begin'
                                            : (state.currentChangeRequest ==
                                                      null
                                                  ? 'Describe your change in plain language, then use Ask AI to edit'
                                                  : 'AI diff ready for review'),
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
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        usePersistentExplorer
                                                            ? 'Choose a file from the explorer to start editing.'
                                                            : 'No file open. Tap the menu icon to browse files, or pick one from the Repo tab.',
                                                        style: Theme.of(
                                                          context,
                                                        ).textTheme.bodyMedium,
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                      if (selectedRepository !=
                                                              null &&
                                                          !usePersistentExplorer) ...[
                                                        const SizedBox(
                                                          height: 20,
                                                        ),
                                                        ForgeSecondaryButton(
                                                          label:
                                                              'Open file list',
                                                          icon: Icons
                                                              .folder_open_rounded,
                                                          onPressed: () =>
                                                              _scaffoldKey
                                                                  .currentState
                                                                  ?.openDrawer(),
                                                        ),
                                                      ],
                                                      if (widget
                                                              .onSwitchToRepoTab !=
                                                          null) ...[
                                                        const SizedBox(
                                                          height: 12,
                                                        ),
                                                        ForgeSecondaryButton(
                                                          label:
                                                              'Repo settings',
                                                          icon: Icons
                                                              .tune_rounded,
                                                          onPressed: widget
                                                              .onSwitchToRepoTab,
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
                                                  style:
                                                      GoogleFonts.jetBrainsMono(
                                                        fontSize: 14,
                                                        height: 1.65,
                                                        color: ForgePalette
                                                            .textPrimary,
                                                      ),
                                                  decoration:
                                                      const InputDecoration.collapsed(
                                                        hintText:
                                                            'Start editing code',
                                                      ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ForgeSecondaryButton(
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
                    ],
                  );
                },
              ),
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
