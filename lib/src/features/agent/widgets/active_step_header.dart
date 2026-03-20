import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';
import '../agent_ui_utils.dart';
import 'task_status_chip.dart';

class ActiveStepHeader extends StatelessWidget {
  const ActiveStepHeader({
    super.key,
    required this.task,
    required this.repoLabel,
    required this.queueCount,
    this.queuePosition,
    required this.onOpenQueue,
    required this.onOpenDetails,
  });

  final ForgeAgentTask task;
  final String repoLabel;
  final int queueCount;
  final int? queuePosition;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final elapsed = agentElapsed(task);
    final isQueued = task.isQueued;
    final maxRetries = task.metadata['maxRetries'] is num
        ? (task.metadata['maxRetries'] as num).toInt()
        : null;
    final validationAttemptCount =
        task.metadata['validationAttemptCount'] is num
            ? (task.metadata['validationAttemptCount'] as num).toInt()
            : 0;
    final hardLimitReached = task.metadata['hardLimitReached'] == true;
    final executionProvider = task.metadata['executionProvider'] is String
        ? (task.metadata['executionProvider'] as String).trim()
        : '';
    final toolRegistryCount = task.metadata['toolRegistryCount'] is num
        ? (task.metadata['toolRegistryCount'] as num).toInt()
        : 0;
    final preApplyValidationPassed =
        task.metadata['preApplyValidationPassed'] == true;
    final failureCategory = formatFailureCategoryLabel(
      task.metadata['latestFailureCategory'] as String?,
    );
    final repairTargetCount = countMetadataList(
      task.metadata,
      'repairTargetPaths',
    );
    final workspaceSource = formatWorkspaceSourceLabel(
      task.metadata['workspaceSourceOfTruth'] as String?,
    );
    final latestLine = task.latestEventMessage?.trim().isNotEmpty == true
        ? task.latestEventMessage!.trim()
        : task.executionSummary?.trim().isNotEmpty == true
            ? task.executionSummary!.trim()
            : task.currentStep;
    final accent = agentStatusColor(task);
    final runLabel = task.needsApproval
        ? 'Approval Block'
        : isQueued
            ? 'Queued Run'
            : task.status == ForgeAgentTaskStatus.completed
                ? 'Completed Run'
                : task.status == ForgeAgentTaskStatus.failed
                    ? 'Failed Run'
                    : 'Active Run';
    final stateTitle = task.needsApproval
        ? 'Waiting on your decision'
        : isQueued
            ? 'Waiting in queue'
            : task.status == ForgeAgentTaskStatus.completed
                ? 'Completed work'
                : task.status == ForgeAgentTaskStatus.failed
                    ? 'Failure summary'
                    : 'Current operation';
    final runSummary = ((task.metadata['planSummary'] is String
                ? task.metadata['planSummary'] as String
                : null) ??
            task.executionSummary ??
            task.latestEventMessage ??
            (isQueued
                ? 'This run is lined up behind the active workspace lock and will start automatically.'
                : 'The agent is actively working through the requested repository changes.'))
        .trim();
    return ForgePanel(
      highlight: task.isActive,
      padding: const EdgeInsets.all(22),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _AgentPulseIndicator(
                                color: accent,
                                active: task.isActive,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                runLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color: accent,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (queueCount > 0)
                          ForgePill(
                            label: '$queueCount queued',
                            icon: Icons.format_list_numbered_rounded,
                            color: ForgePalette.primaryAccent,
                          ),
                        if (isQueued && queuePosition != null)
                          ForgePill(
                            label: queuePosition == 1
                                ? 'Next in line'
                                : 'Queue #$queuePosition',
                            icon: Icons.playlist_play_rounded,
                            color: ForgePalette.warning,
                          ),
                        if (executionProvider.isNotEmpty)
                          ForgePill(
                            label: executionProvider,
                            icon: Icons.hub_rounded,
                            color: ForgePalette.sparkAccent,
                          ),
                        if (toolRegistryCount > 0)
                          ForgePill(
                            label: '$toolRegistryCount tools',
                            icon: Icons.handyman_rounded,
                            color: ForgePalette.textSecondary,
                          ),
                        if (preApplyValidationPassed)
                          const ForgePill(
                            label: 'Validated before apply',
                            icon: Icons.verified_rounded,
                            color: ForgePalette.success,
                          ),
                        if (failureCategory.isNotEmpty)
                          ForgePill(
                            label: failureCategory,
                            icon: Icons.bug_report_rounded,
                            color: ForgePalette.error,
                          ),
                        if (repairTargetCount != null && repairTargetCount > 0)
                          ForgePill(
                            label:
                                '$repairTargetCount targeted file${repairTargetCount == 1 ? '' : 's'}',
                            icon: Icons.my_location_rounded,
                            color: ForgePalette.warning,
                          ),
                        if (workspaceSource.isNotEmpty)
                          ForgePill(
                            label: workspaceSource,
                            icon: Icons.folder_open_rounded,
                            color: ForgePalette.textSecondary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      task.prompt.trim(),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      runSummary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TaskStatusChip(task: task),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: onOpenDetails,
                    icon: const Icon(Icons.open_in_full_rounded, size: 16),
                    label: const Text('Open run'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stateTitle,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  task.currentStep,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  latestLine,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ForgePalette.textSecondary,
                      ),
                ),
              ],
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
                color: ForgePalette.textSecondary,
              ),
              ForgePill(
                label: formatElapsed(elapsed),
                icon: Icons.timer_outlined,
                color: ForgePalette.glowAccent,
              ),
              ForgePill(
                label: '${task.filesTouched.length} files',
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
              if (task.inspectedFiles.isNotEmpty)
                ForgePill(
                  label: '${task.inspectedFiles.length} inspected',
                  icon: Icons.travel_explore_rounded,
                  color: ForgePalette.sparkAccent,
                ),
              if (task.retryCount > 0)
                ForgePill(
                  label: maxRetries != null
                      ? '${task.retryCount}/$maxRetries repair passes'
                      : '${task.retryCount} retries',
                  icon: Icons.refresh_rounded,
                  color: ForgePalette.emberAccent,
                ),
              if (validationAttemptCount > 0)
                ForgePill(
                  label:
                      '$validationAttemptCount validation pass${validationAttemptCount == 1 ? '' : 'es'}',
                  icon: Icons.rule_folder_rounded,
                  color: ForgePalette.warning,
                ),
              if (preApplyValidationPassed)
                const ForgePill(
                  label: 'Sandbox passed',
                  icon: Icons.shield_rounded,
                  color: ForgePalette.success,
                ),
              if (hardLimitReached)
                const ForgePill(
                  label: 'Hard limit hit',
                  icon: Icons.gpp_maybe_rounded,
                  color: ForgePalette.error,
                ),
              ForgePill(
                label: queueCount == 0 ? 'Queue clear' : '$queueCount queued',
                icon: Icons.format_list_numbered_rounded,
                color: queueCount == 0
                    ? ForgePalette.textMuted
                    : ForgePalette.primaryAccent,
              ),
            ],
          ),
          if (task.isRunning || task.needsApproval || isQueued) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Row(
                children: [
                  Icon(
                    task.needsApproval
                        ? Icons.pending_actions_rounded
                        : isQueued
                            ? Icons.schedule_rounded
                            : Icons.bolt_rounded,
                    size: 18,
                    color: accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      task.needsApproval
                          ? 'Run is paused at a checkpoint. The workspace stays locked until you approve or revise.'
                          : isQueued
                              ? 'This run is already planned and waiting for the current workspace lock to clear.'
                              : 'Run is live. The execution log below updates as the agent inspects, edits, and validates.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.textSecondary,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenQueue,
                    child: Text(queueCount == 0 ? 'Queue' : 'View queue'),
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

class _AgentPulseIndicator extends StatefulWidget {
  const _AgentPulseIndicator({
    required this.color,
    required this.active,
  });

  final Color color;
  final bool active;

  @override
  State<_AgentPulseIndicator> createState() => _AgentPulseIndicatorState();
}

class _AgentPulseIndicatorState extends State<_AgentPulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _AgentPulseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = 0.65 + ((_controller.value - 0.5).abs() * -0.5 + 0.25);
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.14 * pulse),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
