import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';
import '../agent_ui_utils.dart';

Future<void> showApprovalActionSheet({
  required BuildContext context,
  required ForgeAgentTask task,
  required String repoLabel,
  required bool isResolving,
  required VoidCallback onApprove,
  required VoidCallback onReject,
  VoidCallback? onReviewDiff,
}) {
  final approval = task.pendingApproval;
  if (approval == null) {
    return Future<void>.value();
  }
  return showModalBottomSheet<void>(
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ForgePalette.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: ForgePalette.warning.withValues(alpha: 0.26),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ForgePill(
                          label: 'Approval needed',
                          icon: Icons.pending_actions_rounded,
                          color: ForgePalette.warning,
                        ),
                        ForgePill(
                          label: approvalTypeLabel(approval.type),
                          icon: Icons.rule_folder_rounded,
                          color: ForgePalette.primaryAccent,
                        ),
                        ForgePill(
                          label: 'Workspace paused',
                          icon: Icons.pause_circle_filled_rounded,
                          color: ForgePalette.textSecondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      approval.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      approval.description,
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
                    color: ForgePalette.primaryAccent,
                  ),
                  ForgePill(
                    label: task.currentStep,
                    icon: Icons.track_changes_rounded,
                    color: ForgePalette.glowAccent,
                  ),
                  ForgePill(
                    label: '${task.filesTouched.length} files',
                    icon: Icons.description_rounded,
                    color: ForgePalette.warning,
                  ),
                  if (task.metadata['branchName'] is String)
                    ForgePill(
                      label: task.metadata['branchName'] as String,
                      icon: Icons.call_split_rounded,
                      color: ForgePalette.glowAccent,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (task.filesTouched.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ForgePalette.surfaceElevated.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: ForgePalette.border.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Files in scope',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: ForgePalette.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 10),
                      ...task.filesTouched.take(8).map(
                        (path) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            path,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (approval.type == ForgeAgentTaskApprovalType.applyChanges &&
                      onReviewDiff != null)
                    ForgeSecondaryButton(
                      label: 'Review changes',
                      icon: Icons.code_rounded,
                      onPressed: () {
                        Navigator.of(context).pop();
                        onReviewDiff();
                      },
                    ),
                  ForgePrimaryButton(
                    label: approval.actionLabel,
                    icon: Icons.check_rounded,
                    onPressed: isResolving
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            onApprove();
                          },
                  ),
                  ForgeSecondaryButton(
                    label: approval.type == ForgeAgentTaskApprovalType.applyChanges
                        ? 'Revise'
                        : approval.cancelLabel,
                    icon: Icons.close_rounded,
                    onPressed: isResolving
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            onReject();
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
