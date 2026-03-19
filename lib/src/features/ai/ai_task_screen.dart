import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../diff/diff_review_screen.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';

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
        final session = state.currentExecutionSession;
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
                        title: 'Repo-aware execution',
                        subtitle:
                            'Describe the real repository change you want. The agent will retrieve relevant files, prepare a multi-file diff, and wait for approval before anything is applied. Wallet: $balance tokens.',
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
                          labelText: 'What should change?',
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
                                  ? 'Generating...'
                                  : 'Generate repo diff',
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
                      Text(
                        '~$estimate tokens estimated • ${state.repoExecutionDeepMode ? 'deep mode loads more files' : 'normal mode stays fast'} • review before apply/commit',
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
                        'Prepared execution',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (session == null)
                        const ForgeCodeBlock(
                          lines: [
                            'No execution session yet.',
                            'Describe the repo change you want, then generate a diff.',
                          ],
                        )
                      else ...[
                        Text(
                          session.summary,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ForgePill(
                              label: '${session.edits.length} files',
                              icon: Icons.description_rounded,
                            ),
                            ForgePill(
                              label: session.isDeepMode ? 'Deep mode' : 'Normal mode',
                              icon: Icons.tune_rounded,
                            ),
                            ForgePill(
                              label: '${session.estimatedTokens} tokens',
                              icon: Icons.token_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ForgeCodeBlock(
                          lines: [
                            'Files prepared for review:',
                            ...session.edits.map(
                              (edit) => '- ${edit.action.toUpperCase()} ${edit.path}',
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
        );
      },
    );
  }

  Future<void> _runAi(BuildContext context) async {
    try {
      await widget.controller.runAiAction(
        prompt: _promptController.text.trim(),
        provider: ForgeAiProvider.openai,
      );
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DiffReviewScreen(controller: widget.controller),
        ),
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
