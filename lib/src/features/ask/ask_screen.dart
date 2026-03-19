import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';
import '../workspace/domain/forge_workspace_state.dart';

class AskScreen extends StatefulWidget {
  const AskScreen({
    super.key,
    required this.controller,
    this.onSwitchToEditorTab,
  });

  final ForgeWorkspaceController controller;
  final VoidCallback? onSwitchToEditorTab;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _workflowController = TextEditingController(
    text: 'run-app.yml',
  );
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _commitMessageController = TextEditingController(text: 'chore: update code from prompt');
  final TextEditingController _newBranchController = TextEditingController();
  String? _selectedCommitBranch;
  final ImagePicker _imagePicker = ImagePicker();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final List<ForgePromptMediaAttachment> _pendingMedia = <ForgePromptMediaAttachment>[];
  bool _isWorking = false;
  bool _speechReady = false;
  bool _isListening = false;
  String _speechSeedText = '';
  bool _showHeaderChrome = true;
  String? _lastAutoScrollThreadId;
  int _lastAutoScrollItemCount = -1;

  static const String _newBranchOption = '__new_branch__';

  String _compactError(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return 'Unknown error.';
    }
    var text = raw;
    final stackIndex = text.indexOf('\n#0');
    if (stackIndex > 0) {
      text = text.substring(0, stackIndex).trim();
    }
    if (text.contains('Remote provider error (404)')) {
      return 'Workflow was not found in this repository. Install `run-app.yml` first, then try again.';
    }
    const maxLen = 280;
    if (text.length > maxLen) {
      return '${text.substring(0, maxLen)}...';
    }
    return text;
  }

  @override
  void dispose() {
    _speechToText.cancel();
    _inputController.dispose();
    _workflowController.dispose();
    _commitMessageController.dispose();
    _newBranchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  ForgePromptThread? _currentThread(ForgeWorkspaceState state) {
    final selected = state.selectedPromptThreadId;
    if (selected == null) return null;
    for (final t in state.promptThreads) {
      if (t.id == selected) return t;
    }
    return null;
  }

  String _messageForDisplay(String input) {
    var out = input;
    final stackIndex = out.indexOf('\n#0');
    if (stackIndex > 0) {
      out = out.substring(0, stackIndex).trim();
    }
    return out;
  }

  void _showPromptSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _autoScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }


  String _guessMimeType(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<void> _pickMedia() async {
    if (_isWorking) return;
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // Keep payload under control for callable size limits.
      if (bytes.length > 2 * 1024 * 1024) {
        widget.controller.addPromptAssistantMessage(
          'Selected image is too large. Please choose an image under 2 MB.',
        );
        return;
      }
      final attachment = ForgePromptMediaAttachment(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        fileName: file.name,
        mimeType: _guessMimeType(file.name),
        dataBase64: base64Encode(bytes),
      );
      setState(() {
        _pendingMedia.add(attachment);
      });
    } catch (e) {
      widget.controller.addPromptAssistantMessage('Media attach failed: ${_compactError(e)}');
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_isWorking) return;
    if (_isListening) {
      await _speechToText.stop();
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
      return;
    }

    if (!_speechReady) {
      final available = await _speechToText.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
          });
          _showPromptSnack('Voice note failed: ${error.errorMsg}');
        },
      );
      if (!available) {
        _showPromptSnack('Voice notes are unavailable on this device.');
        return;
      }
      _speechReady = true;
    }

    _speechSeedText = _inputController.text.trim();
    final started = await _speechToText.listen(
      partialResults: true,
      listenMode: stt.ListenMode.confirmation,
      onResult: (result) {
        final spoken = result.recognizedWords.trim();
        final nextText = [
          _speechSeedText,
          if (spoken.isNotEmpty) spoken,
        ].where((item) => item.isNotEmpty).join(_speechSeedText.isEmpty ? '' : ' ');
        _inputController.value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        );
      },
    );
    if (!started) {
      _showPromptSnack('Could not start voice note recording.');
      return;
    }
    if (mounted) {
      setState(() {
        _isListening = true;
      });
    }
  }

  void _removeMedia(String id) {
    setState(() {
      _pendingMedia.removeWhere((m) => m.id == id);
    });
  }

  Future<void> _runAppViaGit() async {
    if (_isWorking) return;
    final workflow = _workflowController.text.trim().isEmpty
        ? 'run-app.yml'
        : _workflowController.text.trim();
    setState(() => _isWorking = true);
    try {
      final logsUrl = await widget.controller.runAppWorkflow(workflowName: workflow);
      final msg = logsUrl == null || logsUrl.isEmpty
          ? 'Workflow dispatched. Open the latest run in your Git provider for logs/artifacts.'
          : 'Workflow dispatched. Logs: $logsUrl';
      widget.controller.addPromptAssistantMessage(msg);
    } catch (e) {
      widget.controller.addPromptAssistantMessage('Run failed: ${_compactError(e)}');
    } finally {
      if (mounted) setState(() => _isWorking = false);
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

  Future<void> _installRunAppWorkflow(ForgeWorkspaceState state) async {
    final selected = state.selectedRepository;
    if (selected == null || _isWorking) return;
    final draft = await _askBranchAndCommit(
      defaultBranch: state.selectedBranch ?? selected.defaultBranch,
    );
    if (draft == null) return;

    setState(() => _isWorking = true);
    try {
      await widget.controller.installRunAppWorkflowViaGit(
        branchName: draft.branchName,
        commitMessage: draft.commitMessage,
      );
      widget.controller.addPromptAssistantMessage(
        'Installed .github/workflows/run-app.yml on ${draft.branchName}. You can now tap Run app via Git to execute and collect logs/screenshots.',
      );
    } catch (e) {
      widget.controller.addPromptAssistantMessage('Install failed: ${_compactError(e)}');
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }


  Future<void> _commitAndPush(ForgeWorkspaceState state) async {
    final repo = state.selectedRepository;
    if (repo == null || _isWorking) {
      return;
    }

    final branch = (_selectedCommitBranch == null || _selectedCommitBranch!.isEmpty)
        ? (state.selectedBranch ?? repo.defaultBranch)
        : (_selectedCommitBranch == _newBranchOption
            ? (_newBranchController.text.trim().isEmpty
                ? (state.selectedBranch ?? repo.defaultBranch)
                : _newBranchController.text.trim())
            : _selectedCommitBranch!);
    final commitMsg = _commitMessageController.text.trim().isEmpty
        ? 'chore: update code from prompt'
        : _commitMessageController.text.trim();

    setState(() => _isWorking = true);
    try {
      await widget.controller.submitGitAction(
        actionType: ForgeGitActionType.commit,
        draft: ForgeGitDraft(
          branchName: branch,
          commitMessage: commitMsg,
          pullRequestTitle: commitMsg,
          pullRequestDescription: 'Committed from Prompt thread',
          mergeMethod: 'merge',
        ),
      );
      widget.controller.addPromptAssistantMessage(
        'Committed and pushed to $branch with message: "$commitMsg".',
      );
    } catch (e) {
      widget.controller.addPromptAssistantMessage(
        'Commit/push failed: ${_compactError(e)}. Make sure a file is open and has changes, then try again.',
      );
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _send(ForgeWorkspaceState state) async {
    final text = _inputController.text.trim();
    final isBusy = state.isPromptLoading || _isWorking;
    if (text.isEmpty || isBusy) return;

    _inputController.clear();
    try {
      final media = List<ForgePromptMediaAttachment>.from(_pendingMedia);
      setState(() {
        _pendingMedia.clear();
      });
      await widget.controller.sendPromptMessage(text, media: media);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      widget.controller.addPromptAssistantMessage('Error: ${_compactError(e)}');
    }
  }

  Future<void> _renameThread(ForgePromptThread thread) async {
    final controller = TextEditingController(text: thread.title);
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename thread'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: const InputDecoration(
            labelText: 'Thread name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (nextTitle == null || nextTitle.trim().isEmpty) return;
    await widget.controller.renamePromptThread(
      threadId: thread.id,
      title: nextTitle,
    );
  }

  Future<void> _openToolsSheet(ForgeWorkspaceState state) async {
    final repo = state.selectedRepository;
    final branches = <String>{
      if (repo?.defaultBranch != null) repo!.defaultBranch,
      ...?repo?.branches,
      if (state.selectedBranch != null) state.selectedBranch!,
    }.where((b) => b.trim().isNotEmpty).toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, sheetSetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Prompt tools', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Danger Mode (max autonomy)'),
                    subtitle: const Text(
                      'AI becomes aggressive and action-oriented. Use with caution.',
                    ),
                    value: state.promptDangerMode,
                    onChanged: (value) => widget.controller.setPromptDangerMode(value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _workflowController,
                    decoration: const InputDecoration(
                      labelText: 'Run workflow file',
                      hintText: 'run-app.yml',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ForgeSecondaryButton(
                        label: _isWorking ? 'Running...' : 'Run app via Git',
                        icon: Icons.play_arrow_rounded,
                        onPressed: repo == null || _isWorking ? null : _runAppViaGit,
                      ),
                      ForgeSecondaryButton(
                        label: _isWorking ? 'Working...' : 'Install run-app.yml',
                        icon: Icons.download_rounded,
                        onPressed: repo == null || _isWorking
                            ? null
                            : () => _installRunAppWorkflow(state),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Commit & push', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: (_selectedCommitBranch == _newBranchOption)
                        ? null
                        : (() {
                            if (_selectedCommitBranch != null &&
                                branches.contains(_selectedCommitBranch)) {
                              return _selectedCommitBranch;
                            }
                            if (branches.isNotEmpty) return branches.first;
                            return null;
                          }()),
                    hint: const Text('Select branch'),
                    items: [
                      ...branches.map(
                        (b) => DropdownMenuItem(value: b, child: Text(b)),
                      ),
                      const DropdownMenuItem(
                        value: _newBranchOption,
                        child: Text('New branch...'),
                      ),
                    ],
                    onChanged: repo == null || _isWorking
                        ? null
                        : (value) {
                            sheetSetState(() {
                              _selectedCommitBranch = value;
                            });
                            setState(() {
                              _selectedCommitBranch = value;
                            });
                          },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Branch',
                    ),
                  ),
                  if (_selectedCommitBranch == _newBranchOption) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _newBranchController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'New branch name',
                        hintText: 'feature/my-change',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commitMessageController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Commit message',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ForgePrimaryButton(
                      label: _isWorking ? 'Committing...' : 'Commit & push',
                      icon: Icons.commit_rounded,
                      onPressed: repo == null || _isWorking
                          ? null
                          : () => _commitAndPush(state),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openScopeSheet(ForgeWorkspaceState state) async {
    final current = _currentThread(state);
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.hub_rounded),
              title: const Text('All projects'),
              onTap: () {
                if (current != null) {
                  unawaited(widget.controller.setPromptThreadRepo(current.id, null));
                }
                Navigator.of(context).pop();
              },
            ),
            if (state.repositories.isEmpty)
              const ListTile(
                enabled: false,
                title: Text('No projects connected'),
              )
            else
              ...state.repositories.map(
                (repo) => ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(repo.name),
                  onTap: () {
                    if (current != null) {
                      unawaited(
                        widget.controller.setPromptThreadRepo(current.id, repo.id),
                      );
                    } else {
                      unawaited(widget.controller.selectRepository(repo));
                    }
                    Navigator.of(context).pop();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openThreadSheet(ForgeWorkspaceState state) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final t in state.promptThreads)
              ListTile(
                leading: Icon(
                  t.id == state.selectedPromptThreadId
                      ? Icons.check_circle_rounded
                      : Icons.chat_bubble_outline_rounded,
                ),
                title: Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  t.repoId == null ? 'All projects' : 'Single project',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.drive_file_rename_outline_rounded),
                  onPressed: () {
                    Navigator.of(context).pop();
                    unawaited(_renameThread(t));
                  },
                ),
                onTap: () {
                  unawaited(widget.controller.selectPromptThread(t.id));
                  Navigator.of(context).pop();
                },
              ),
            ListTile(
              leading: const Icon(Icons.add_comment_rounded),
              title: const Text('New thread'),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(widget.controller.createPromptThread());
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final thread = _currentThread(state);
        final isBusy = state.isPromptLoading || _isWorking;
        final repoForThread = state.repositories.where((r) => r.id == thread?.repoId).isNotEmpty
            ? state.repositories.firstWhere((r) => r.id == thread!.repoId)
            : null;
        final isAllProjects = thread?.repoId == null;
        final repoLabel = isAllProjects ? 'All projects' : (repoForThread?.name ?? 'Pick project');
        final messages = thread?.messages ?? const <ForgePromptMessage>[];
        final listItemCount = messages.length + (state.isPromptLoading ? 1 : 0);
        final showPromptProgress =
            state.isPromptLoading && state.promptStatusThreadId == thread?.id;
        if (_lastAutoScrollThreadId != thread?.id ||
            _lastAutoScrollItemCount != listItemCount) {
          _lastAutoScrollThreadId = thread?.id;
          _lastAutoScrollItemCount = listItemCount;
          _autoScrollToLatest();
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, _showHeaderChrome ? 12 : 4, 16, 8),
                  child: AnimatedCrossFade(
                    duration: const Duration(milliseconds: 180),
                    crossFadeState: _showHeaderChrome
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                thread?.title ?? 'Prompt',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () => _openScopeSheet(state),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.folder_rounded,
                                      size: 16,
                                      color: ForgePalette.glowAccent,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        repoLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: ForgePalette.textSecondary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 18,
                                      color: ForgePalette.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hide header',
                          onPressed: () {
                            setState(() {
                              _showHeaderChrome = false;
                            });
                          },
                          icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                        IconButton(
                          tooltip: 'Threads',
                          onPressed: () => _openThreadSheet(state),
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                        ),
                        IconButton(
                          tooltip: 'Prompt tools',
                          onPressed: () => _openToolsSheet(state),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ],
                    ),
                    secondChild: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Show header',
                            onPressed: () {
                              setState(() {
                                _showHeaderChrome = true;
                              });
                            },
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                          IconButton(
                            tooltip: 'Threads',
                            onPressed: () => _openThreadSheet(state),
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                          ),
                          IconButton(
                            tooltip: 'Prompt tools',
                            onPressed: () => _openToolsSheet(state),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Divider(height: 1),
                      Expanded(
                        child: messages.isEmpty && !state.isPromptLoading
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(28),
                                  child: Text(
                                    'Start vibecoding: describe what you want to build or change.',
                                    style: Theme.of(context).textTheme.bodyMedium
                                        ?.copyWith(color: ForgePalette.textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                itemCount: messages.length + (state.isPromptLoading ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == messages.length) {
                                    if (!showPromptProgress) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(context).size.width * 0.88,
                                          ),
                                          child: ForgePanel(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        state.promptStatusText ?? 'Thinking...',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .titleSmall,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (state.promptStatusSteps.isNotEmpty) ...[
                                                  const SizedBox(height: 10),
                                                  ...state.promptStatusSteps
                                                      .take(5)
                                                      .map(
                                                        (step) => Padding(
                                                          padding: const EdgeInsets.only(
                                                            bottom: 6,
                                                          ),
                                                          child: Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment.start,
                                                            children: [
                                                              const Padding(
                                                                padding:
                                                                    EdgeInsets.only(top: 6),
                                                                child: Icon(
                                                                  Icons.circle,
                                                                  size: 6,
                                                                  color: ForgePalette
                                                                      .textSecondary,
                                                                ),
                                                              ),
                                                              const SizedBox(width: 8),
                                                              Expanded(
                                                                child: Text(
                                                                  step,
                                                                  style: Theme.of(context)
                                                                      .textTheme
                                                                      .bodySmall
                                                                      ?.copyWith(
                                                                        color: ForgePalette
                                                                            .textSecondary,
                                                                      ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final msg = messages[index];
                                  final isUser = msg.role == 'user';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Align(
                                      alignment: isUser
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: MediaQuery.of(context).size.width * 0.85,
                                        ),
                                        child: ForgePanel(
                                          backgroundColor: isUser
                                              ? ForgePalette.glowAccent.withValues(alpha: 0.15)
                                              : null,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          child: SelectableText(
                                            _messageForDisplay(msg.text),
                                            style: Theme.of(context).textTheme.bodyMedium,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                          decoration: BoxDecoration(
                            color: ForgePalette.surfaceElevated.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: ForgePalette.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_pendingMedia.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: _pendingMedia
                                          .map(
                                            (m) => Padding(
                                              padding: const EdgeInsets.only(right: 8),
                                              child: InputChip(
                                                avatar: const Icon(Icons.image_rounded, size: 18),
                                                label: Text(m.fileName),
                                                onDeleted: () => _removeMedia(m.id),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  IconButton(
                                    tooltip: _isListening ? 'Stop voice note' : 'Voice note',
                                    onPressed: isBusy ? null : _toggleVoiceInput,
                                    icon: Icon(
                                      _isListening
                                          ? Icons.mic_rounded
                                          : Icons.mic_none_rounded,
                                      color: _isListening ? ForgePalette.glowAccent : null,
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: _inputController,
                                      minLines: 1,
                                      maxLines: 4,
                                      decoration: const InputDecoration(
                                        hintText: 'Message ForgeAI...',
                                        border: InputBorder.none,
                                        isCollapsed: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 10,
                                        ),
                                      ),
                                      onSubmitted: (_) => _send(state),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    tooltip: 'Add media',
                                    onPressed: isBusy ? null : _pickMedia,
                                    icon: const Icon(Icons.attach_file_rounded),
                                  ),
                                  const SizedBox(width: 2),
                                  IconButton.filled(
                                    tooltip: state.isPromptLoading ? 'Stop' : 'Send',
                                    onPressed: state.isPromptLoading
                                        ? widget.controller.cancelPromptRun
                                        : (isBusy ? null : () => _send(state)),
                                    icon: Icon(
                                      state.isPromptLoading
                                          ? Icons.stop_rounded
                                          : (isBusy
                                              ? Icons.hourglass_top_rounded
                                              : Icons.send_rounded),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
