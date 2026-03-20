import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';
import '../agent_ui_utils.dart';

class TaskSummaryCard extends StatelessWidget {
  const TaskSummaryCard({
    super.key,
    required this.task,
    this.onOpenDetails,
    this.onViewDiff,
  });

  final ForgeAgentTask task;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onViewDiff;

  String? _planSummary() {
    final value = task.metadata['planSummary'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  List<String> _plannedSteps() {
    final value = task.metadata['plannedSteps'];
    if (value is! List) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((step) => step.trim())
        .where((step) => step.isNotEmpty)
        .take(4)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final maxRetries = task.metadata['maxRetries'] is num
        ? (task.metadata['maxRetries'] as num).toInt()
        : null;
    final validationAttemptCount =
        task.metadata['validationAttemptCount'] is num
            ? (task.metadata['validationAttemptCount'] as num).toInt()
            : 0;
    final hardLimitReached = task.metadata['hardLimitReached'] == true;
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
    final executionProvider = task.metadata['executionProvider'] is String
        ? (task.metadata['executionProvider'] as String).trim()
        : '';
    final toolRegistryCount = task.metadata['toolRegistryCount'] is num
        ? (task.metadata['toolRegistryCount'] as num).toInt()
        : 0;
    final preApplyValidationPassed =
        task.metadata['preApplyValidationPassed'] == true;
    final hardLimitSummary = task.metadata['hardLimitSummary'] is String
        ? (task.metadata['hardLimitSummary'] as String).trim()
        : '';
    final planSummary = _planSummary();
    final plannedSteps = _plannedSteps();
    final summary = hardLimitSummary.isNotEmpty
        ? hardLimitSummary
        : (task.executionSummary ?? '').trim().isNotEmpty
        ? task.executionSummary!.trim()
        : (planSummary ?? '').isNotEmpty
            ? planSummary!
        : (task.resultSummary ?? '').trim().isNotEmpty
            ? task.resultSummary!.trim()
            : task.isQueued
                ? 'This run is queued with a plan and will begin as soon as the current workspace lock clears.'
                : 'The agent is preparing the next meaningful step for this workspace task.';
    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Session brief',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (onOpenDetails != null)
                TextButton.icon(
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.list_alt_rounded, size: 16),
                  label: const Text('Run log'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ForgePalette.surfaceElevated.withValues(alpha: 0.44),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: ForgePalette.border.withValues(alpha: 0.7),
              ),
            ),
            child: Text(
              summary,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ForgePill(
                label: task.deepMode ? 'Deep pass' : 'Normal pass',
                icon: task.deepMode
                    ? Icons.psychology_rounded
                    : Icons.flash_on_rounded,
                color: ForgePalette.primaryAccent,
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
              ForgePill(
                label: 'Pass ${task.currentPass == 0 ? 1 : task.currentPass}',
                icon: Icons.repeat_rounded,
                color: ForgePalette.glowAccent,
              ),
              if (task.selectedFiles.isNotEmpty)
                ForgePill(
                  label: '${task.selectedFiles.length} editable wave',
                  icon: Icons.source_rounded,
                  color: ForgePalette.textSecondary,
                ),
              if (task.inspectedFiles.isNotEmpty)
                ForgePill(
                  label: '${task.inspectedFiles.length} inspected',
                  icon: Icons.travel_explore_rounded,
                  color: ForgePalette.sparkAccent,
                ),
              if (task.dependencyFiles.isNotEmpty)
                ForgePill(
                  label: '${task.dependencyFiles.length} dependencies',
                  icon: Icons.account_tree_rounded,
                  color: ForgePalette.textSecondary,
                ),
              if (task.retryCount > 0)
                ForgePill(
                  label: maxRetries != null
                      ? '${task.retryCount}/$maxRetries repair passes'
                      : '${task.retryCount} retries',
                  icon: Icons.refresh_rounded,
                  color: ForgePalette.warning,
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
              if (validationAttemptCount > 0)
                ForgePill(
                  label:
                      '$validationAttemptCount validation pass${validationAttemptCount == 1 ? '' : 'es'}',
                  icon: Icons.rule_folder_rounded,
                  color: ForgePalette.warning,
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
              if (task.followUpPlan.openPullRequest)
                ForgePill(
                  label: task.followUpPlan.mergePullRequest
                      ? 'PR + merge planned'
                      : 'PR planned',
                  icon: Icons.merge_type_rounded,
                  color: ForgePalette.success,
                )
              else if (task.followUpPlan.commitChanges)
                ForgePill(
                  label: 'Commit planned',
                  icon: Icons.commit_rounded,
                  color: ForgePalette.success,
                ),
              if (task.followUpPlan.deployWorkflow)
                ForgePill(
                  label: 'Deploy planned',
                  icon: Icons.rocket_launch_rounded,
                  color: ForgePalette.glowAccent,
                ),
            ],
          ),
          if (plannedSteps.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Run plan',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            ...plannedSteps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '• $step',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
          if (onViewDiff != null && task.sessionId != null) ...[
            const SizedBox(height: 16),
            ForgeSecondaryButton(
              label: 'Open diff',
              icon: Icons.compare_arrows_rounded,
              onPressed: onViewDiff,
              expanded: true,
            ),
          ],
        ],
      ),
    );
  }
}
