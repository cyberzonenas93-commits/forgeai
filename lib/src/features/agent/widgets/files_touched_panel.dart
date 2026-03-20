import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';
import '../../workspace/domain/forge_workspace_entities.dart';
import '../agent_ui_utils.dart';

class FilesTouchedPanel extends StatelessWidget {
  const FilesTouchedPanel({
    super.key,
    required this.task,
    required this.events,
    this.session,
    this.onOpenFile,
  });

  final ForgeAgentTask task;
  final List<ForgeAgentTaskEvent> events;
  final ForgeRepoExecutionSession? session;
  final ValueChanged<String>? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final files = buildFileVisuals(
      task: task,
      session: session,
      events: events,
    );

    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Files touched',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'See what the agent inspected, modified, created, or queued for review.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ForgePalette.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              ForgePill(
                label: '${files.length} files',
                icon: Icons.folder_copy_rounded,
                color: ForgePalette.primaryAccent,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (files.isEmpty)
            Text(
              'No file activity has been recorded yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ForgePalette.textSecondary,
                  ),
            )
          else
            Column(
              children: files
                  .take(12)
                  .map(
                    (file) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _FileActivityRow(
                        file: file,
                        onTap: onOpenFile == null ? null : () => onOpenFile!(file.path),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _FileActivityRow extends StatelessWidget {
  const _FileActivityRow({
    required this.file,
    this.onTap,
  });

  final ForgeAgentFileVisual file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = fileStateColor(file.state);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: ForgePalette.surfaceElevated.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ForgePalette.border.withValues(alpha: 0.65)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  fileStateIcon(file.state),
                  size: 16,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.action == null ? file.label : '${file.label} • ${file.action}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: ForgePalette.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
