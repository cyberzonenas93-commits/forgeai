import 'package:flutter/material.dart';

import '../../shared/forge_models.dart';
import '../../shared/widgets/forge_widgets.dart';

class RepositoryBrowserScreen extends StatelessWidget {
  const RepositoryBrowserScreen({
    super.key,
    this.files = const [],
    this.onOpenFile,
    this.onSync,
    this.isSyncing = false,
  });

  final List<ForgeFileNode> files;
  final ValueChanged<ForgeFileNode>? onOpenFile;
  final VoidCallback? onSync;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ForgeSectionHeader(
                  title: 'File tree',
                  subtitle: files.isEmpty
                      ? 'Sync the repository to load files, then tap one to open in the Editor.'
                      : 'Open a file to edit, diff, or hand off to AI.',
                  trailing: const ForgePill(
                    label: 'Review-first',
                    icon: Icons.visibility_rounded,
                  ),
                ),
              ),
              if (onSync != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ForgeSecondaryButton(
                    label: isSyncing ? 'Syncing...' : 'Sync',
                    icon: Icons.sync_rounded,
                    onPressed: isSyncing ? null : onSync,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  onSync != null
                      ? 'No files yet. Tap Sync to load the file tree from your repo.'
                      : 'Select a repository to see the file tree.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            for (final node in files) ..._buildNodes(node),
        ],
      ),
    );
  }

  List<Widget> _buildNodes(ForgeFileNode node, {double indent = 0}) {
    return [
      _FileNodeTile(file: node, indent: indent, onOpenFile: onOpenFile),
      if (node.isFolder)
        for (final child in node.children)
          ..._buildNodes(child, indent: indent + 18),
    ];
  }
}

class _FileNodeTile extends StatelessWidget {
  const _FileNodeTile({required this.file, this.indent = 0, this.onOpenFile});

  final ForgeFileNode file;
  final double indent;
  final ValueChanged<ForgeFileNode>? onOpenFile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 8),
      child: ForgePanel(
        onTap: file.isFolder ? null : () => onOpenFile?.call(file),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        backgroundColor: file.isSelected ? const Color(0xFF182235) : null,
        highlight: file.isSelected,
        child: Row(
          children: [
            Icon(
              file.isFolder
                  ? Icons.folder_copy_rounded
                  : Icons.description_rounded,
              color: file.isFolder ? const Color(0xFF60A5FA) : Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    file.isFolder
                        ? '${file.children.length} items'
                        : '${file.language} • ${file.sizeLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              file.changeLabel,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}
