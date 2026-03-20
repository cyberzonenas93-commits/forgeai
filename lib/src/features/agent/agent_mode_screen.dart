import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_agent_entities.dart';
import '../workspace/domain/forge_workspace_state.dart';
import 'agent_task_details_screen.dart';
import 'agent_ui_utils.dart';
import 'widgets/active_step_header.dart';
import 'widgets/approval_action_sheet.dart';
import 'widgets/empty_workspace_state.dart';
import 'widgets/failure_state_card.dart';
import 'widgets/files_touched_panel.dart';
import 'widgets/live_event_row.dart';
import 'widgets/queue_item_card.dart';
import 'widgets/success_state_card.dart';
import 'widgets/task_status_chip.dart';
import 'widgets/task_summary_card.dart';

class AgentModeScreen extends StatefulWidget {
  const AgentModeScreen({
    super.key,
    required this.controller,
    this.onSwitchToEditorTab,
  });

  final ForgeWorkspaceController controller;
  final VoidCallback? onSwitchToEditorTab;

  @override
  State<AgentModeScreen> createState() => _AgentModeScreenState();
}

class _AgentModeScreenState extends State<AgentModeScreen> {
  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();
  final ScrollController _timelineScrollController = ScrollController();

  int _lastTimelineEventCount = 0;
  String? _pendingPrimaryTaskSelectionId;
  String? _lastPresentedApprovalId;
  bool _isApprovalSheetVisible = false;

  @override
  void dispose() {
    _promptController.dispose();
    _promptFocusNode.dispose();
    _timelineScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ForgeWorkspaceState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final selectedRepo = state.selectedRepository;
        final repoTasks = _repoTasksForSelectedWorkspace(state);
        final activeTask = _findActiveTask(repoTasks);
        final queuedTasks = _queuedTasks(repoTasks);
        final recentTasks = _recentTasks(repoTasks);
        final displayedTask = activeTask;
        final displayedEvents = displayedTask != null &&
                state.selectedAgentTaskId == displayedTask.id
            ? state.agentTaskEvents
            : const <ForgeAgentTaskEvent>[];
        final displayedSession = displayedTask != null &&
                displayedTask.sessionId != null &&
                state.currentExecutionSession?.id == displayedTask.sessionId
            ? state.currentExecutionSession
            : null;
        final repoLabel = selectedRepo?.repoLabel ?? 'No workspace selected';
        final canSubmit = selectedRepo != null &&
            _promptController.text.trim().isNotEmpty &&
            !state.isSubmittingAgentTask;

        _ensurePrimaryTaskSelection(state, activeTask);
        _maybeAutoScrollTimeline(displayedEvents);
        _maybePresentApprovalSheet(
          task: displayedTask,
          repoLabel: repoLabel,
          isResolving: state.isResolvingAgentTask,
        );

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            padding: EdgeInsets.zero,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              children: [
                ForgeReveal(
                  child: _WorkspaceBanner(
                    repoLabel: repoLabel,
                    hasSelection: selectedRepo != null,
                    queueCount: queuedTasks.length,
                    isLocked: activeTask != null,
                    isDeepMode: state.repoExecutionDeepMode,
                    onToggleDeepMode: selectedRepo == null
                        ? null
                        : widget.controller.setRepoExecutionDeepMode,
                  ),
                ),
                const SizedBox(height: 16),
                if (selectedRepo == null)
                  ForgeReveal(
                    delay: const Duration(milliseconds: 60),
                    child: EmptyWorkspaceState(
                      repoLabel: null,
                      onUsePrompt: _applySuggestedPrompt,
                    ),
                  )
                else if (displayedTask == null) ...[
                  ForgeReveal(
                    delay: const Duration(milliseconds: 60),
                    child: EmptyWorkspaceState(
                      repoLabel: repoLabel,
                      onUsePrompt: _applySuggestedPrompt,
                    ),
                  ),
                  if (queuedTasks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _QueuePreviewPanel(
                      queuedTasks: queuedTasks,
                      repoLabelForTask: _repoLabelForTask,
                      onOpenQueue: () => _showQueueSheet(
                        queuedTasks: queuedTasks,
                        activeTask: activeTask,
                      ),
                      onOpenDetails: _openTaskDetails,
                      onRemove: (taskId) => _cancelTask(
                        taskId,
                        isQueued: true,
                      ),
                    ),
                  ],
                  if (recentTasks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _RecentTasksPanel(
                      tasks: recentTasks,
                      repoLabelForTask: _repoLabelForTask,
                      onOpenDetails: _openTaskDetails,
                    ),
                  ],
                ] else ...[
                  ForgeReveal(
                    delay: const Duration(milliseconds: 60),
                    child: ActiveStepHeader(
                      task: displayedTask,
                      repoLabel: _repoLabelForTask(displayedTask.repoId),
                      queueCount: queuedTasks.length,
                      onOpenQueue: queuedTasks.isEmpty
                          ? () => _showQueueSheet(
                                queuedTasks: queuedTasks,
                                activeTask: activeTask,
                              )
                          : () => _showQueueSheet(
                                queuedTasks: queuedTasks,
                                activeTask: activeTask,
                              ),
                      onOpenDetails: () => _openTaskDetails(
                        displayedTask.id,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (displayedTask.isRunning || displayedTask.needsApproval)
                    ForgeReveal(
                      delay: const Duration(milliseconds: 110),
                      child: _TaskControlsPanel(
                        task: displayedTask,
                        isResolving: state.isResolvingAgentTask,
                        onPause: displayedTask.isRunning
                            ? () => _pauseTask(displayedTask.id)
                            : null,
                        onCancel: () => _cancelTask(
                          displayedTask.id,
                          isQueued: displayedTask.isQueued,
                        ),
                        onOpenApproval: displayedTask.needsApproval
                            ? () => _openApprovalSheet(
                                  task: displayedTask,
                                  repoLabel: _repoLabelForTask(
                                    displayedTask.repoId,
                                  ),
                                  isResolving: state.isResolvingAgentTask,
                                )
                            : null,
                        onApprove: displayedTask.needsApproval
                            ? () => _resolveApproval(
                                  taskId: displayedTask.id,
                                  approved: true,
                                )
                            : null,
                        onReject: displayedTask.needsApproval
                            ? () => _resolveApproval(
                                  taskId: displayedTask.id,
                                  approved: false,
                                )
                            : null,
                        onReviewDiff: displayedTask.sessionId != null &&
                                widget.onSwitchToEditorTab != null
                            ? _openDiffView
                            : null,
                      ),
                  ),
                  const SizedBox(height: 16),
                  ForgeReveal(
                    delay: const Duration(milliseconds: 130),
                    child: _QueuePreviewPanel(
                      queuedTasks: queuedTasks,
                      repoLabelForTask: _repoLabelForTask,
                      onOpenQueue: () => _showQueueSheet(
                        queuedTasks: queuedTasks,
                        activeTask: activeTask,
                      ),
                      onOpenDetails: _openTaskDetails,
                      onRemove: (taskId) => _cancelTask(
                        taskId,
                        isQueued: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ForgeReveal(
                    delay: const Duration(milliseconds: 170),
                    child: _buildTaskStateCard(displayedTask),
                  ),
                  const SizedBox(height: 16),
                  ForgeReveal(
                    delay: const Duration(milliseconds: 210),
                    child: FilesTouchedPanel(
                      task: displayedTask,
                      session: displayedSession,
                      events: displayedEvents,
                      onOpenFile: _openFile,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ForgeReveal(
                    delay: const Duration(milliseconds: 250),
                    child: _TimelinePanel(
                      events: displayedEvents,
                      task: displayedTask,
                      controller: _timelineScrollController,
                      onOpenDetails: () => _openTaskDetails(
                        displayedTask.id,
                      ),
                    ),
                  ),
                  if (recentTasks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _RecentTasksPanel(
                      tasks: recentTasks,
                      repoLabelForTask: _repoLabelForTask,
                      onOpenDetails: _openTaskDetails,
                    ),
                  ],
                ],
                const SizedBox(height: 128),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: _PromptComposer(
              controller: _promptController,
              focusNode: _promptFocusNode,
              repoLabel: repoLabel,
              isDeepMode: state.repoExecutionDeepMode,
              hasSelection: selectedRepo != null,
              queueCount: queuedTasks.length,
              isSubmitting: state.isSubmittingAgentTask,
              activeTask: activeTask,
              canSubmit: canSubmit,
              onToggleDeepMode: selectedRepo == null
                  ? null
                  : widget.controller.setRepoExecutionDeepMode,
              onSubmit: () => _submitPrompt(
                activeTask: activeTask,
                queueDepth: queuedTasks.length,
              ),
            ),
          ),
        );
      },
    );
  }

  List<ForgeAgentTask> _repoTasksForSelectedWorkspace(ForgeWorkspaceState state) {
    final selectedRepo = state.selectedRepository;
    final tasks = selectedRepo == null
        ? List<ForgeAgentTask>.from(state.agentTasks)
        : state.agentTasks
            .where((task) => task.repoId == selectedRepo.id)
            .toList();
    tasks.sort((a, b) {
      if (a.isActive && !b.isActive) {
        return -1;
      }
      if (!a.isActive && b.isActive) {
        return 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return tasks;
  }

  ForgeAgentTask? _findActiveTask(List<ForgeAgentTask> tasks) {
    for (final task in tasks) {
      if (task.isActive) {
        return task;
      }
    }
    return null;
  }

  List<ForgeAgentTask> _queuedTasks(List<ForgeAgentTask> tasks) {
    final queued = tasks
        .where((task) => task.status == ForgeAgentTaskStatus.queued)
        .toList();
    queued.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return queued;
  }

  List<ForgeAgentTask> _recentTasks(List<ForgeAgentTask> tasks) {
    final recent = tasks
        .where(
          (task) =>
              task.status != ForgeAgentTaskStatus.queued && !task.isActive,
        )
        .toList();
    recent.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return recent.take(6).toList();
  }

  void _ensurePrimaryTaskSelection(
    ForgeWorkspaceState state,
    ForgeAgentTask? activeTask,
  ) {
    final targetId = activeTask?.id;
    if (targetId == null ||
        state.selectedAgentTaskId == targetId ||
        _pendingPrimaryTaskSelectionId == targetId) {
      return;
    }
    _pendingPrimaryTaskSelectionId = targetId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.controller.selectAgentTask(targetId);
      } finally {
        if (mounted && _pendingPrimaryTaskSelectionId == targetId) {
          _pendingPrimaryTaskSelectionId = null;
        }
      }
    });
  }

  void _maybeAutoScrollTimeline(List<ForgeAgentTaskEvent> events) {
    if (_lastTimelineEventCount == events.length) {
      return;
    }
    _lastTimelineEventCount = events.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timelineScrollController.hasClients) {
        return;
      }
      final position = _timelineScrollController.position;
      final distanceToBottom = position.maxScrollExtent - position.pixels;
      final shouldFollow = distanceToBottom < 80 || position.pixels == 0;
      if (!shouldFollow) {
        return;
      }
      _timelineScrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _maybePresentApprovalSheet({
    required ForgeAgentTask? task,
    required String repoLabel,
    required bool isResolving,
  }) {
    final approvalId = task?.pendingApproval?.id;
    if (task == null ||
        !task.needsApproval ||
        approvalId == null ||
        _isApprovalSheetVisible ||
        _lastPresentedApprovalId == approvalId) {
      return;
    }
    _lastPresentedApprovalId = approvalId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openApprovalSheet(
        task: task,
        repoLabel: repoLabel,
        isResolving: isResolving,
      );
    });
  }

  String _repoLabelForTask(String repoId) {
    for (final repository in widget.controller.value.repositories) {
      if (repository.id == repoId) {
        return repository.repoLabel;
      }
    }
    return 'Workspace unavailable';
  }

  Widget _buildTaskStateCard(ForgeAgentTask task) {
    if (task.status == ForgeAgentTaskStatus.failed) {
      return FailureStateCard(
        task: task,
        onRetry: () => _duplicateTask(task, showRetryMessage: true),
        onDuplicate: () => _duplicateTask(task),
        onInspectLogs: () => _openTaskDetails(task.id),
        onDismiss: () => widget.controller.value = widget.controller.value
            .copyWith(clearSelectedAgentTask: true, agentTaskEvents: const []),
      );
    }
    if (task.status == ForgeAgentTaskStatus.completed) {
      return SuccessStateCard(
        task: task,
        onViewDiff: task.sessionId != null && widget.onSwitchToEditorTab != null
            ? _openDiffView
            : null,
        onOpenDetails: () => _openTaskDetails(task.id),
      );
    }
    return TaskSummaryCard(
      task: task,
      onOpenDetails: () => _openTaskDetails(task.id),
      onViewDiff: task.sessionId != null && widget.onSwitchToEditorTab != null
          ? _openDiffView
          : null,
    );
  }

  Future<void> _submitPrompt({
    required ForgeAgentTask? activeTask,
    required int queueDepth,
  }) async {
    try {
      await widget.controller.enqueueAgentTask(
        prompt: _promptController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      _promptController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activeTask == null
                ? 'Work session started.'
                : 'Queued as #${queueDepth + 1} behind the active run.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(forgeUserFriendlyMessage(error))),
      );
    }
  }

  Future<void> _cancelTask(
    String taskId, {
    required bool isQueued,
  }) async {
    try {
      await widget.controller.cancelAgentTask(taskId: taskId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isQueued ? 'Removed from queue.' : 'Cancellation requested.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(forgeUserFriendlyMessage(error))),
      );
    }
  }

  Future<void> _pauseTask(String taskId) async {
    try {
      await widget.controller.pauseAgentTask(taskId: taskId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pause requested. The agent will pause at a safe checkpoint.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(forgeUserFriendlyMessage(error))),
      );
    }
  }

  Future<void> _resolveApproval({
    required String taskId,
    required bool approved,
  }) async {
    try {
      await widget.controller.resolveAgentTaskApproval(
        taskId: taskId,
        approved: approved,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved ? 'Approval submitted. The agent is resuming.' : 'Revision requested.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(forgeUserFriendlyMessage(error))),
      );
    }
  }

  Future<void> _duplicateTask(
    ForgeAgentTask task, {
    bool showRetryMessage = false,
  }) async {
    try {
      await widget.controller.enqueueAgentTask(
        prompt: task.prompt,
        repoId: task.repoId,
        currentFilePath: task.currentFilePath,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            showRetryMessage
                ? 'Retry queued for the workspace.'
                : 'Run duplicated into the queue.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(forgeUserFriendlyMessage(error))),
      );
    }
  }

  Future<void> _openTaskDetails(String taskId) async {
    await widget.controller.selectAgentTask(taskId);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AgentTaskDetailsScreen(
          controller: widget.controller,
          taskId: taskId,
          onSwitchToEditorTab: widget.onSwitchToEditorTab,
        ),
      ),
    );
  }

  Future<void> _openFile(String path) async {
    try {
      await widget.controller.openFile(
        ForgeFileNode(
          name: path.split('/').last,
          path: path,
          language: 'Text',
          sizeLabel: '',
          changeLabel: '',
        ),
      );
      if (!mounted) {
        return;
      }
      if (widget.onSwitchToEditorTab != null) {
        widget.onSwitchToEditorTab!();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(forgeUserFriendlyMessage(error))),
      );
    }
  }

  Future<void> _openApprovalSheet({
    required ForgeAgentTask task,
    required String repoLabel,
    required bool isResolving,
  }) async {
    if (_isApprovalSheetVisible) {
      return;
    }
    _isApprovalSheetVisible = true;
    await showApprovalActionSheet(
      context: context,
      task: task,
      repoLabel: repoLabel,
      isResolving: isResolving,
      onApprove: () => _resolveApproval(taskId: task.id, approved: true),
      onReject: () => _resolveApproval(taskId: task.id, approved: false),
      onReviewDiff: task.sessionId != null && widget.onSwitchToEditorTab != null
          ? _openDiffView
          : null,
    );
    _isApprovalSheetVisible = false;
  }

  Future<void> _showQueueSheet({
    required List<ForgeAgentTask> queuedTasks,
    required ForgeAgentTask? activeTask,
  }) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: ForgePalette.backgroundSecondary,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              12,
              18,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Run queue',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  activeTask == null
                      ? 'No run currently owns the workspace.'
                      : 'Queued runs wait here while the active run keeps the workspace lock.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ForgePalette.textSecondary,
                      ),
                ),
                const SizedBox(height: 16),
                if (queuedTasks.isEmpty)
                  ForgePanel(
                    child: Text(
                      'No queued runs.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.textSecondary,
                          ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: queuedTasks.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final task = queuedTasks[index];
                        return QueueItemCard(
                          task: task,
                          position: index + 1,
                          repoLabel: _repoLabelForTask(task.repoId),
                          onTap: () {
                            Navigator.of(context).pop();
                            _openTaskDetails(task.id);
                          },
                          onRemove: () {
                            Navigator.of(context).pop();
                            _cancelTask(task.id, isQueued: true);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _applySuggestedPrompt(String prompt) {
    _promptController
      ..text = prompt
      ..selection = TextSelection.collapsed(offset: prompt.length);
    _promptFocusNode.requestFocus();
  }

  void _openDiffView() {
    if (widget.onSwitchToEditorTab != null) {
      widget.onSwitchToEditorTab!();
    }
  }
}

class _WorkspaceBanner extends StatelessWidget {
  const _WorkspaceBanner({
    required this.repoLabel,
    required this.hasSelection,
    required this.queueCount,
    required this.isLocked,
    required this.isDeepMode,
    required this.onToggleDeepMode,
  });

  final String repoLabel;
  final bool hasSelection;
  final int queueCount;
  final bool isLocked;
  final bool isDeepMode;
  final ValueChanged<bool>? onToggleDeepMode;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      highlight: hasSelection,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Work Session',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: ForgePalette.glowAccent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Live agent execution',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            hasSelection
                ? 'Track the active run, review checkpoints, and stack follow-up runs without breaking flow.'
                : 'Select a repository to start a live run with queueing, approvals, and a durable execution log.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ForgePalette.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ForgePill(
                label: repoLabel,
                icon: Icons.folder_copy_rounded,
                color: hasSelection
                    ? ForgePalette.primaryAccent
                    : ForgePalette.textMuted,
              ),
              ForgePill(
                label: queueCount == 0 ? 'Queue empty' : '$queueCount queued',
                icon: Icons.format_list_numbered_rounded,
                color: queueCount == 0
                    ? ForgePalette.textMuted
                    : ForgePalette.primaryAccent,
              ),
              ForgePill(
                label: isLocked ? 'Workspace locked' : 'Workspace idle',
                icon: isLocked ? Icons.lock_clock_rounded : Icons.lock_open_rounded,
                color: isLocked ? ForgePalette.warning : ForgePalette.success,
              ),
              FilterChip(
                selected: isDeepMode,
                onSelected: onToggleDeepMode,
                avatar: Icon(
                  isDeepMode
                      ? Icons.psychology_rounded
                      : Icons.flash_on_rounded,
                  size: 18,
                  color: isDeepMode
                      ? ForgePalette.textPrimary
                      : ForgePalette.textSecondary,
                ),
                label: Text(isDeepMode ? 'Deep mode' : 'Normal mode'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskControlsPanel extends StatelessWidget {
  const _TaskControlsPanel({
    required this.task,
    required this.isResolving,
    this.onPause,
    this.onCancel,
    this.onOpenApproval,
    this.onApprove,
    this.onReject,
    this.onReviewDiff,
  });

  final ForgeAgentTask task;
  final bool isResolving;
  final VoidCallback? onPause;
  final VoidCallback? onCancel;
  final VoidCallback? onOpenApproval;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onReviewDiff;

  @override
  Widget build(BuildContext context) {
    final approval = task.pendingApproval;
    return ForgePanel(
      highlight: task.needsApproval,
      backgroundColor: task.needsApproval
          ? ForgePalette.warning.withValues(alpha: 0.08)
          : null,
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
                      task.needsApproval ? 'Approval required' : 'Run controls',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.needsApproval && approval != null
                          ? approvalTypeLabel(approval.type)
                          : 'Control the active run without leaving the console.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: task.needsApproval
                                ? ForgePalette.warning
                                : ForgePalette.textSecondary,
                            fontWeight: task.needsApproval
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              if (task.needsApproval) TaskStatusChip(task: task),
            ],
          ),
          const SizedBox(height: 10),
          if (task.needsApproval || task.isRunning)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ForgePill(
                  label: task.currentStep,
                  icon: Icons.track_changes_rounded,
                  color: task.needsApproval
                      ? ForgePalette.warning
                      : ForgePalette.primaryAccent,
                ),
                ForgePill(
                  label: '${task.filesTouched.length} files',
                  icon: Icons.description_rounded,
                  color: ForgePalette.textSecondary,
                ),
                if (task.metadata['branchName'] is String)
                  ForgePill(
                    label: task.metadata['branchName'] as String,
                    icon: Icons.call_split_rounded,
                    color: ForgePalette.glowAccent,
                  ),
              ],
            ),
          if (task.needsApproval || task.isRunning) const SizedBox(height: 12),
          Text(
            task.needsApproval && approval != null
                ? approval.description
                : task.isRunning
                    ? 'The run is in flight. Pause at the next safe checkpoint or stop the run if you need to take over.'
                    : 'The run is waiting here for the next action.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ForgePalette.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (task.needsApproval && onOpenApproval != null)
                ForgePrimaryButton(
                  label: 'Review',
                  icon: Icons.pending_actions_rounded,
                  onPressed: isResolving ? null : onOpenApproval,
                ),
              if (task.needsApproval && onApprove != null)
                ForgeSecondaryButton(
                  label: approval?.actionLabel ?? 'Approve',
                  icon: Icons.check_rounded,
                  onPressed: isResolving ? null : onApprove,
                ),
              if (task.needsApproval && onReject != null)
                ForgeSecondaryButton(
                  label: approval?.type ==
                          ForgeAgentTaskApprovalType.applyChanges
                      ? 'Revise'
                      : (approval?.cancelLabel ?? 'Reject'),
                  icon: Icons.close_rounded,
                  onPressed: isResolving ? null : onReject,
                ),
              if (!task.needsApproval && onPause != null)
                ForgeSecondaryButton(
                  label: 'Pause after step',
                  icon: Icons.pause_circle_outline_rounded,
                  onPressed: isResolving ? null : onPause,
                ),
              if (onCancel != null)
                ForgeSecondaryButton(
                  label: task.isQueued ? 'Remove from queue' : 'Cancel task',
                  icon: Icons.stop_circle_outlined,
                  onPressed: isResolving ? null : onCancel,
                ),
              if (onReviewDiff != null)
                ForgeSecondaryButton(
                  label: 'Open diff',
                  icon: Icons.compare_arrows_rounded,
                  onPressed: onReviewDiff,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({
    required this.events,
    required this.task,
    required this.controller,
    required this.onOpenDetails,
  });

  final List<ForgeAgentTaskEvent> events;
  final ForgeAgentTask task;
  final ScrollController controller;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final latestEvent = events.isEmpty ? null : events.last;
    final timelineHeight = MediaQuery.sizeOf(context).height < 760 ? 300.0 : 380.0;
    return ForgePanel(
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
                      'Execution log',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Live steps stay pinned at the top while the full run stays visible for debugging.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              if (events.isNotEmpty)
                ForgePill(
                  label: '${events.length} events',
                  icon: Icons.timeline_rounded,
                  color: ForgePalette.primaryAccent,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (latestEvent != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ForgePalette.glowAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: ForgePalette.glowAccent.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: const BoxDecoration(
                      color: ForgePalette.glowAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Now',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: ForgePalette.glowAccent,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    latestEvent.step,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                        const SizedBox(height: 4),
                        Text(
                          latestEvent.message,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: ForgePalette.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (latestEvent != null) const SizedBox(height: 14),
          if (events.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: ForgePalette.surfaceElevated.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: ForgePalette.border.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Waiting for events',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    task.isQueued
                        ? 'This task is queued behind the active workspace run. Its event stream will begin once it starts.'
                        : 'The agent will stream each repository action here as soon as the next step is emitted.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ForgePalette.textSecondary,
                        ),
                  ),
                ],
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: timelineHeight,
                decoration: BoxDecoration(
                  color: ForgePalette.surfaceElevated.withValues(alpha: 0.32),
                  border: Border.all(
                    color: ForgePalette.border.withValues(alpha: 0.7),
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.all(12),
                  itemCount: events.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return LiveEventRow(
                      event: event,
                      isCurrent: index == events.length - 1,
                    );
                  },
                ),
              ),
            ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpenDetails,
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('Open run log'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueuePreviewPanel extends StatelessWidget {
  const _QueuePreviewPanel({
    required this.queuedTasks,
    required this.repoLabelForTask,
    required this.onOpenQueue,
    required this.onOpenDetails,
    required this.onRemove,
  });

  final List<ForgeAgentTask> queuedTasks;
  final String Function(String repoId) repoLabelForTask;
  final VoidCallback onOpenQueue;
  final ValueChanged<String> onOpenDetails;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
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
                      'Queue',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      queuedTasks.isEmpty
                          ? 'New runs land here while another run owns the workspace.'
                          : 'Queued runs stay ordered here until the active run releases the lock.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              if (queuedTasks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ForgePill(
                    label: '${queuedTasks.length} queued',
                    icon: Icons.format_list_numbered_rounded,
                    color: ForgePalette.primaryAccent,
                  ),
                ),
              TextButton.icon(
                onPressed: onOpenQueue,
                icon: const Icon(Icons.open_in_full_rounded, size: 16),
                label: Text(queuedTasks.isEmpty ? 'Open' : 'View all'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (queuedTasks.isEmpty)
            Text(
              'No queued runs.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ForgePalette.textSecondary,
                  ),
            )
          else
            Column(
              children: List<Widget>.generate(
                queuedTasks.length > 3 ? 3 : queuedTasks.length,
                (index) {
                  final task = queuedTasks[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index ==
                              ((queuedTasks.length > 3 ? 3 : queuedTasks.length) -
                                  1)
                          ? 0
                          : 12,
                    ),
                    child: ForgeReveal(
                      delay: Duration(milliseconds: 80 * (index + 1)),
                      child: QueueItemCard(
                        task: task,
                        position: index + 1,
                        repoLabel: repoLabelForTask(task.repoId),
                        onTap: () => onOpenDetails(task.id),
                        onRemove: () => onRemove(task.id),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentTasksPanel extends StatelessWidget {
  const _RecentTasksPanel({
    required this.tasks,
    required this.repoLabelForTask,
    required this.onOpenDetails,
  });

  final List<ForgeAgentTask> tasks;
  final String Function(String repoId) repoLabelForTask;
  final ValueChanged<String> onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent runs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Completed, failed, and cancelled runs stay available for inspection.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ForgePalette.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          Column(
            children: List<Widget>.generate(
              tasks.length,
              (index) {
                final task = tasks[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == tasks.length - 1 ? 0 : 12,
                  ),
                  child: _RecentTaskCard(
                    task: task,
                    repoLabel: repoLabelForTask(task.repoId),
                    onTap: () => onOpenDetails(task.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTaskCard extends StatelessWidget {
  const _RecentTaskCard({
    required this.task,
    required this.repoLabel,
    required this.onTap,
  });

  final ForgeAgentTask task;
  final String repoLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: TaskStatusChip(task: task)),
              const SizedBox(width: 8),
              ForgePill(
                label: formatRelativeTime(task.updatedAt),
                icon: Icons.schedule_rounded,
                color: ForgePalette.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            taskHeadline(task),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ForgePill(
                label: repoLabel,
                icon: Icons.folder_copy_rounded,
                color: ForgePalette.textSecondary,
              ),
              ForgePill(
                label: '${task.diffCount} diffs',
                icon: Icons.compare_arrows_rounded,
                color: ForgePalette.primaryAccent,
              ),
              ForgePill(
                label: '${task.filesTouched.length} files',
                icon: Icons.description_rounded,
                color: ForgePalette.success,
              ),
            ],
          ),
          if ((task.resultSummary ?? task.errorMessage ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              (task.resultSummary ?? task.errorMessage)!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: task.status == ForgeAgentTaskStatus.failed
                        ? ForgePalette.error
                        : ForgePalette.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PromptComposer extends StatelessWidget {
  const _PromptComposer({
    required this.controller,
    required this.focusNode,
    required this.repoLabel,
    required this.isDeepMode,
    required this.hasSelection,
    required this.queueCount,
    required this.isSubmitting,
    required this.activeTask,
    required this.canSubmit,
    required this.onToggleDeepMode,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String repoLabel;
  final bool isDeepMode;
  final bool hasSelection;
  final int queueCount;
  final bool isSubmitting;
  final ForgeAgentTask? activeTask;
  final bool canSubmit;
  final ValueChanged<bool>? onToggleDeepMode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final queueLabel = activeTask == null
        ? 'Runs now'
        : (queueCount == 0 ? 'Queues next' : 'Queues as #${queueCount + 1}');
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ForgePanel(
        padding: const EdgeInsets.all(16),
        backgroundColor: ForgePalette.backgroundSecondary.withValues(alpha: 0.96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ForgePill(
                  label: repoLabel,
                  icon: Icons.folder_copy_rounded,
                  color: hasSelection
                      ? ForgePalette.primaryAccent
                      : ForgePalette.textMuted,
                ),
                ForgePill(
                  label: queueLabel,
                  icon: activeTask == null
                      ? Icons.play_arrow_rounded
                      : Icons.schedule_rounded,
                  color: activeTask == null
                      ? ForgePalette.success
                      : ForgePalette.warning,
                ),
                FilterChip(
                  selected: isDeepMode,
                  onSelected: onToggleDeepMode,
                  label: Text(isDeepMode ? 'Deep mode' : 'Normal mode'),
                ),
              ],
            ),
            if (activeTask != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ForgePalette.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: ForgePalette.warning.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_clock_rounded,
                      size: 18,
                      color: ForgePalette.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Workspace busy',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: ForgePalette.warning,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            queueCount == 0
                                ? 'The current run owns this repo. Your next submission will queue behind it.'
                                : 'The current run owns this repo. Your next submission will join ${queueCount + 1} queued runs.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: ForgePalette.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 2,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: activeTask == null
                    ? 'New task'
                    : 'Queue next run',
                hintText: activeTask == null
                    ? 'Fix auth, add onboarding, or refactor the repo service.'
                    : 'This run will wait until the active run finishes.',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    !hasSelection
                        ? 'Choose a repository to enable agent execution.'
                        : activeTask == null
                            ? 'Submitting now starts the live run.'
                            : 'Submitting now adds this run to the queue.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ForgePalette.textSecondary,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                ForgePrimaryButton(
                  label: isSubmitting
                      ? 'Submitting...'
                      : activeTask == null
                          ? 'Start task'
                          : 'Queue run',
                  icon: activeTask == null
                      ? Icons.play_arrow_rounded
                      : Icons.playlist_add_rounded,
                  onPressed: canSubmit ? onSubmit : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
