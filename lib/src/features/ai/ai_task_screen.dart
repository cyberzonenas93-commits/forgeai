import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';

class AiTaskScreen extends StatefulWidget {
  const AiTaskScreen({super.key, required this.controller});

  final ForgeWorkspaceController controller;

  @override
  State<AiTaskScreen> createState() => _AiTaskScreenState();
}

class _AiTaskScreenState extends State<AiTaskScreen> {
  final TextEditingController _promptController = TextEditingController();

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final estimate = (_promptController.text.length / 3).ceil() +
            (state.repoExecutionDeepMode ? 420 : 240);
        final task = state.selectedAgentTask;
        final selectedRepoId = state.selectedRepository?.id;
        final hasActiveRun = state.agentTasks.any(
          (item) => item.repoId == selectedRepoId && item.isActive,
        );
        final balance = state.wallet.balance.toInt();
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: ListView(
              children: [
                ForgePanel(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ForgeSectionHeader(
                        title: 'Repo-aware run',
                        subtitle:
                            'Start a durable repo work session from the editor. The agent will inspect the repo, edit files, validate, repair, and queue behind any active run. Wallet: $balance tokens.',
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<bool>(
                        segments: const <ButtonSegment<bool>>[
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('Normal'),
                            icon: Icon(Icons.flash_on_rounded),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Deep'),
                            icon: Icon(Icons.psychology_rounded),
                          ),
                        ],
                        selected: <bool>{state.repoExecutionDeepMode},
                        onSelectionChanged: (selection) {
                          widget.controller.setRepoExecutionDeepMode(
                            selection.contains(true),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _promptController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'What should this run do?',
                          hintText:
                              'e.g. add authentication to this app, wire Git commit staging, or refactor repository retrieval',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ForgePrimaryButton(
                              label: state.isRunningAi
                                  ? 'Submitting...'
                                  : hasActiveRun
                                      ? 'Queue run'
                                      : 'Start run',
                              icon: Icons.auto_awesome_rounded,
                              onPressed: state.isRunningAi
                                  ? null
                                  : () => _runAi(context),
                              expanded: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (state.isRunningAi) const ForgeAiIndicator(),
                      if (hasActiveRun) ...[
                        const SizedBox(height: 10),
                        Text(
                          'A run is already active for this workspace. Submitting here adds another run to the queue.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.warning,
                          ),
                        ),
                      ],
                      Text(
                        '~$estimate tokens estimated • ${state.repoExecutionDeepMode ? 'deep mode widens repo reasoning and repair scope' : 'normal mode stays faster'} • approval is only required before apply/commit',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ForgePalette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ForgePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Run handoff',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (task == null)
                        const ForgeCodeBlock(
                          lines: [
                            'No run selected yet.',
                            'Start a repo run and follow the live agent work from the Agent tab.',
                          ],
                        )
                      else ...[
                        Text(
                          task.executionSummary ??
                              task.resultSummary ??
                              task.currentStep,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ForgePill(
                              label: '${task.filesTouched.length} files',
                              icon: Icons.description_rounded,
                            ),
                            ForgePill(
                              label: task.deepMode ? 'Deep mode' : 'Normal mode',
                              icon: Icons.tune_rounded,
                            ),
                            ForgePill(
                              label: '${task.estimatedTokens} tokens',
                              icon: Icons.token_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ForgeCodeBlock(
                          lines: [
                            'Run status:',
                            '- ${task.currentStep}',
                            if (task.selectedFiles.isNotEmpty)
                              'Current editable wave:',
                            ...task.selectedFiles
                                .take(8)
                                .map((path) => '- $path'),
                          ],
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

  Future<void> _runAi(BuildContext context) async {
    try {
      await widget.controller.runAiAction(
        prompt: _promptController.text.trim(),
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Run created. Track it from the Agent tab.'),
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
