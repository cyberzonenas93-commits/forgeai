import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';
import '../agent_ui_utils.dart';

class LiveEventRow extends StatelessWidget {
  const LiveEventRow({
    super.key,
    required this.event,
    this.isCurrent = false,
  });

  final ForgeAgentTaskEvent event;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final accent = _eventColor(event.type);
    final metadata = buildEventMetadata(event);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCurrent
            ? accent.withValues(alpha: 0.10)
            : ForgePalette.surfaceElevated.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent
              ? accent.withValues(alpha: 0.38)
              : ForgePalette.border.withValues(alpha: 0.7),
        ),
        boxShadow: [
          if (isCurrent)
            BoxShadow(
              color: accent.withValues(alpha: 0.18),
              blurRadius: 20,
              spreadRadius: -12,
              offset: const Offset(0, 14),
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isCurrent)
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.only(top: 8),
                  color: ForgePalette.border.withValues(alpha: 0.7),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.step,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatAbsoluteTime(event.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.textMuted,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  event.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isCurrent
                            ? ForgePalette.textPrimary
                            : ForgePalette.textSecondary,
                      ),
                ),
                if (metadata.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: metadata
                        .map(
                          (item) => ForgePill(
                            label: item,
                            icon: Icons.sell_outlined,
                            color: accent,
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
    );
  }
}

Color _eventColor(String type) {
  switch (type) {
    case 'task_failed':
    case 'validation_failed':
      return ForgePalette.error;
    case 'awaiting_approval':
      return ForgePalette.warning;
    case 'task_completed':
    case 'remote_action_completed':
      return ForgePalette.success;
    case 'retrying':
      return ForgePalette.emberAccent;
    case 'task_cancel_requested':
    case 'task_cancelled':
      return ForgePalette.textMuted;
    default:
      return ForgePalette.glowAccent;
  }
}
