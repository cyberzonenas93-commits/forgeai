import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';
import '../agent_ui_utils.dart';
import 'task_status_chip.dart';

class QueueItemCard extends StatelessWidget {
  const QueueItemCard({
    super.key,
    required this.task,
    required this.position,
    required this.repoLabel,
    this.isSelected = false,
    this.onTap,
    this.onRemove,
  });

  final ForgeAgentTask task;
  final int position;
  final String repoLabel;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

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
        .take(2)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isNext = position == 1;
    final planSummary = _planSummary();
    final plannedSteps = _plannedSteps();
    final executionProvider = task.metadata['executionProvider'] is String
        ? (task.metadata['executionProvider'] as String).trim()
        : '';
    final toolRegistryCount = task.metadata['toolRegistryCount'] is num
        ? (task.metadata['toolRegistryCount'] as num).toInt()
        : 0;
    return ForgePanel(
      onTap: onTap,
      highlight: isNext,
      backgroundColor: isSelected
          ? ForgePalette.surfaceTint.withValues(alpha: 0.46)
          : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (isNext
                          ? ForgePalette.primaryAccent
                          : ForgePalette.surfaceElevated)
                      .withValues(alpha: isNext ? 0.16 : 0.84),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: (isNext
                            ? ForgePalette.primaryAccent
                            : ForgePalette.border)
                        .withValues(alpha: 0.8),
                  ),
                ),
                child: Text(
                  isNext ? 'Next' : '#$position',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: isNext
                            ? ForgePalette.primaryAccent
                            : ForgePalette.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: TaskStatusChip(task: task)),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove from queue',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isNext ? 'Next up when the active run clears.' : queueEtaLabel(position),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isNext
                      ? ForgePalette.primaryAccent
                      : ForgePalette.textSecondary,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            task.prompt,
            style: Theme.of(context).textTheme.bodyMedium,
            softWrap: true,
          ),
          if (planSummary != null) ...[
            const SizedBox(height: 10),
            Text(
              planSummary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ForgePalette.textSecondary,
                  ),
            ),
          ],
          const SizedBox(height: 12),
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
                label: formatRelativeTime(task.createdAt),
                icon: Icons.schedule_rounded,
                color: ForgePalette.textMuted,
              ),
              ForgePill(
                label: task.deepMode ? 'Deep mode' : 'Normal mode',
                icon: task.deepMode
                    ? Icons.psychology_rounded
                    : Icons.flash_on_rounded,
                color: ForgePalette.glowAccent,
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
              if (isSelected)
                ForgePill(
                  label: 'Focused',
                  icon: Icons.center_focus_strong_rounded,
                  color: ForgePalette.success,
                ),
            ],
          ),
          if (plannedSteps.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...plannedSteps.map(
              (step) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• $step',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ForgePalette.textSecondary,
                      ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
