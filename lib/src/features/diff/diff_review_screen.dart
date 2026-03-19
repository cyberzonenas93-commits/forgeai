import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';

class DiffReviewScreen extends StatelessWidget {
  const DiffReviewScreen({super.key, required this.controller});

  final ForgeWorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final change = state.currentChangeRequest;
        final before = change?.beforeContent.split('\n') ?? const <String>[];
        final after = change?.afterContent.split('\n') ?? const <String>[];

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
                      const ForgeSectionHeader(
                        title: 'Diff review',
                        subtitle:
                            'Approve or reject every code change before it becomes a commit.',
                      ),
                      const SizedBox(height: 16),
                      if (change == null)
                        Text(
                          'No AI-generated diff is waiting for review.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: ForgeSecondaryButton(
                                label: 'Reject',
                                icon: Icons.close_rounded,
                                onPressed: () => _reject(context),
                                expanded: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ForgeSecondaryButton(
                                label: 'Edit',
                                icon: Icons.edit_rounded,
                                onPressed: () => Navigator.of(context).pop(),
                                expanded: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ForgePrimaryButton(
                                label: 'Approve',
                                icon: Icons.check_rounded,
                                onPressed: () => _approve(context),
                                expanded: true,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (change != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ForgePanel(
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
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ForgePanel(
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
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ForgePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Line-by-line',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        ...change.diffLines.map(
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
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _approve(BuildContext context) async {
    try {
      await controller.approveCurrentChange();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diff approved and applied to the draft.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _reject(BuildContext context) async {
    try {
      await controller.rejectCurrentChange();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Changes sent back for edit.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
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
