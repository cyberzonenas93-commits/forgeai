import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/branding/app_branding.dart';
import '../../core/theme/forge_palette.dart';
import '../../shared/widgets/forge_widgets.dart';
import 'prompt_git_intents.dart';
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
  final TextEditingController _deployWorkflowController = TextEditingController(
    text: 'deploy-functions.yml',
  );
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _commitMessageController = TextEditingController(
    text: 'chore: update code from prompt',
  );
  final TextEditingController _newBranchController = TextEditingController();
  String? _selectedCommitBranch;
  final ImagePicker _imagePicker = ImagePicker();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final List<ForgePromptMediaAttachment> _pendingMedia =
      <ForgePromptMediaAttachment>[];
  bool _isWorking = false;
  bool _speechReady = false;
  bool _isListening = false;
  String _speechSeedText = '';
  bool _showHeaderChrome = true;

  /// Bumps when thread / messages / loading change — keep view pinned to latest
  /// (WhatsApp-style [ListView.reverse] anchor at composer).
  String? _lastChatScrollSignature;
  bool _showDeployChip = false;

  static const String _newBranchOption = '__new_branch__';

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

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
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    final text = _inputController.text.trim().toLowerCase();
    final show = text.contains('deploy') && text.contains('function');
    if (show != _showDeployChip) {
      setState(() => _showDeployChip = show);
    }
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _speechToText.cancel();
    _inputController.dispose();
    _workflowController.dispose();
    _deployWorkflowController.dispose();
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pin scroll to the newest messages (offset 0 with [ListView.reverse]).
  void _scrollTranscriptToEnd() {
    void jump() {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      WidgetsBinding.instance.addPostFrameCallback((_) => jump());
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
      widget.controller.addPromptAssistantMessage(
        'Media attach failed: ${_compactError(e)}',
      );
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
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (result) {
        final spoken = result.recognizedWords.trim();
        final nextText = [_speechSeedText, if (spoken.isNotEmpty) spoken]
            .where((item) => item.isNotEmpty)
            .join(_speechSeedText.isEmpty ? '' : ' ');
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
      final logsUrl = await widget.controller.runAppWorkflow(
        workflowName: workflow,
      );
      final msg = logsUrl == null || logsUrl.isEmpty
          ? '**Run app via Git** — workflow `$workflow` dispatched. Open the latest GitHub Actions run for logs and artifacts. If the workflow is missing, say **install run app** or use Prompt tools → Install run-app.yml.'
          : '**Run app via Git** — workflow dispatched. Logs: $logsUrl';
      widget.controller.addPromptAssistantMessage(msg);
    } catch (e) {
      widget.controller.addPromptAssistantMessage(
        'Run failed: ${_compactError(e)}',
      );
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _runDeployFunctionsViaGit() async {
    if (_isWorking) return;
    final workflow = _deployWorkflowController.text.trim().isEmpty
        ? 'deploy-functions.yml'
        : _deployWorkflowController.text.trim();
    setState(() => _isWorking = true);
    try {
      final logsUrl = await widget.controller.runDeployFunctionsWorkflow(
        workflowName: workflow,
      );
      final msg = logsUrl == null || logsUrl.isEmpty
          ? '**Deploy functions** — workflow `$workflow` dispatched. Ensure GitHub repo **Actions** secrets include either `FIREBASE_TOKEN` (easy: `firebase login:ci`) or `FIREBASE_SERVICE_ACCOUNT` (recommended). If the file is missing, say **install deploy workflow** or use Prompt tools.'
          : '**Deploy functions** — workflow dispatched. Logs: $logsUrl';
      widget.controller.addPromptAssistantMessage(msg);
    } catch (e) {
      widget.controller.addPromptAssistantMessage(
        'Deploy failed: ${_compactError(e)}',
      );
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
      widget.controller.addPromptAssistantMessage(
        'Install failed: ${_compactError(e)}',
      );
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _installDeployFunctionsWorkflow(
    ForgeWorkspaceState state,
  ) async {
    final selected = state.selectedRepository;
    if (selected == null || _isWorking) return;
    final draft = await _askBranchAndCommit(
      defaultBranch: state.selectedBranch ?? selected.defaultBranch,
      defaultMessage: 'chore: add deploy-functions workflow',
    );
    if (draft == null) return;

    setState(() => _isWorking = true);
    try {
      await widget.controller.installDeployFunctionsWorkflowViaGit(
        branchName: draft.branchName,
        commitMessage: draft.commitMessage,
      );
      widget.controller.addPromptAssistantMessage(
        'Installed `.github/workflows/deploy-functions.yml` on `${draft.branchName}`. '
        'Add GitHub **Actions** secret **`FIREBASE_TOKEN`** (easy: `firebase login:ci`) '
        'or **`FIREBASE_SERVICE_ACCOUNT`** (recommended), then say **deploy functions** to run it.',
      );
    } catch (e) {
      widget.controller.addPromptAssistantMessage(
        'Install failed: ${_compactError(e)}',
      );
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _commitAndPush(ForgeWorkspaceState state) async {
    final repo = state.selectedRepository;
    if (repo == null || _isWorking) {
      return;
    }

    final branch =
        (_selectedCommitBranch == null || _selectedCommitBranch!.isEmpty)
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

    final quick = matchPromptGitQuickCommand(text);
    if (quick != null) {
      _inputController.clear();
      setState(() => _pendingMedia.clear());
      await _handlePromptGitQuickCommand(quick, text, state);
      return;
    }

    _inputController.clear();
    try {
      final media = List<ForgePromptMediaAttachment>.from(_pendingMedia);
      setState(() {
        _pendingMedia.clear();
      });
      await widget.controller.sendPromptMessage(text, media: media);
      if (!mounted) return;
      _scrollTranscriptToEnd();
    } catch (e) {
      widget.controller.addPromptAssistantMessage('Error: ${_compactError(e)}');
    }
  }

  Future<void> _handlePromptGitQuickCommand(
    PromptGitQuickCommand cmd,
    String originalText,
    ForgeWorkspaceState state,
  ) async {
    widget.controller.ensurePromptThreadReady();
    widget.controller.addPromptUserMessage(originalText);

    final repo = state.selectedRepository;
    if (repo == null) {
      widget.controller.addPromptAssistantMessage(
        'Pick a repository first: open the **Repo** tab and select a project, or set this thread’s scope to a repo.',
      );
      _scrollTranscriptToEnd();
      return;
    }

    switch (cmd) {
      case PromptGitQuickCommand.runAppViaGit:
        await _runAppViaGit();
      case PromptGitQuickCommand.deployFunctionsViaGit:
        await _runDeployFunctionsViaGit();
      case PromptGitQuickCommand.installRunAppWorkflow:
        await _installRunAppWorkflow(state);
      case PromptGitQuickCommand.installDeployWorkflow:
        await _installDeployFunctionsWorkflow(state);
    }
    if (mounted) _scrollTranscriptToEnd();
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

  Future<void> _clearCurrentThread(ForgeWorkspaceState state) async {
    final thread = _currentThread(state);
    if (thread == null || thread.messages.isEmpty || _isWorking) return;
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text(
          'This removes all messages in the current thread.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (shouldClear != true) return;
    await widget.controller.clearPromptThreadMessages(threadId: thread.id);
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
                  Text(
                    'Prompt tools',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Autonomous agent mode'),
                    subtitle: const Text(
                      'AI takes a stronger coding-agent posture (acts first, asks fewer clarifying questions, and proposes concrete file-level changes).',
                    ),
                    value: state.promptDangerMode,
                    onChanged: (value) =>
                        widget.controller.setPromptDangerMode(value),
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
                        onPressed: repo == null || _isWorking
                            ? null
                            : _runAppViaGit,
                      ),
                      ForgeSecondaryButton(
                        label: _isWorking
                            ? 'Working...'
                            : 'Install run-app.yml',
                        icon: Icons.download_rounded,
                        onPressed: repo == null || _isWorking
                            ? null
                            : () => _installRunAppWorkflow(state),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _deployWorkflowController,
                    decoration: const InputDecoration(
                      labelText: 'Deploy workflow file',
                      hintText: 'deploy-functions.yml',
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
                        label: _isWorking
                            ? 'Deploying...'
                            : 'Deploy functions via Git',
                        icon: Icons.cloud_upload_rounded,
                        onPressed: repo == null || _isWorking
                            ? null
                            : _runDeployFunctionsViaGit,
                      ),
                      ForgeSecondaryButton(
                        label: _isWorking
                            ? 'Working...'
                            : 'Install deploy-functions.yml',
                        icon: Icons.download_rounded,
                        onPressed: repo == null || _isWorking
                            ? null
                            : () => _installDeployFunctionsWorkflow(state),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Commit & push',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
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
                  unawaited(
                    widget.controller.setPromptThreadRepo(current.id, null),
                  );
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
                        widget.controller.setPromptThreadRepo(
                          current.id,
                          repo.id,
                        ),
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
                title: Text(t.title),
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
        final repoForThread =
            state.repositories.where((r) => r.id == thread?.repoId).isNotEmpty
            ? state.repositories.firstWhere((r) => r.id == thread!.repoId)
            : null;
        final isAllProjects = thread?.repoId == null;
        final repoLabel = isAllProjects
            ? 'All projects'
            : (repoForThread?.name ?? 'Pick project');
        final messages = thread?.messages ?? const <ForgePromptMessage>[];
        final showPromptProgress =
            state.isPromptLoading && state.promptStatusThreadId == thread?.id;
        final lastMsgId = messages.isEmpty ? '' : messages.last.id;
        final scrollSignature =
            '${thread?.id ?? ''}|len:${messages.length}|load:${state.isPromptLoading}|last:$lastMsgId';
        if (_lastChatScrollSignature != scrollSignature) {
          _lastChatScrollSignature = scrollSignature;
          _scrollTranscriptToEnd();
        }
        final tokenBalance = state.wallet.balance.toInt();

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _dismissKeyboard,
            child: ForgeScreen(
              // Tighter bottom inset so the composer sits lower (closer to the tab bar).
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      _showHeaderChrome ? 12 : 4,
                      16,
                      8,
                    ),
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
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color:
                                                    ForgePalette.textSecondary,
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
                                const SizedBox(height: 4),
                                Text(
                                  'Each reply uses tokens ($tokenBalance available). Use Code → AI edit for file changes.',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: ForgePalette.textSecondary,
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
                            tooltip: 'Clear chat',
                            onPressed: messages.isEmpty || isBusy
                                ? null
                                : () => _clearCurrentThread(state),
                            icon: const Icon(Icons.delete_sweep_rounded),
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
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Threads',
                              onPressed: () => _openThreadSheet(state),
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Clear chat',
                              onPressed: messages.isEmpty || isBusy
                                  ? null
                                  : () => _clearCurrentThread(state),
                              icon: const Icon(Icons.delete_sweep_rounded),
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: ForgePalette.textSecondary,
                                          ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollController,
                                  // Newest rows sit next to the composer (WhatsApp-style).
                                  reverse: true,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    12,
                                  ),
                                  itemCount:
                                      messages.length +
                                      (showPromptProgress ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (showPromptProgress && index == 0) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.88,
                                            ),
                                            child: ForgePanel(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 12,
                                                  ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Text(
                                                          state.promptStatusText ??
                                                              'Thinking...',
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleSmall,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (state
                                                      .promptStatusSteps
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 10),
                                                    ...state.promptStatusSteps
                                                        .take(5)
                                                        .map(
                                                          (step) => Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  bottom: 6,
                                                                ),
                                                            child: Row(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                const Padding(
                                                                  padding:
                                                                      EdgeInsets.only(
                                                                        top: 6,
                                                                      ),
                                                                  child: Icon(
                                                                    Icons
                                                                        .circle,
                                                                    size: 6,
                                                                    color: ForgePalette
                                                                        .textSecondary,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 8,
                                                                ),
                                                                Expanded(
                                                                  child: Text(
                                                                    step,
                                                                    style: Theme.of(context)
                                                                        .textTheme
                                                                        .bodySmall
                                                                        ?.copyWith(
                                                                          color:
                                                                              ForgePalette.textSecondary,
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
                                    final msgIndex = showPromptProgress
                                        ? index - 1
                                        : index;
                                    final msg =
                                        messages[messages.length -
                                            1 -
                                            msgIndex];
                                    final isUser = msg.role == 'user';
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Align(
                                        alignment: isUser
                                            ? Alignment.centerRight
                                            : Alignment.centerLeft,
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.85,
                                          ),
                                          child: ForgePanel(
                                            backgroundColor: isUser
                                                ? ForgePalette.glowAccent
                                                      .withValues(alpha: 0.15)
                                                : null,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            child: SelectableText(
                                              _messageForDisplay(msg.text),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
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
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
                            decoration: BoxDecoration(
                              color: ForgePalette.surfaceElevated.withValues(
                                alpha: 0.55,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: ForgePalette.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_showDeployChip &&
                                    state.selectedRepository != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: ActionChip(
                                      avatar: const Icon(
                                        Icons.rocket_launch_rounded,
                                        size: 18,
                                        color: ForgePalette.glowAccent,
                                      ),
                                      label: const Text(
                                        'Deploy functions (GitHub)',
                                      ),
                                      onPressed: isBusy
                                          ? null
                                          : () {
                                              widget.controller
                                                  .ensurePromptThreadReady();
                                              widget.controller
                                                  .addPromptUserMessage(
                                                    'Deploy functions',
                                                  );
                                              unawaited(
                                                _runDeployFunctionsViaGit(),
                                              );
                                            },
                                    ),
                                  ),
                                if (_pendingMedia.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: _pendingMedia
                                            .map(
                                              (m) => Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: InputChip(
                                                  avatar: const Icon(
                                                    Icons.image_rounded,
                                                    size: 18,
                                                  ),
                                                  label: Text(m.fileName),
                                                  onDeleted: () =>
                                                      _removeMedia(m.id),
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
                                      tooltip: _isListening
                                          ? 'Stop voice note'
                                          : 'Voice note',
                                      onPressed: isBusy
                                          ? null
                                          : _toggleVoiceInput,
                                      icon: Icon(
                                        _isListening
                                            ? Icons.mic_rounded
                                            : Icons.mic_none_rounded,
                                        color: _isListening
                                            ? ForgePalette.glowAccent
                                            : null,
                                      ),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: _inputController,
                                        minLines: 1,
                                        maxLines: 4,
                                        decoration: const InputDecoration(
                                          hintText:
                                              'Message $kAppDisplayName...',
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
                                      icon: const Icon(
                                        Icons.attach_file_rounded,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Hide keyboard',
                                      onPressed: _dismissKeyboard,
                                      icon: const Icon(
                                        Icons.keyboard_hide_rounded,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    IconButton.filled(
                                      tooltip: state.isPromptLoading
                                          ? 'Stop'
                                          : 'Send',
                                      onPressed: state.isPromptLoading
                                          ? widget.controller.cancelPromptRun
                                          : (isBusy
                                                ? null
                                                : () => _send(state)),
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
          ),
        );
      },
    );
  }
}
