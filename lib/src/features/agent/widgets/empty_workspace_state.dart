import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';

class EmptyWorkspaceState extends StatelessWidget {
  const EmptyWorkspaceState({
    super.key,
    required this.repoLabel,
    required this.onUsePrompt,
  });

  final String? repoLabel;
  final ValueChanged<String> onUsePrompt;

  static const List<String> _examples = [
    'Fix the login flow',
    'Add onboarding screen',
    'Refactor repository service',
  ];

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            repoLabel == null ? 'No workspace selected' : 'Start a live work session',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            repoLabel == null
                ? 'Select a repository to start a live run. Once selected, new requests become queued workspace runs with live execution updates.'
                : 'Kick off a coding run and watch the agent inspect files, generate diffs, retry when needed, and pause for approval before writes.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ForgePalette.textSecondary,
                ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _examples
                .map(
                  (example) => ActionChip(
                    avatar: const Icon(Icons.keyboard_command_key_rounded, size: 16),
                    label: Text(example),
                    onPressed: repoLabel == null ? null : () => onUsePrompt(example),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
