import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
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
        final estimate = (_promptController.text.length / 3).ceil() + 240;
        final changeRequest = state.currentChangeRequest;
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
                        title: 'Ask in plain language',
                        subtitle:
                            'Describe what you want in free-form English. The AI can rewrite the entire open file or draft full content for that path (including new files once the path is open). Tokens are charged when a suggestion is generated successfully. Wallet: $balance tokens.',
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _promptController,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'What should change?',
                          hintText:
                              'e.g. small edits, full rewrites, or "Scaffold a new widget in this file"',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ForgePrimaryButton(
                              label: state.isRunningAi
                                  ? 'Processing...'
                                  : 'Apply my instructions',
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
                        '~$estimate tokens estimated • charged on success • review the diff before committing',
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
                        'Suggested output',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (changeRequest == null)
                        const ForgeCodeBlock(
                          lines: [
                            'No suggestion yet.',
                            'Describe the change you want in plain English above, then tap Apply.',
                          ],
                        )
                      else
                        ForgeCodeBlock(
                          lines: changeRequest.afterContent.split('\n'),
                        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI change generated. Review the diff next.'),
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
