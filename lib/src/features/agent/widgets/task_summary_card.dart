import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';

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

  @override
  Widget build(BuildContext context) {
    final summary = (task.executionSummary ?? '').trim().isNotEmpty
        ? task.executionSummary!.trim()
        : (task.resultSummary ?? '').trim().isNotEmpty
            ? task.resultSummary!.trim()
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
              ForgePill(
                label: 'Pass ${task.currentPass == 0 ? 1 : task.currentPass}',
                icon: Icons.repeat_rounded,
                color: ForgePalette.glowAccent,
              ),
              if (task.selectedFiles.isNotEmpty)
                ForgePill(
                  label: '${task.selectedFiles.length} selected',
                  icon: Icons.source_rounded,
                  color: ForgePalette.textSecondary,
                ),
              if (task.retryCount > 0)
                ForgePill(
                  label: '${task.retryCount} retries',
                  icon: Icons.refresh_rounded,
                  color: ForgePalette.warning,
                ),
            ],
          ),
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
