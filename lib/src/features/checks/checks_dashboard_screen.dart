import 'package:flutter/material.dart';

import '../../core/branding/app_branding.dart';
import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';

class ChecksDashboardScreen extends StatefulWidget {
  const ChecksDashboardScreen({super.key, required this.controller});

  final ForgeWorkspaceController controller;

  @override
  State<ChecksDashboardScreen> createState() => _ChecksDashboardScreenState();
}

class _ChecksDashboardScreenState extends State<ChecksDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.loadRepoWorkflows();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final checks = state.checks;
        final selectedJob = checks.isEmpty ? null : checks.first;
        final detailLines = selectedJob == null
            ? const <String>[
                'No validation runs yet.',
                'Manual checks and agent-run validations will appear here once a repository is connected.',
              ]
            : <String>[
                '[$kAppDisplayName] ${selectedJob.name}',
                '[Status] ${selectedJob.summary}',
                '[Duration] ${selectedJob.duration}',
                if ((selectedJob.source ?? '').trim().isNotEmpty)
                  '[Source] ${selectedJob.source == 'agent_validation' ? 'Agent validation loop' : 'Manual check run'}',
                if ((selectedJob.workflowCategory ?? '').trim().isNotEmpty)
                  '[Category] ${selectedJob.workflowCategory}',
                if ((selectedJob.ref ?? '').trim().isNotEmpty)
                  '[Ref] ${selectedJob.ref}',
                if ((selectedJob.executionState ?? '').trim().isNotEmpty)
                  '[Execution] ${selectedJob.executionState}',
                if ((selectedJob.agentTaskId ?? '').trim().isNotEmpty)
                  '[Agent task] ${selectedJob.agentTaskId}',
                if (selectedJob.logsAvailable)
                  '[Signals] Findings or provider logs are available below.'
                else
                  '[Signals] No findings or provider logs published yet.',
              ];

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
                        title: 'Checks',
                        subtitle:
                            'Run manual CI checks and review agent-driven validation runs in one place. GitHub repos still need workflow_dispatch-enabled workflows in .github/workflows/.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ForgePrimaryButton(
                            label: state.isRunningCheck
                                ? 'Queueing...'
                                : 'Run tests',
                            icon: Icons.science_rounded,
                            onPressed: state.isRunningCheck
                                ? null
                                : () => _runCheck(
                                    context,
                                    widget.controller,
                                    ForgeCheckActionType.runTests,
                                  ),
                          ),
                          ForgeSecondaryButton(
                            label: 'Build project',
                            icon: Icons.rocket_launch_rounded,
                            onPressed: state.isRunningCheck
                                ? null
                                : () => _runCheck(
                                    context,
                                    widget.controller,
                                    ForgeCheckActionType.buildProject,
                                  ),
                          ),
                          ForgeSecondaryButton(
                            label: 'Lint code',
                            icon: Icons.rule_rounded,
                            onPressed: state.isRunningCheck
                                ? null
                                : () => _runCheck(
                                    context,
                                    widget.controller,
                                    ForgeCheckActionType.runLint,
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (checks.isEmpty)
                  const ForgePanel(
                    child: Text(
                      'No checks have been queued yet. Run a workflow from here after connecting a repository.',
                    ),
                  )
                else
                  ...checks.map(
                    (job) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ForgePanel(
                        highlight: selectedJob == job,
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: switch (job.status) {
                                  ForgeCheckStatus.passed =>
                                    ForgePalette.success,
                                  ForgeCheckStatus.running =>
                                    ForgePalette.glowAccent,
                                  ForgeCheckStatus.failed => ForgePalette.error,
                                  ForgeCheckStatus.queued =>
                                    ForgePalette.warning,
                                },
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: switch (job.status) {
                                      ForgeCheckStatus.passed =>
                                        ForgePalette.success.withValues(
                                          alpha: 0.4,
                                        ),
                                      ForgeCheckStatus.running =>
                                        ForgePalette.glowAccent.withValues(
                                          alpha: 0.4,
                                        ),
                                      ForgeCheckStatus.failed =>
                                        ForgePalette.error.withValues(
                                          alpha: 0.4,
                                        ),
                                      ForgeCheckStatus.queued =>
                                        ForgePalette.warning.withValues(
                                          alpha: 0.4,
                                        ),
                                    },
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    job.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${job.summary} • ${job.duration}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  if ((job.source ?? '').trim().isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ForgePill(
                                          label: job.source == 'agent_validation'
                                              ? 'Agent validation'
                                              : 'Manual check',
                                          icon: job.source == 'agent_validation'
                                              ? Icons.smart_toy_rounded
                                              : Icons.play_circle_outline_rounded,
                                          color: job.source == 'agent_validation'
                                              ? ForgePalette.glowAccent
                                              : ForgePalette.primaryAccent,
                                        ),
                                        if ((job.workflowCategory ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          ForgePill(
                                            label:
                                                job.workflowCategory!.trim(),
                                            icon: Icons.tune_rounded,
                                            color: ForgePalette.warning,
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                ForgePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedJob?.name ?? 'Validation details',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          const ForgePill(
                            label: 'Validation details',
                            icon: Icons.rule_folder_rounded,
                            color: ForgePalette.glowAccent,
                          ),
                          if ((selectedJob?.source ?? '').trim().isNotEmpty)
                            ForgePill(
                              label: selectedJob!.source == 'agent_validation'
                                  ? 'Agent-driven'
                                  : 'Manual',
                              icon: selectedJob.source == 'agent_validation'
                                  ? Icons.smart_toy_rounded
                                  : Icons.play_circle_outline_rounded,
                              color: ForgePalette.primaryAccent,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ForgeCodeBlock(lines: detailLines),
                      if ((selectedJob?.findings ?? const <String>[])
                          .isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Structured findings',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        ...selectedJob!.findings.take(6).map(
                              (finding) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  finding,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: ForgePalette.textSecondary,
                                      ),
                                ),
                              ),
                            ),
                      ],
                      if ((selectedJob?.logs ?? const <String>[]).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Provider signals',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        ForgeCodeBlock(lines: selectedJob!.logs.take(8).toList()),
                      ],
                      if ((selectedJob?.logsUrl ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          selectedJob!.logsUrl!.trim(),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: ForgePalette.glowAccent,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runCheck(
    BuildContext context,
    ForgeWorkspaceController controller,
    ForgeCheckActionType actionType,
  ) async {
    try {
      await controller.runCheck(actionType);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check started. Results will stream into the dashboard.')),
      );
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
