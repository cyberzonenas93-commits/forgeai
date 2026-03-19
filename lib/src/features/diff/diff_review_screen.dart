import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';

class DiffReviewScreen extends StatelessWidget {
  const DiffReviewScreen({super.key, required this.controller});

  final ForgeWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final execution = state.currentExecutionSession;
        final change = state.currentChangeRequest;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                ForgePanel(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ForgeSectionHeader(
                        title: execution != null
                            ? 'Repo execution review'
                            : 'Diff review',
                        subtitle: execution != null
                            ? 'Inspect each prepared file change before it is applied to the working copy.'
                            : 'Approve or reject every code change before it becomes a commit.',
                      ),
                      const SizedBox(height: 16),
                      if (execution == null && change == null)
                        Text(
                          'No AI-generated diff is waiting for review.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else ...[
                        if (execution != null) ...[
                          Text(
                            execution.summary,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ForgePill(
                                label: '${execution.edits.length} files',
                                icon: Icons.description_rounded,
                              ),
                              ForgePill(
                                label: execution.isDeepMode
                                    ? 'Deep mode'
                                    : 'Normal mode',
                                icon: Icons.tune_rounded,
                              ),
                              ForgePill(
                                label: '${execution.estimatedTokens} tokens',
                                icon: Icons.token_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        ForgeSecondaryButton(
                          label: 'Reject',
                          icon: Icons.close_rounded,
                          onPressed: () => _reject(context),
                          expanded: true,
                        ),
                        const SizedBox(height: 10),
                        ForgeSecondaryButton(
                          label: 'Edit',
                          icon: Icons.edit_rounded,
                          onPressed: () => Navigator.of(context).pop(),
                          expanded: true,
                        ),
                        const SizedBox(height: 10),
                        ForgePrimaryButton(
                          label: 'Approve',
                          icon: Icons.check_rounded,
                          onPressed: () => _approve(context),
                          expanded: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (execution != null) ...[
                  if (execution.selectedFiles.isNotEmpty)
                    ForgePanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Retrieved files',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: execution.selectedFiles
                                .map(
                                  (path) => ForgePill(
                                    label: path,
                                    icon: Icons.insert_drive_file_rounded,
                                  ),
                                )
                                .toList(),
                          ),
                          if (execution.steps.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Execution steps',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            ...execution.steps.map(
                              (step) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '• $step',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (execution.selectedFiles.isNotEmpty)
                    const SizedBox(height: 16),
                  ...execution.edits.map(
                    (edit) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ExecutionEditPanel(edit: edit),
                    ),
                  ),
                ] else if (change != null) ...[
                  _SingleChangePanel(change: change),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _approve(BuildContext context) async {
    final hadExecution = controller.value.currentExecutionSession != null;
    try {
      if (hadExecution) {
        await controller.approveCurrentExecution();
      } else {
        await controller.approveCurrentChange();
      }
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hadExecution
                ? 'Repo changes applied to the working copy.'
                : 'Diff approved and applied to the draft.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(forgeUserFriendlyMessage(error))));
    }
  }

  Future<void> _reject(BuildContext context) async {
    final hadExecution = controller.value.currentExecutionSession != null;
    try {
      if (hadExecution) {
        await controller.rejectCurrentExecution();
      } else {
        await controller.rejectCurrentChange();
      }
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hadExecution
                ? 'Repo execution discarded.'
                : 'Changes sent back for edit.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(forgeUserFriendlyMessage(error))));
    }
  }
}

class _SingleChangePanel extends StatelessWidget {
  const _SingleChangePanel({required this.change});

  final ForgeChangeRequest change;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CodeComparison(
          beforeContent: change.beforeContent,
          afterContent: change.afterContent,
        ),
        const SizedBox(height: 16),
        _DiffLinesPanel(lines: change.diffLines),
      ],
    );
  }
}

class _ExecutionEditPanel extends StatelessWidget {
  const _ExecutionEditPanel({required this.edit});

  final ForgeRepoExecutionFileChange edit;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                edit.path,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ForgePill(
                label: edit.action.toUpperCase(),
                icon: edit.action == 'create'
                    ? Icons.add_rounded
                    : edit.action == 'delete'
                        ? Icons.delete_outline_rounded
                        : Icons.edit_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            edit.summary,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _CodeComparison(
            beforeContent: edit.beforeContent,
            afterContent: edit.afterContent,
          ),
          if (edit.diffLines.isNotEmpty) ...[
            const SizedBox(height: 16),
            _DiffLinesPanel(lines: edit.diffLines),
          ],
        ],
      ),
    );
  }
}

class _CodeComparison extends StatelessWidget {
  const _CodeComparison({
    required this.beforeContent,
    required this.afterContent,
  });

  final String beforeContent;
  final String afterContent;

  @override
  Widget build(BuildContext context) {
    final before = beforeContent.split('\n');
    final after = afterContent.split('\n');
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackPanels = constraints.maxWidth < 900;
        final beforePanel = ForgePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Before',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ForgeCodeBlock(
                lines: before,
                lineColors: List<Color?>.filled(
                  before.length,
                  ForgePalette.error.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        );
        final afterPanel = ForgePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'After',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ForgeCodeBlock(
                lines: after,
                lineColors: List<Color?>.filled(
                  after.length,
                  ForgePalette.success.withValues(alpha: 0.94),
                ),
              ),
            ],
          ),
        );
        if (stackPanels) {
          return Column(
            children: [
              beforePanel,
              const SizedBox(height: 12),
              afterPanel,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: beforePanel),
            const SizedBox(width: 12),
            Expanded(child: afterPanel),
          ],
        );
      },
    );
  }
}

class _DiffLinesPanel extends StatelessWidget {
  const _DiffLinesPanel({required this.lines});

  final List<ForgeDiffLine> lines;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Line-by-line',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DiffLine(
                prefix: line.prefix,
                line: line.line,
                color: line.isAddition
                    ? ForgePalette.success
                    : ForgePalette.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.prefix,
    required this.line,
    required this.color,
  });

  final String prefix;
  final String line;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$prefix $line',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: color, fontFamily: 'monospace'),
      ),
    );
  }
}
