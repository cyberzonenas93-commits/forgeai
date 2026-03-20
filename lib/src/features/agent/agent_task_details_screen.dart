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
import 'widgets/stream_log_widget.dart';
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
        final planSummary = task?.metadata['planSummary'] is String
            ? (task!.metadata['planSummary'] as String).trim()
            : '';
        final plannedSteps = task?.metadata['plannedSteps'] is List
            ? (task!.metadata['plannedSteps'] as List)
                .whereType<String>()
                .map((step) => step.trim())
                .where((step) => step.isNotEmpty)
                .toList()
            : const <String>[];
        final validationSummary = task?.metadata['validationSummary'] is String
            ? (task!.metadata['validationSummary'] as String).trim()
            : '';
        final validationAttemptCount =
            task?.metadata['validationAttemptCount'] is num
                ? (task!.metadata['validationAttemptCount'] as num).toInt()
                : 0;
        final failureCategory = task?.metadata['latestFailureCategory'] is String
            ? formatFailureCategoryLabel(
                (task!.metadata['latestFailureCategory'] as String).trim(),
              )
            : '';
        final workspaceSource = task?.metadata['workspaceSourceOfTruth'] is String
            ? formatWorkspaceSourceLabel(
                (task!.metadata['workspaceSourceOfTruth'] as String).trim(),
              )
            : '';
        final repairTargetPaths = task?.metadata['repairTargetPaths'] is List
            ? (task!.metadata['repairTargetPaths'] as List)
                .whereType<String>()
                .map((path) => path.trim())
                .where((path) => path.isNotEmpty)
                .toList()
            : const <String>[];
        final failureLocations = task?.metadata['latestFailureLocations'] is List
            ? (task!.metadata['latestFailureLocations'] as List)
                .whereType<String>()
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList()
            : const <String>[];
        final maxRetries = task?.metadata['maxRetries'] is num
            ? (task!.metadata['maxRetries'] as num).toInt()
            : 0;
        final hardLimitReached = task?.metadata['hardLimitReached'] == true;
        final latestValidationBranch =
            task?.metadata['latestValidationBranch'] as String?;
        final preApplyValidationPassed =
            task?.metadata['preApplyValidationPassed'] == true;
        final preApplyValidationSummary =
            task?.metadata['preApplyValidationSummary'] is String
                ? (task!.metadata['preApplyValidationSummary'] as String).trim()
                : '';
        final executionProvider = task?.metadata['executionProvider'] is String
            ? (task!.metadata['executionProvider'] as String).trim()
            : '';
        final executionModel = task?.metadata['executionModel'] is String
            ? (task!.metadata['executionModel'] as String).trim()
            : '';
        final executionProviderReason =
            task?.metadata['executionProviderReason'] is String
                ? (task!.metadata['executionProviderReason'] as String).trim()
                : '';
        final contextPlannerProvider =
            task?.metadata['contextPlannerProvider'] is String
                ? (task!.metadata['contextPlannerProvider'] as String).trim()
                : '';
        final executionPlannerProvider =
            task?.metadata['executionPlannerProvider'] is String
                ? (task!.metadata['executionPlannerProvider'] as String).trim()
                : '';
        final toolRegistrySummary =
            task?.metadata['toolRegistrySummary'] is String
                ? (task!.metadata['toolRegistrySummary'] as String).trim()
                : '';
        final toolExecutions = task == null
            ? const <_ToolExecutionView>[]
            : _toolExecutionsFromMetadata(task.metadata);
        final latestValidationResults = task == null
            ? const <_ValidationToolView>[]
            : _validationResultsFromMetadata(task.metadata);
        final validationHistory = task == null
            ? const <_ValidationHistoryView>[]
            : _validationHistoryFromMetadata(task.metadata);

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
                                    label: maxRetries > 0
                                        ? '${task.retryCount}/$maxRetries repair passes'
                                        : '${task.retryCount} retries',
                                    icon: Icons.refresh_rounded,
                                    color: ForgePalette.emberAccent,
                                  ),
                                if (failureCategory.isNotEmpty)
                                  ForgePill(
                                    label: failureCategory,
                                    icon: Icons.bug_report_rounded,
                                    color: ForgePalette.error,
                                  ),
                                if (repairTargetPaths.isNotEmpty)
                                  ForgePill(
                                    label:
                                        '${repairTargetPaths.length} targeted file${repairTargetPaths.length == 1 ? '' : 's'}',
                                    icon: Icons.my_location_rounded,
                                    color: ForgePalette.warning,
                                  ),
                                if (workspaceSource.isNotEmpty)
                                  ForgePill(
                                    label: workspaceSource,
                                    icon: Icons.folder_open_rounded,
                                    color: ForgePalette.textSecondary,
                                  ),
                                if (preApplyValidationPassed)
                                  const ForgePill(
                                    label: 'Validated before apply',
                                    icon: Icons.verified_rounded,
                                    color: ForgePalette.success,
                                  ),
                                if (hardLimitReached)
                                  const ForgePill(
                                    label: 'Hard limit hit',
                                    icon: Icons.gpp_maybe_rounded,
                                    color: ForgePalette.error,
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
                            if (preApplyValidationSummary.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                preApplyValidationSummary,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: ForgePalette.success,
                                    ),
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
                      if (planSummary.isNotEmpty || plannedSteps.isNotEmpty)
                        ForgePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Execution plan',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (planSummary.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  planSummary,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (plannedSteps.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ...plannedSteps.map(
                                  (step) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      '• $step',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color:
                                                ForgePalette.textSecondary,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (planSummary.isNotEmpty || plannedSteps.isNotEmpty)
                        const SizedBox(height: 16),
                      if (executionProvider.isNotEmpty ||
                          executionModel.isNotEmpty ||
                          toolRegistrySummary.isNotEmpty ||
                          toolExecutions.isNotEmpty ||
                          contextPlannerProvider.isNotEmpty ||
                          executionPlannerProvider.isNotEmpty)
                        ForgePanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Runtime routing',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (executionProvider.isNotEmpty)
                                    ForgePill(
                                      label: executionProvider,
                                      icon: Icons.hub_rounded,
                                      color: ForgePalette.sparkAccent,
                                    ),
                                  if (executionModel.isNotEmpty)
                                    ForgePill(
                                      label: executionModel,
                                      icon: Icons.memory_rounded,
                                      color: ForgePalette.primaryAccent,
                                    ),
                                  if (contextPlannerProvider.isNotEmpty)
                                    ForgePill(
                                      label: 'Context: $contextPlannerProvider',
                                      icon: Icons.travel_explore_rounded,
                                      color: ForgePalette.warning,
                                    ),
                                  if (executionPlannerProvider.isNotEmpty)
                                    ForgePill(
                                      label: 'Planner: $executionPlannerProvider',
                                      icon: Icons.account_tree_rounded,
                                      color: ForgePalette.glowAccent,
                                    ),
                                ],
                              ),
                              if (executionProviderReason.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  executionProviderReason,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (toolRegistrySummary.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  toolRegistrySummary,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: ForgePalette.textSecondary,
                                      ),
                                ),
                              ],
                              if (toolExecutions.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'Recent tool executions',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: 8),
                                ...toolExecutions.map(
                                  (tool) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      '${tool.label}: ${tool.summary}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: tool.status == 'failed'
                                                ? ForgePalette.error
                                                : ForgePalette.textSecondary,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (executionProvider.isNotEmpty ||
                          executionModel.isNotEmpty ||
                          toolRegistrySummary.isNotEmpty ||
                          toolExecutions.isNotEmpty ||
                          contextPlannerProvider.isNotEmpty ||
                          executionPlannerProvider.isNotEmpty)
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
                            if (validationAttemptCount > 0 ||
                                validationSummary.isNotEmpty ||
                                (latestValidationBranch ?? '').trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (validationAttemptCount > 0)
                                      ForgePill(
                                        label:
                                            '$validationAttemptCount validation pass${validationAttemptCount == 1 ? '' : 'es'}',
                                        icon: Icons.rule_folder_rounded,
                                        color: ForgePalette.primaryAccent,
                                      ),
                                    if ((latestValidationBranch ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      ForgePill(
                                        label: latestValidationBranch!.trim(),
                                        icon: Icons.alt_route_rounded,
                                        color: ForgePalette.warning,
                                      ),
                                  ],
                                ),
                              ),
                            if (validationSummary.isNotEmpty) ...[
                              Text(
                                validationSummary,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (repairTargetPaths.isNotEmpty ||
                                failureCategory.isNotEmpty ||
                                failureLocations.isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: ForgePalette.surfaceElevated,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: ForgePalette.warning.withValues(
                                      alpha: 0.24,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Current repair focus',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    if (failureCategory.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Failure type: $failureCategory',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                    if (repairTargetPaths.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Targeting: ${repairTargetPaths.take(6).join(', ')}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color:
                                                  ForgePalette.textSecondary,
                                            ),
                                      ),
                                    ],
                                    if (failureLocations.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      ...failureLocations.take(4).map(
                                        (item) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 6,
                                          ),
                                          child: Text(
                                            item,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      ForgePalette.textMuted,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (validationHistory.isNotEmpty) ...[
                              Text(
                                'Recent validation passes',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 8),
                              ...validationHistory.map(
                                (entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'Pass ${entry.attempt}: ${entry.summary}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: entry.passed
                                              ? ForgePalette.textSecondary
                                              : ForgePalette.error,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (latestValidationResults.isNotEmpty) ...[
                              ...latestValidationResults.map(
                                (result) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: ForgePalette.surfaceElevated,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: _validationColor(result.status)
                                            .withValues(alpha: 0.28),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              result.name,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                            ForgePill(
                                              label: _validationStatusLabel(
                                                result.status,
                                              ),
                                              icon: result.status == 'passed'
                                                  ? Icons.check_circle_rounded
                                                  : result.status == 'skipped'
                                                      ? Icons.remove_circle_outline_rounded
                                                      : Icons.error_rounded,
                                              color: _validationColor(
                                                result.status,
                                              ),
                                            ),
                                            if ((result.workflowCategory ?? '')
                                                .trim()
                                                .isNotEmpty)
                                              ForgePill(
                                                label:
                                                    result.workflowCategory!
                                                        .trim(),
                                                icon: Icons.tune_rounded,
                                                color: ForgePalette
                                                    .glowAccent,
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          result.summary,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        if (result.findings.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          ...result.findings.map(
                                            (finding) => Padding(
                                              padding:
                                                  const EdgeInsets.only(
                                                    bottom: 6,
                                                  ),
                                              child: Text(
                                                finding,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: ForgePalette
                                                          .textSecondary,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        if ((result.logsUrl ?? '')
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          SelectableText(
                                            result.logsUrl!.trim(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: ForgePalette
                                                      .glowAccent,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if ((task.latestValidationError ?? '')
                                .trim()
                                .isEmpty)
                              Text(
                                task.status == ForgeAgentTaskStatus.failed &&
                                        latestValidationResults.isEmpty
                                    ? 'No validation metadata was captured for this failure.'
                                    : latestValidationResults.isEmpty
                                        ? 'No validation failures were recorded for this task.'
                                        : 'The latest validation run did not record a blocking failure.',
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
                      // ── Live stream log ──────────────────────────────
                      if (task != null &&
                          task.isActive &&
                          widget.controller.currentOwnerId != null) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: StreamLogWidget(
                            ownerId: widget.controller.currentOwnerId!,
                            taskId: task.id,
                          ),
                        ),
                      ],
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

class _ValidationToolView {
  const _ValidationToolView({
    required this.name,
    required this.status,
    required this.summary,
    required this.findings,
    this.workflowCategory,
    this.logsUrl,
  });

  final String name;
  final String status;
  final String summary;
  final List<String> findings;
  final String? workflowCategory;
  final String? logsUrl;
}

class _ToolExecutionView {
  const _ToolExecutionView({
    required this.label,
    required this.status,
    required this.summary,
  });

  final String label;
  final String status;
  final String summary;
}

class _ValidationHistoryView {
  const _ValidationHistoryView({
    required this.attempt,
    required this.passed,
    required this.summary,
  });

  final int attempt;
  final bool passed;
  final String summary;
}

List<_ToolExecutionView> _toolExecutionsFromMetadata(
  Map<String, dynamic> metadata,
) {
  final raw = metadata['toolExecutions'];
  if (raw is! List) {
    return const <_ToolExecutionView>[];
  }
  return raw
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry('$key', value)))
      .map(
        (item) => _ToolExecutionView(
          label: (item['label'] as String?) ?? 'Agent tool',
          status: (item['status'] as String?) ?? 'passed',
          summary:
              (item['summary'] as String?) ??
              'This tool executed during the run.',
        ),
      )
      .toList()
      .reversed
      .take(5)
      .toList();
}

List<_ValidationToolView> _validationResultsFromMetadata(
  Map<String, dynamic> metadata,
) {
  final raw = metadata['latestValidationToolResults'];
  if (raw is! List) {
    return const <_ValidationToolView>[];
  }
  return raw
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry('$key', value)))
      .map(
        (item) => _ValidationToolView(
          name: (item['name'] as String?) ?? 'Validation tool',
          status: (item['status'] as String?) ?? 'skipped',
          summary:
              (item['summary'] as String?) ??
              'Validation metadata is available for this step.',
          workflowCategory: item['workflowCategory'] as String?,
          logsUrl: item['logsUrl'] as String?,
          findings: (item['findings'] as List? ?? const <dynamic>[])
              .whereType<Map>()
              .map((finding) {
                final filePath = finding['filePath'] as String?;
                final line = finding['line'] as num?;
                final message = (finding['message'] as String?)?.trim() ?? '';
                if (message.isEmpty) {
                  return '';
                }
                final prefix = (filePath ?? '').trim().isEmpty
                    ? ''
                    : '${filePath!.trim()}${line != null ? ':${line.toInt()}' : ''} ';
                return '$prefix$message'.trim();
              })
              .where((item) => item.isNotEmpty)
              .take(4)
              .toList(),
        ),
      )
      .toList();
}

List<_ValidationHistoryView> _validationHistoryFromMetadata(
  Map<String, dynamic> metadata,
) {
  final raw = metadata['validationHistory'];
  if (raw is! List) {
    return const <_ValidationHistoryView>[];
  }
  return raw
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry('$key', value)))
      .map(
        (item) => _ValidationHistoryView(
          attempt: (item['attempt'] as num?)?.toInt() ?? 0,
          passed: item['passed'] == true,
          summary:
              (item['summary'] as String?) ??
              'Validation metadata was recorded for this pass.',
        ),
      )
      .where((item) => item.attempt > 0)
      .toList()
      .reversed
      .take(4)
      .toList();
}

String _validationStatusLabel(String status) {
  switch (status) {
    case 'passed':
      return 'Passed';
    case 'failed':
      return 'Failed';
    case 'timed_out':
      return 'Timed out';
    default:
      return 'Skipped';
  }
}

Color _validationColor(String status) {
  switch (status) {
    case 'passed':
      return ForgePalette.success;
    case 'failed':
    case 'timed_out':
      return ForgePalette.error;
    default:
      return ForgePalette.textMuted;
  }
}
