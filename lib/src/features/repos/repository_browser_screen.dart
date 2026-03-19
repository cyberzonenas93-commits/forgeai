import 'package:flutter/material.dart';

import '../../shared/forge_models.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../editor/widgets/forge_file_explorer.dart';

class RepositoryBrowserScreen extends StatelessWidget {
  const RepositoryBrowserScreen({
    super.key,
    this.files = const [],
    this.selectedPath,
    this.onOpenFile,
    this.onSync,
    this.isSyncing = false,
  });

  final List<ForgeFileNode> files;
  final String? selectedPath;
  final ValueChanged<ForgeFileNode>? onOpenFile;
  final VoidCallback? onSync;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ForgeSectionHeader(
            title: 'File tree',
            subtitle: files.isEmpty
                ? (onSync != null
                      ? 'Tap Sync to load files, then tap a file to open in the Code tab.'
                      : 'Select a repository above to browse files.')
                : 'Same explorer as Code. Search, expand folders, and open files.',
            trailing: onSync == null
                ? null
                : ForgeSecondaryButton(
                    label: isSyncing ? 'Syncing...' : 'Sync',
                    icon: Icons.sync_rounded,
                    onPressed: isSyncing ? null : onSync,
                  ),
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
          else if (onOpenFile != null)
            ForgeFileExplorer(
              roots: files,
              selectedPath: selectedPath,
              shrinkWrap: true,
              onFileSelected: onOpenFile!,
              emptyMessage:
                  'No files yet. Tap Sync to load the file tree from your repo.',
            ),
        ],
      ),
    );
  }
}
