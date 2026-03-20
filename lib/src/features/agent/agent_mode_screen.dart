import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_agent_entities.dart';
import '../workspace/domain/forge_workspace_state.dart';
import '../workspace/domain/forge_workspace_entities.dart';
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
        final selectedTask = _selectedTaskForRepo(
          state.selectedAgentTaskId,
          repoTasks,
        );
        final displayedTask =
            selectedTask ??
            activeTask ??
            (queuedTasks.isNotEmpty
                ? queuedTasks.first
                : (recentTasks.isNotEmpty ? recentTasks.first : null));
        final displayedQueuePosition = displayedTask?.isQueued == true
            ? _queuePosition(queuedTasks, displayedTask!.id)
            : null;
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

        _ensurePrimaryTaskSelection(
          state,
          repoTasks,
          displayedTask,
        );
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
                    agentTrustLevel: state.agentTrustLevel,
                    onTrustLevelChanged: selectedRepo == null
                        ? null
                        : widget.controller.setAgentTrustLevel,
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
                      selectedTaskId: state.selectedAgentTaskId,
                      repoLabelForTask: _repoLabelForTask,
                      onOpenQueue: () => _showQueueSheet(
                        queuedTasks: queuedTasks,
                        activeTask: activeTask,
                      ),
                      onSelectTask: _focusTask,
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
                  if (displayedTask.isQueued &&
                      activeTask != null &&
                      activeTask.id != displayedTask.id) ...[
                    ForgeReveal(
                      delay: const Duration(milliseconds: 40),
                      child: _QueuedRunStatusPanel(
                        queuedTask: displayedTask,
                        activeTask: activeTask,
                        queuePosition: displayedQueuePosition ?? 1,
                        onFocusActiveRun: () => _focusTask(activeTask.id),
                        onOpenQueue: () => _showQueueSheet(
                          queuedTasks: queuedTasks,
                          activeTask: activeTask,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  ForgeReveal(
                    delay: const Duration(milliseconds: 60),
                    child: ActiveStepHeader(
                      task: displayedTask,
                      repoLabel: _repoLabelForTask(displayedTask.repoId),
                      queueCount: queuedTasks.length,
                      queuePosition: displayedQueuePosition,
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
                  if (displayedTask.isRunning ||
                      displayedTask.needsApproval ||
                      displayedTask.isQueued)
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
                      selectedTaskId: state.selectedAgentTaskId,
                      repoLabelForTask: _repoLabelForTask,
                      onOpenQueue: () => _showQueueSheet(
                        queuedTasks: queuedTasks,
                        activeTask: activeTask,
                      ),
                      onSelectTask: _focusTask,
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
                    delay: const Duration(milliseconds: 190),
                    child: _RepoAwarenessPanel(
                      task: displayedTask,
                      session: displayedSession,
                    ),
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

  ForgeAgentTask? _selectedTaskForRepo(
    String? selectedTaskId,
    List<ForgeAgentTask> tasks,
  ) {
    if (selectedTaskId == null) {
      return null;
    }
    for (final task in tasks) {
      if (task.id == selectedTaskId) {
        return task;
      }
    }
    return null;
  }

  int? _queuePosition(List<ForgeAgentTask> queuedTasks, String taskId) {
    for (var index = 0; index < queuedTasks.length; index += 1) {
      if (queuedTasks[index].id == taskId) {
        return index + 1;
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
    List<ForgeAgentTask> repoTasks,
    ForgeAgentTask? fallbackTask,
  ) {
    final selectedId = state.selectedAgentTaskId;
    if (selectedId != null && repoTasks.any((task) => task.id == selectedId)) {
      return;
    }
    final targetId = fallbackTask?.id;
    if (targetId == null || _pendingPrimaryTaskSelectionId == targetId) {
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

  Future<void> _focusTask(String taskId) async {
    try {
      await widget.controller.selectAgentTask(taskId);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load that run right now.'),
        ),
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
                          isSelected: widget
                                  .controller
                                  .value
                                  .selectedAgentTaskId ==
                              task.id,
                          onTap: () {
                            Navigator.of(context).pop();
                            _focusTask(task.id);
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

class _QueuedRunStatusPanel extends StatelessWidget {
  const _QueuedRunStatusPanel({
    required this.queuedTask,
    required this.activeTask,
    required this.queuePosition,
    required this.onFocusActiveRun,
    required this.onOpenQueue,
  });

  final ForgeAgentTask queuedTask;
  final ForgeAgentTask activeTask;
  final int queuePosition;
  final VoidCallback onFocusActiveRun;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final accent = ForgePalette.warning;
    return ForgePanel(
      highlight: true,
      backgroundColor: accent.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ForgePill(
                label: queuePosition == 1 ? 'Next in line' : 'Queue #$queuePosition',
                icon: Icons.schedule_rounded,
                color: accent,
              ),
              ForgePill(
                label: activeTask.currentStep,
                icon: Icons.lock_clock_rounded,
                color: ForgePalette.primaryAccent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Queued behind the active run',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'This run is already selected and planned. The workspace is currently owned by "${taskHeadline(activeTask)}", and your queued run will start automatically when that lock clears.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ForgePalette.textSecondary,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ForgeSecondaryButton(
                label: 'Focus active run',
                icon: Icons.motion_photos_on_rounded,
                onPressed: onFocusActiveRun,
              ),
              ForgeSecondaryButton(
                label: 'View full queue',
                icon: Icons.format_list_numbered_rounded,
                onPressed: onOpenQueue,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RepoAwarenessPanel extends StatelessWidget {
  const _RepoAwarenessPanel({
    required this.task,
    this.session,
  });

  final ForgeAgentTask task;
  final ForgeRepoExecutionSession? session;

  @override
  Widget build(BuildContext context) {
    final metadata = task.metadata;
    final repoOverview = session?.repoOverview ?? _stringValue(metadata['repoOverview']);
    final architectureOverview =
        session?.architectureOverview ?? _stringValue(metadata['architectureOverview']);
    final moduleOverview =
        session?.moduleOverview ?? _stringValue(metadata['moduleOverview']);
    final planningSummary = session?.planningSummary ??
        _stringValue(metadata['planningSummary']) ??
        _stringValue(metadata['planSummary']);
    final repoSizeClass =
        session?.repoSizeClass ?? _stringValue(metadata['repoSizeClass']);
    final contextStrategy =
        session?.contextStrategy ?? _stringValue(metadata['contextStrategy']);
    final executionMemorySummary = session?.executionMemorySummary ??
        _stringValue(metadata['executionMemorySummary']);
    final repoCoverageNotice = session?.repoCoverageNotice ??
        _stringValue(metadata['repoCoverageNotice']);
    final focusedModules = session?.focusedModules.isNotEmpty == true
        ? session!.focusedModules
        : _stringListValue(metadata['focusedModules']);
    final moduleCount = session?.moduleCount ??
        ((metadata['moduleCount'] is num)
            ? (metadata['moduleCount'] as num).toInt()
            : null);
    final architectureZoneCount = session?.architectureZoneCount ??
        ((metadata['architectureZoneCount'] is num)
            ? (metadata['architectureZoneCount'] as num).toInt()
            : null);
    final explorationPassCount = session?.explorationPassCount ??
        ((metadata['explorationPassCount'] is num)
            ? (metadata['explorationPassCount'] as num).toInt()
            : null);
    final explorationPass = metadata['explorationPass'] is num
        ? (metadata['explorationPass'] as num).toInt()
        : null;
    final explorationPassLimit = metadata['explorationPassLimit'] is num
        ? (metadata['explorationPassLimit'] as num).toInt()
        : null;
    final hydratedPathCount = session?.hydratedPathCount ??
        ((metadata['hydratedPathCount'] is num)
            ? (metadata['hydratedPathCount'] as num).toInt()
            : null);
    final wholeRepoEligible =
        session?.wholeRepoEligible ?? (metadata['wholeRepoEligible'] == true);
    final globalContextFiles = session?.globalContextFiles.isNotEmpty == true
        ? session!.globalContextFiles
        : _stringListValue(metadata['globalContextFiles']);
    final executionProvider =
        session?.executionProvider ?? _stringValue(metadata['executionProvider']);
    final repoFileCount = metadata['repoFileCount'] is num
        ? (metadata['repoFileCount'] as num).toInt()
        : null;
    final overviewText = [
      planningSummary,
      repoOverview != planningSummary ? repoOverview : null,
      architectureOverview,
      moduleOverview,
      executionMemorySummary,
    ].whereType<String>().map((value) => value.trim()).where((value) => value.isNotEmpty).join('\n\n');
    final intro = task.isQueued
        ? 'This run is queued, but the repo plan is already visible here so you can see how the agent intends to work before execution begins.'
        : task.isRunning
            ? 'The agent updates this view as it maps the repository, explores modules, and only later narrows down the final writable scope.'
            : task.needsApproval
                ? 'This run has already built repo context and is paused at a checkpoint.'
                : 'The repo context gathered for this run stays visible here for review.';
    final scopeNote = task.selectedFiles.isNotEmpty
        ? 'The editable wave is only the current write scope. The broader repo understanding comes from mapped files, focused modules, hydrated paths, read-only context, and repair-time expansion when failures expose more ripple paths.'
        : 'The agent is still building broad repo understanding before it finalizes any writable scope.';

    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Repo understanding',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      intro,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              ForgePill(
                label: wholeRepoEligible
                    ? 'Whole repo inline'
                    : 'Expanded repo map',
                icon: wholeRepoEligible
                    ? Icons.hub_rounded
                    : Icons.travel_explore_rounded,
                color: wholeRepoEligible
                    ? ForgePalette.success
                    : ForgePalette.primaryAccent,
              ),
              if ((repoSizeClass ?? '').trim().isNotEmpty)
                ForgePill(
                  label: repoSizeClass!,
                  icon: Icons.straighten_rounded,
                  color: ForgePalette.warning,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (repoFileCount != null)
                ForgePill(
                  label: '$repoFileCount files mapped',
                  icon: Icons.account_tree_rounded,
                  color: ForgePalette.textSecondary,
                ),
              if ((contextStrategy ?? '').trim().isNotEmpty)
                ForgePill(
                  label: contextStrategy!,
                  icon: Icons.psychology_alt_rounded,
                  color: ForgePalette.glowAccent,
                ),
              if ((executionProvider ?? '').trim().isNotEmpty)
                ForgePill(
                  label: executionProvider!,
                  icon: Icons.hub_rounded,
                  color: ForgePalette.sparkAccent,
                ),
              if (moduleCount != null)
                ForgePill(
                  label: '$moduleCount modules',
                  icon: Icons.widgets_rounded,
                  color: ForgePalette.emberAccent,
                ),
              if (architectureZoneCount != null)
                ForgePill(
                  label: '$architectureZoneCount zones',
                  icon: Icons.grid_view_rounded,
                  color: ForgePalette.warning,
                ),
              if (hydratedPathCount != null)
                ForgePill(
                  label: '$hydratedPathCount hydrated',
                  icon: Icons.dataset_linked_rounded,
                  color: ForgePalette.sparkAccent,
                ),
              if (explorationPass != null && explorationPassLimit != null)
                ForgePill(
                  label: 'Pass $explorationPass/$explorationPassLimit',
                  icon: Icons.alt_route_rounded,
                  color: ForgePalette.glowAccent,
                )
              else if (explorationPassCount != null && explorationPassCount > 0)
                ForgePill(
                  label: '$explorationPassCount passes',
                  icon: Icons.alt_route_rounded,
                  color: ForgePalette.glowAccent,
                ),
              ForgePill(
                label: '${task.selectedFiles.length} editable wave',
                icon: Icons.edit_note_rounded,
                color: ForgePalette.primaryAccent,
              ),
              ForgePill(
                label: '${task.inspectedFiles.length} inspected',
                icon: Icons.travel_explore_rounded,
                color: ForgePalette.sparkAccent,
              ),
              if (task.dependencyFiles.isNotEmpty)
                ForgePill(
                  label: '${task.dependencyFiles.length} dependencies',
                  icon: Icons.account_tree_rounded,
                  color: ForgePalette.warning,
                ),
              if (globalContextFiles.isNotEmpty)
                ForgePill(
                  label: '${globalContextFiles.length} global anchors',
                  icon: Icons.map_rounded,
                  color: ForgePalette.glowAccent,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _RepoInsightCard(
            title: 'What This Means',
            body: scopeNote,
          ),
          if ((repoCoverageNotice ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _RepoInsightCard(
              title: 'Sync Coverage',
              body: repoCoverageNotice!,
              accent: ForgePalette.warning,
            ),
          ],
          if (focusedModules.isNotEmpty) ...[
            const SizedBox(height: 12),
            _RepoModuleSection(
              modules: focusedModules,
              moduleCount: moduleCount,
            ),
          ],
          if (overviewText.isNotEmpty) ...[
            const SizedBox(height: 16),
            _RepoInsightCard(
              title: 'Architecture And Memory',
              body: overviewText,
            ),
          ],
          if (task.selectedFiles.isNotEmpty ||
              task.dependencyFiles.isNotEmpty ||
              globalContextFiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            _RepoPathSection(
              title: 'Current editable wave',
              description:
                  'This is the current writable wave, not the full repo context the agent inspected. Later repair passes can still widen it when failures expose more ripple paths.',
              paths: task.selectedFiles,
              emptyLabel: 'The agent has not selected editable files yet.',
            ),
            const SizedBox(height: 12),
            _RepoPathSection(
              title: 'Read-only context',
              description: 'Dependency files loaded to preserve architecture.',
              paths: task.dependencyFiles,
              emptyLabel: 'No dependency context has been attached yet.',
            ),
            const SizedBox(height: 12),
            _RepoPathSection(
              title: 'Global repo anchors',
              description: 'Repo-level files used to keep the run grounded.',
              paths: globalContextFiles,
              emptyLabel: 'No global repo anchors were needed for this run.',
            ),
          ],
        ],
      ),
    );
  }
}

class _RepoPathSection extends StatelessWidget {
  const _RepoPathSection({
    required this.title,
    required this.description,
    required this.paths,
    required this.emptyLabel,
  });

  final String title;
  final String description;
  final List<String> paths;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ForgePalette.surfaceElevated.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ForgePalette.border.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ForgePalette.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          if (paths.isEmpty)
            Text(
              emptyLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ForgePalette.textMuted,
                  ),
            )
          else
            Column(
              children: paths
                  .take(4)
                  .map(
                    (path) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          path,
                          style: Theme.of(context).textTheme.bodySmall,
                          softWrap: true,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _RepoInsightCard extends StatelessWidget {
  const _RepoInsightCard({
    required this.title,
    required this.body,
    this.accent = ForgePalette.glowAccent,
  });

  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ForgePalette.surfaceElevated.withValues(alpha: 0.44),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RepoModuleSection extends StatelessWidget {
  const _RepoModuleSection({
    required this.modules,
    this.moduleCount,
  });

  final List<String> modules;
  final int? moduleCount;

  @override
  Widget build(BuildContext context) {
    final visibleModules = modules.take(12).toList();
    final remaining = modules.length - visibleModules.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ForgePalette.surfaceElevated.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ForgePalette.border.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Focused modules',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            moduleCount != null
                ? 'The agent is tracking $moduleCount modules in the mapped repo and is currently focused on these higher-signal areas.'
                : 'These are the higher-signal modules the agent is actively using to understand the repo while it works.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ForgePalette.textSecondary,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final module in visibleModules)
                ForgePill(
                  label: module,
                  icon: Icons.widgets_rounded,
                  color: ForgePalette.emberAccent,
                ),
              if (remaining > 0)
                ForgePill(
                  label: '+$remaining more',
                  icon: Icons.more_horiz_rounded,
                  color: ForgePalette.textMuted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _stringValue(Object? value) {
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

List<String> _stringListValue(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

class _WorkspaceBanner extends StatelessWidget {
  const _WorkspaceBanner({
    required this.repoLabel,
    required this.hasSelection,
    required this.queueCount,
    required this.isLocked,
    required this.isDeepMode,
    required this.onToggleDeepMode,
    required this.agentTrustLevel,
    required this.onTrustLevelChanged,
  });

  final String repoLabel;
  final bool hasSelection;
  final int queueCount;
  final bool isLocked;
  final bool isDeepMode;
  final ValueChanged<bool>? onToggleDeepMode;
  final AgentTrustLevel agentTrustLevel;
  final ValueChanged<AgentTrustLevel>? onTrustLevelChanged;

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
                ? 'Watch the agent map the repo, edit files, validate changes, and queue follow-up runs without breaking flow.'
                : 'Select a repository to start a live run with repo inspection, queueing, approvals, and a durable execution log.',
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
              // ── Auto-execute mode selector ──
              PopupMenuButton<AgentTrustLevel>(
                initialValue: agentTrustLevel,
                onSelected: onTrustLevelChanged,
                tooltip: 'Execution mode',
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
                child: Chip(
                  avatar: Icon(
                    agentTrustLevel == AgentTrustLevel.supervised
                        ? Icons.supervised_user_circle_rounded
                        : agentTrustLevel == AgentTrustLevel.autoApproveOnSuccess
                            ? Icons.auto_mode_rounded
                            : Icons.rocket_launch_rounded,
                    size: 16,
                    color: agentTrustLevel == AgentTrustLevel.supervised
                        ? ForgePalette.textSecondary
                        : ForgePalette.success,
                  ),
                  label: Text(agentTrustLevel.label),
                  side: BorderSide(
                    color: agentTrustLevel == AgentTrustLevel.supervised
                        ? ForgePalette.textMuted
                        : ForgePalette.success,
                  ),
                ),
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
                          : task.isQueued
                              ? 'Queued behind the active workspace run'
                          : 'Control the active run without leaving the console.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: task.needsApproval
                                ? ForgePalette.warning
                                : task.isQueued
                                    ? ForgePalette.primaryAccent
                                : ForgePalette.textSecondary,
                            fontWeight: task.needsApproval
                                ? FontWeight.w600
                                : task.isQueued
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
          if (task.needsApproval || task.isRunning || task.isQueued)
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
          if (task.needsApproval || task.isRunning || task.isQueued)
            const SizedBox(height: 12),
          Text(
            task.needsApproval && approval != null
                ? approval.description
                : task.isRunning
                    ? 'The run is in flight. Pause at the next safe checkpoint or stop the run if you need to take over.'
                    : task.isQueued
                        ? 'This run is already accepted by the agent and will begin automatically once the active run releases the workspace lock.'
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
    final latestMetadata =
        latestEvent == null ? const <String>[] : buildEventMetadata(latestEvent);
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
                  if (latestMetadata.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: latestMetadata
                          .map(
                            (item) => ForgePill(
                              label: item,
                              icon: Icons.sell_outlined,
                              color: ForgePalette.glowAccent,
                            ),
                          )
                          .toList(),
                    ),
                  ],
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
    required this.selectedTaskId,
    required this.repoLabelForTask,
    required this.onOpenQueue,
    required this.onSelectTask,
    required this.onRemove,
  });

  final List<ForgeAgentTask> queuedTasks;
  final String? selectedTaskId;
  final String Function(String repoId) repoLabelForTask;
  final VoidCallback onOpenQueue;
  final ValueChanged<String> onSelectTask;
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
                          : 'Queued runs stay ordered here until the active run releases the lock. Tap any run to focus it.',
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
                        isSelected: selectedTaskId == task.id,
                        onTap: () => onSelectTask(task.id),
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
                                ? 'The current run owns this repo. Your next submission will queue behind it while the console stays live.'
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
                    : 'This run will queue, stay visible, and start automatically when the active run finishes.',
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
                            ? 'Submitting now starts the live run and begins repo inspection.'
                            : 'Submitting now adds this run to the queue and keeps it visible above.',
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
