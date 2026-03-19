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
        final logs = selectedJob == null
            ? const <String>[
                'No CI logs yet.',
                'Connect a repository and run checks to see workflow output here.',
              ]
            : <String>[
                '[$kAppDisplayName] ${selectedJob.name}',
                '[Status] ${selectedJob.summary}',
                '[Duration] ${selectedJob.duration}',
                if (selectedJob.logsAvailable)
                  '[Logs] Provider log output available through backend sync.'
                else
                  '[Logs] No logs published yet.',
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
                            'Run tests, build, and lint through CI only. GitHub repos need a workflow in .github/workflows/ (e.g. ci.yml) with workflow_dispatch.',
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
                        selectedJob?.name ?? 'Live logs',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      const ForgePill(
                        label: 'Live logs',
                        icon: Icons.subject_rounded,
                        color: ForgePalette.glowAccent,
                      ),
                      const SizedBox(height: 12),
                      ForgeCodeBlock(lines: logs),
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
        const SnackBar(content: Text('Check queued successfully.')),
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
