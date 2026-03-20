import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';

class SuccessStateCard extends StatelessWidget {
  const SuccessStateCard({
    super.key,
    required this.task,
    this.onViewDiff,
    required this.onOpenDetails,
  });

  final ForgeAgentTask task;
  final VoidCallback? onViewDiff;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      highlight: true,
      backgroundColor: ForgePalette.success.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ForgePalette.success.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: ForgePalette.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Run complete',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.currentStep,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.success,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            (task.resultSummary ?? task.executionSummary ?? 'The agent completed the requested work.').trim(),
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
                label: '${task.filesTouched.length} files changed',
                icon: Icons.description_rounded,
                color: ForgePalette.success,
              ),
              ForgePill(
                label: '${task.diffCount} diffs',
                icon: Icons.compare_arrows_rounded,
                color: ForgePalette.primaryAccent,
              ),
              if (task.metadata['branchName'] is String)
                ForgePill(
                  label: task.metadata['branchName'] as String,
                  icon: Icons.call_split_rounded,
                  color: ForgePalette.warning,
                ),
              if (task.metadata['pullRequestNumber'] != null)
                ForgePill(
                  label: 'PR #${task.metadata['pullRequestNumber']}',
                  icon: Icons.merge_type_rounded,
                  color: ForgePalette.glowAccent,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if ((task.resultSummary ?? task.executionSummary ?? '').trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ForgePalette.surfaceElevated.withValues(alpha: 0.46),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: ForgePalette.border.withValues(alpha: 0.7),
                ),
              ),
              child: Text(
                (task.resultSummary ?? task.executionSummary ?? '').trim(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ForgePalette.textSecondary,
                    ),
              ),
            ),
          if ((task.resultSummary ?? task.executionSummary ?? '').trim().isNotEmpty)
            const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (onViewDiff != null)
                ForgePrimaryButton(
                  label: 'Diff',
                  icon: Icons.compare_arrows_rounded,
                  onPressed: onViewDiff,
                ),
              ForgeSecondaryButton(
                label: 'Details',
                icon: Icons.receipt_long_rounded,
                onPressed: onOpenDetails,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
