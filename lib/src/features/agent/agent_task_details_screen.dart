import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_agent_entities.dart';
import '../workspace/domain/forge_workspace_state.dart';
import 'agent_ui_utils.dart';
import 'widgets/files_touched_panel.dart';
import 'widgets/live_event_row.dart';
import 'widgets/task_status_chip.dart';

class AgentTaskDetailsScreen extends StatefulWidget {
  const AgentTaskDetailsScreen({
    super.key,
    required this.controller,
    required this.taskId,
    this.onSwitchToEditorTab,
  });

  final ForgeWorkspaceController controller;
  final String taskId;
  final VoidCallback? onSwitchToEditorTab;

  @override
  State<AgentTaskDetailsScreen> createState() => _AgentTaskDetailsScreenState();
}

class _AgentTaskDetailsScreenState extends State<AgentTaskDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.selectAgentTask(widget.taskId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ForgeWorkspaceState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final task = _findTask(state.agentTasks, widget.taskId);
        final repo = _findRepository(state.repositories, task?.repoId);
        final session = task != null &&
                task.sessionId != null &&
                state.currentExecutionSession?.id == task.sessionId
            ? state.currentExecutionSession
            : null;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Run details'),
          ),
          body: ForgeScreen(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: task == null
                ? Center(
                    child: Text(
                      'Run details are no longer available.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView(
                    children: [
                      ForgePanel(
                        highlight: task.isActive,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        taskHeadline(task),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        task.prompt,
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
                                const SizedBox(width: 12),
                                TaskStatusChip(task: task),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (repo != null)
                                  ForgePill(
                                    label: repo.repoLabel,
                                    icon: Icons.folder_copy_rounded,
                                    color: ForgePalette.primaryAccent,
                                  ),
                                ForgePill(
                                  label: task.currentStep,
                                  icon: Icons.track_changes_rounded,
                                  color: ForgePalette.glowAccent,
                                ),
                                ForgePill(
                                  label: formatElapsed(agentElapsed(task)),
                                  icon: Icons.timer_outlined,
                                  color: ForgePalette.warning,
                                ),
                                ForgePill(
                                  label: '${task.filesTouched.length} touched',
                                  icon: Icons.description_rounded,
                                  color: ForgePalette.success,
                                ),
                                ForgePill(
                                  label: '${task.diffCount} diffs',
                                  icon: Icons.compare_arrows_rounded,
                                  color: ForgePalette.primaryAccent,
                                ),
                                ForgePill(
                                  label: '${task.estimatedTokens} tokens',
                                  icon: Icons.token_rounded,
                                  color: ForgePalette.warning,
                                ),
                                if (task.retryCount > 0)
                                  ForgePill(
                                    label: '${task.retryCount} retries',
                                    icon: Icons.refresh_rounded,
                                    color: ForgePalette.emberAccent,
                                  ),
                              ],
                            ),
                            if ((task.resultSummary ?? task.executionSummary ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                (task.resultSummary ?? task.executionSummary)!
                                    .trim(),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                            if ((task.errorMessage ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                task.errorMessage!.trim(),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: ForgePalette.error,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilesTouchedPanel(
                        task: task,
                        session: session,
                        events: state.agentTaskEvents,
                        onOpenFile: _openFile,
                      ),
                      const SizedBox(height: 16),
                      ForgePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Validation',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            if ((task.latestValidationError ?? '')
                                .trim()
                                .isEmpty)
                              Text(
                                task.status == ForgeAgentTaskStatus.failed
                                    ? 'No validation metadata was captured for this failure.'
                                    : 'No validation failures were recorded for this task.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: ForgePalette.textSecondary,
                                    ),
                              )
                            else
                              Text(
                                task.latestValidationError!.trim(),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: ForgePalette.error,
                                    ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ForgePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Execution log',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ),
                                if (state.agentTaskEvents.isNotEmpty)
                                  ForgePill(
                                    label:
                                        '${state.agentTaskEvents.length} events',
                                    icon: Icons.timeline_rounded,
                                    color: ForgePalette.primaryAccent,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (state.agentTaskEvents.isEmpty)
                              Text(
                                'No events captured yet.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: ForgePalette.textSecondary,
                                    ),
                              )
                            else
                              Column(
                                children: List<Widget>.generate(
                                  state.agentTaskEvents.length,
                                  (index) {
                                    final event = state.agentTaskEvents[index];
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom: index ==
                                                state.agentTaskEvents.length - 1
                                            ? 0
                                            : 12,
                                      ),
                                      child: LiveEventRow(
                                        event: event,
                                        isCurrent: index ==
                                            state.agentTaskEvents.length - 1,
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          bottomNavigationBar: task == null
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (task.sessionId != null &&
                            widget.onSwitchToEditorTab != null)
                          ForgePrimaryButton(
                            label: 'View diff',
                            icon: Icons.compare_arrows_rounded,
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onSwitchToEditorTab!();
                            },
                          ),
                        ForgeSecondaryButton(
                          label: 'Run again',
                          icon: Icons.refresh_rounded,
                          onPressed: () => _rerunTask(task),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  ForgeAgentTask? _findTask(List<ForgeAgentTask> tasks, String taskId) {
    for (final task in tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  ForgeRepository? _findRepository(
    List<ForgeRepository> repositories,
    String? repoId,
  ) {
    if (repoId == null) {
      return null;
    }
    for (final repository in repositories) {
      if (repository.id == repoId) {
        return repository;
      }
    }
    return null;
  }

  Future<void> _rerunTask(ForgeAgentTask task) async {
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
        const SnackBar(content: Text('Run queued again.')),
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
        Navigator.of(context).pop();
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
}
