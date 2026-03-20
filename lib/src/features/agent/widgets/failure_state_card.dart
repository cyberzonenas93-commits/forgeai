import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';

class FailureStateCard extends StatelessWidget {
  const FailureStateCard({
    super.key,
    required this.task,
    required this.onRetry,
    required this.onDuplicate,
    required this.onInspectLogs,
    required this.onDismiss,
  });

  final ForgeAgentTask task;
  final VoidCallback onRetry;
  final VoidCallback onDuplicate;
  final VoidCallback onInspectLogs;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final details =
        (task.errorMessage ?? task.latestValidationError ?? 'The run stopped before completion.')
            .trim();
    return ForgePanel(
      highlight: true,
      backgroundColor: ForgePalette.error.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ForgePalette.error.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: ForgePalette.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Run failed',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.currentStep,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.error,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ForgePill(
                label: task.currentStep,
                icon: Icons.track_changes_rounded,
                color: ForgePalette.error,
              ),
              ForgePill(
                label: '${task.diffCount} diffs',
                icon: Icons.compare_arrows_rounded,
                color: ForgePalette.primaryAccent,
              ),
              if (task.retryCount > 0)
                ForgePill(
                  label: '${task.retryCount} retries',
                  icon: Icons.refresh_rounded,
                  color: ForgePalette.warning,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            details,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ForgePalette.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ForgePrimaryButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
              ForgeSecondaryButton(
                label: 'Duplicate',
                icon: Icons.copy_rounded,
                onPressed: onDuplicate,
              ),
              ForgeSecondaryButton(
                label: 'Inspect logs',
                icon: Icons.receipt_long_rounded,
                onPressed: onInspectLogs,
              ),
              ForgeSecondaryButton(
                label: 'Dismiss',
                icon: Icons.close_rounded,
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Billing details are not streamed into run state yet.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ForgePalette.textMuted,
                ),
          ),
        ],
      ),
    );
  }
}
