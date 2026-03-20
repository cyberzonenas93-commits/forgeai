import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_agent_entities.dart';
import '../workspace/domain/forge_workspace_state.dart';
import 'widgets/stream_log_widget.dart';
import 'widgets/task_status_chip.dart';

/// A simplified chat-style entry point that mirrors the Claude Code / terminal
/// UX:  type a prompt → hit Send → agent runs (optionally auto-approved).
///
/// Conversation thread shows:
///   • User message bubble (the prompt)
///   • Live stream log (stdout/stderr from commands running on backend)
///   • Final result card (completed / failed)
///
/// [onOpenTaskQueue] — opens the full task-queue / AgentModeScreen view.
/// [onSwitchToEditorTab] — navigates to the code editor tab (e.g. after a diff).
class ChatPromptScreen extends StatefulWidget {
  const ChatPromptScreen({
    super.key,
    required this.controller,
    this.onOpenTaskQueue,
    this.onSwitchToEditorTab,
  });

  final ForgeWorkspaceController controller;

  /// Called when the user taps the "Task queue" icon in the app bar.
  /// Typically pushes [AgentModeScreen] as a full-screen route.
  final VoidCallback? onOpenTaskQueue;

  /// Called from a result card to jump straight to the diff/editor tab.
  final VoidCallback? onSwitchToEditorTab;

  @override
  State<ChatPromptScreen> createState() => _ChatPromptScreenState();
}

class _ChatPromptScreenState extends State<ChatPromptScreen> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();

  // Local list of submitted prompts so we can show the user bubble immediately.
  final List<_ChatEntry> _entries = [];
  bool _isSubmitting = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _submit() async {
    final prompt = _text.text.trim();
    if (prompt.isEmpty || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _entries.add(_ChatEntry.prompt(prompt));
    });
    _text.clear();
    _scrollToBottom();

    try {
      final taskId = await widget.controller.enqueueAgentTask(prompt: prompt);
      setState(() {
        _entries.last = _entries.last.withTaskId(taskId);
      });
      _scrollToBottom();
    } catch (error) {
      setState(() {
        _entries.last = _entries.last.withError(forgeUserFriendlyMessage(error));
      });
    } finally {
      setState(() => _isSubmitting = false);
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ForgeWorkspaceState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final selectedRepo = state.selectedRepository;
        final trustLevel = state.agentTrustLevel;
        final ownerId = widget.controller.currentOwnerId;

        return Scaffold(
          backgroundColor: ForgePalette.surface,
          appBar: AppBar(
            backgroundColor: ForgePalette.surface,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Agent Chat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                if (selectedRepo != null)
                  Text(
                    selectedRepo.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: ForgePalette.textSecondary,
                    ),
                  ),
              ],
            ),
            actions: [
              // Task queue button — opens the full AgentModeScreen.
              if (widget.onOpenTaskQueue != null)
                IconButton(
                  icon: const Icon(Icons.format_list_numbered_rounded),
                  tooltip: 'Task queue',
                  onPressed: widget.onOpenTaskQueue,
                ),
              // Trust level indicator / toggle button.
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PopupMenuButton<AgentTrustLevel>(
                  initialValue: trustLevel,
                  onSelected: widget.controller.setAgentTrustLevel,
                  tooltip: 'Execution mode',
                  child: Chip(
                    avatar: Icon(
                      trustLevel == AgentTrustLevel.supervised
                          ? Icons.supervised_user_circle_rounded
                          : trustLevel == AgentTrustLevel.autoApproveOnSuccess
                              ? Icons.auto_mode_rounded
                              : Icons.rocket_launch_rounded,
                      size: 14,
                      color: trustLevel == AgentTrustLevel.supervised
                          ? ForgePalette.textSecondary
                          : ForgePalette.success,
                    ),
                    label: Text(
                      trustLevel.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                    side: BorderSide(
                      color: trustLevel == AgentTrustLevel.supervised
                          ? ForgePalette.textMuted
                          : ForgePalette.success,
                    ),
                  ),
                  itemBuilder: (_) => AgentTrustLevel.values
                      .map(
                        (level) => PopupMenuItem(
                          value: level,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                level.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                level.description,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: ForgePalette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // ── Conversation history ──────────────────────────────────
              Expanded(
                child: _entries.isEmpty
                    ? _EmptyState(repoName: selectedRepo?.name)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          return _ChatEntryCard(
                            entry: entry,
                            ownerId: ownerId,
                            allTasks: state.agentTasks,
                            onSwitchToEditorTab: widget.onSwitchToEditorTab,
                          );
                        },
                      ),
              ),
              // ── Prompt input ─────────────────────────────────────────
              _ChatInput(
                controller: _text,
                focusNode: _focus,
                isSubmitting: _isSubmitting,
                hasSelection: selectedRepo != null,
                onSubmit: _submit,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Data model ──────────────────────────────────────────────────────────────

class _ChatEntry {
  const _ChatEntry({
    required this.prompt,
    this.taskId,
    this.errorMessage,
  });

  factory _ChatEntry.prompt(String prompt) =>
      _ChatEntry(prompt: prompt);

  final String prompt;
  final String? taskId;
  final String? errorMessage;

  _ChatEntry withTaskId(String taskId) =>
      _ChatEntry(prompt: prompt, taskId: taskId);

  _ChatEntry withError(String message) =>
      _ChatEntry(prompt: prompt, errorMessage: message);
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.repoName});
  final String? repoName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal_rounded,
              size: 56,
              color: ForgePalette.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              repoName != null
                  ? 'Ready to work on $repoName'
                  : 'Select a repository to get started',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Type a task below and the agent will plan, diff, validate, and (optionally) commit without stopping.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ForgePalette.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatEntryCard extends StatelessWidget {
  const _ChatEntryCard({
    required this.entry,
    required this.ownerId,
    required this.allTasks,
    this.onSwitchToEditorTab,
  });

  final _ChatEntry entry;
  final String? ownerId;
  final List<ForgeAgentTask> allTasks;
  final VoidCallback? onSwitchToEditorTab;

  @override
  Widget build(BuildContext context) {
    final task = entry.taskId != null
        ? allTasks.where((t) => t.id == entry.taskId).firstOrNull
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User message bubble.
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: ForgePalette.primaryAccent.withValues(alpha: 0.18),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(
                  color: ForgePalette.primaryAccent.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                entry.prompt,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Error state.
          if (entry.errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ForgePalette.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ForgePalette.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 16, color: ForgePalette.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.errorMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        color: ForgePalette.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Task status + stream log.
          if (task != null) ...[
            Row(
              children: [
                Icon(
                  Icons.smart_toy_rounded,
                  size: 14,
                  color: ForgePalette.primaryAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  task.currentStep,
                  style: TextStyle(
                    fontSize: 12,
                    color: ForgePalette.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                TaskStatusChip(task: task),
              ],
            ),
            const SizedBox(height: 8),
            if (task.isActive && ownerId != null)
              StreamLogWidget(ownerId: ownerId!, taskId: task.id),
            if (task.isFinal)
              _TerminalResultCard(
                task: task,
                onViewDiff: task.sessionId != null ? onSwitchToEditorTab : null,
              ),
          ] else if (entry.taskId != null && entry.errorMessage == null) ...[
            // Task enqueued but not yet in the local list.
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: ForgePalette.primaryAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Starting…',
                  style: TextStyle(
                    fontSize: 12,
                    color: ForgePalette.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TerminalResultCard extends StatelessWidget {
  const _TerminalResultCard({
    required this.task,
    this.onViewDiff,
  });

  final ForgeAgentTask task;

  /// If non-null, shows a "View diff" action button.
  final VoidCallback? onViewDiff;

  @override
  Widget build(BuildContext context) {
    final isSuccess = task.status == ForgeAgentTaskStatus.completed;
    final color = isSuccess ? ForgePalette.success : ForgePalette.error;
    final icon = isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded;
    final label = isSuccess
        ? (task.resultSummary?.isNotEmpty == true
            ? task.resultSummary!
            : 'Completed successfully')
        : (task.errorMessage?.isNotEmpty == true
            ? task.errorMessage!
            : 'Task failed');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ],
          ),
          if (onViewDiff != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onViewDiff,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.compare_arrows_rounded,
                    size: 13,
                    color: ForgePalette.primaryAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'View diff',
                    style: TextStyle(
                      fontSize: 12,
                      color: ForgePalette.primaryAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.hasSelection,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSubmitting;
  final bool hasSelection;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: ForgePalette.surface,
          border: Border(
            top: BorderSide(color: ForgePalette.border),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 6,
                minLines: 1,
                enabled: hasSelection && !isSubmitting,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: hasSelection
                      ? 'Describe a task for the agent…'
                      : 'Select a repository first',
                  hintStyle: TextStyle(color: ForgePalette.textMuted),
                  filled: true,
                  fillColor: ForgePalette.backgroundSecondary,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isSubmitting
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ForgePalette.primaryAccent,
                          ),
                        ),
                      ),
                    )
                  : IconButton(
                      key: const ValueKey('send'),
                      icon: Icon(
                        Icons.send_rounded,
                        color: hasSelection
                            ? ForgePalette.primaryAccent
                            : ForgePalette.textMuted,
                      ),
                      onPressed: hasSelection ? onSubmit : null,
                      tooltip: 'Send',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
