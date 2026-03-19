import 'package:flutter/material.dart';

import '../../core/theme/forge_palette.dart';
import '../../shared/forge_models.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import 'repository_browser_screen.dart';
import 'repository_connection_screen.dart';

class RepositoriesScreen extends StatefulWidget {
  const RepositoriesScreen({
    super.key,
    required this.controller,
    this.onOpenFile,
  });

  final ForgeWorkspaceController controller;
  final ValueChanged<ForgeFileNode>? onOpenFile;

  @override
  State<RepositoriesScreen> createState() => _RepositoriesScreenState();
}

class _RepositoriesScreenState extends State<RepositoriesScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final repositories = state.repositories;
        final connections = state.connections;
        final selectedRepository = state.selectedRepository;
        final selectedBranch = state.selectedBranch ?? 'main';

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                ForgePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ForgeSectionHeader(
                        title: 'Repository',
                        subtitle:
                            'Browse branches, inspect the tree, and open files in a mobile-friendly review flow.',
                      ),
                      const SizedBox(height: 16),
                      if (repositories.isEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connections.isEmpty
                                  ? 'No repositories connected'
                                  : 'No repository selected yet',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              connections.isEmpty
                                  ? 'Connect GitHub or GitLab to sync a real repository into ForgeAI. GitHub sign-in can now authorize GitHub repos automatically.'
                                  : 'Your provider connection is ready. Choose one of your available repositories to connect into ForgeAI.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            ForgePrimaryButton(
                              label: 'Connect repository',
                              icon: Icons.link_rounded,
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RepositoryConnectionScreen(
                                      controller: widget.controller,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        )
                      else
                        SizedBox(
                          height: 136,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: repositories.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final repository = repositories[index];
                              final selected =
                                  selectedRepository?.id == repository.id;
                              return SizedBox(
                                width: 270,
                                height: 136,
                                child: ForgePanel(
                                  onTap: () => widget.controller
                                      .selectRepository(repository),
                                  highlight: selected,
                                  backgroundColor: selected
                                      ? const Color(0xFF152033)
                                      : null,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: ForgePill(
                                                label: repository.providerLabel,
                                                icon:
                                                    repository.provider ==
                                                        ForgeProvider.github
                                                    ? Icons.code_rounded
                                                    : Icons.merge_rounded,
                                                color:
                                                    repository.provider ==
                                                        ForgeProvider.github
                                                    ? ForgePalette.glowAccent
                                                    : ForgePalette.warning,
                                              ),
                                            ),
                                            const Spacer(),
                                            if (selected)
                                              const Icon(
                                                Icons.check_circle_rounded,
                                                color: ForgePalette.glowAccent,
                                                size: 18,
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          repository.repoLabel,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          repository.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ForgePanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Branch selector',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: selectedBranch,
                              isExpanded: true,
                              items: [
                                DropdownMenuItem(
                                  value:
                                      selectedRepository?.defaultBranch ??
                                      'main',
                                  child: Text(
                                    selectedRepository?.defaultBranch ?? 'main',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                if ((selectedRepository?.defaultBranch ??
                                        'main') !=
                                    'feature/mobile-review')
                                  const DropdownMenuItem(
                                    value: 'feature/mobile-review',
                                    child: Text(
                                      'feature/mobile-review',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                              ],
                              selectedItemBuilder: (context) {
                                final items = <String>[
                                  selectedRepository?.defaultBranch ?? 'main',
                                  if ((selectedRepository?.defaultBranch ??
                                          'main') !=
                                      'feature/mobile-review')
                                    'feature/mobile-review',
                                ];
                                return items
                                    .map((v) => Text(
                                          v,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ))
                                    .toList();
                              },
                              onChanged: (value) {
                                if (value != null) {
                                  widget.controller.selectBranch(value);
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            if (connections.isEmpty)
                              Text(
                                'No provider connections stored yet.',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: connections.map((connection) {
                                  return ForgePill(
                                    label: connection.account,
                                    color:
                                        connection.provider ==
                                            ForgeProvider.github
                                        ? ForgePalette.glowAccent
                                        : ForgePalette.warning,
                                    icon:
                                        connection.provider ==
                                            ForgeProvider.github
                                        ? Icons.code_rounded
                                        : Icons.merge_rounded,
                                  );
                                }).toList(),
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
                              'Workspace status',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            _StatusRow(
                              label: 'Default branch',
                              value:
                                  selectedRepository?.defaultBranch ??
                                  'Not set',
                            ),
                            _StatusRow(
                              label: 'Changed files',
                              value: '${selectedRepository?.changedFiles ?? 0}',
                            ),
                            _StatusRow(
                              label: 'Pull requests',
                              value:
                                  '${selectedRepository?.openPullRequests ?? 0}',
                            ),
                            _StatusRow(
                              label: 'Protection',
                              value: (selectedRepository?.isProtected ?? false)
                                  ? 'Enabled'
                                  : 'Open',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                RepositoryBrowserScreen(
                  files: state.files,
                  onOpenFile: (file) async {
                    try {
                      await widget.controller.openFile(file);
                      if (!context.mounted) return;
                      widget.onOpenFile?.call(file);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Could not open file: ${e.toString()}'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  },
                  onSync: selectedRepository != null
                      ? () async {
                          try {
                            await widget.controller.refreshSelectedRepository();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Repository synced. File tree updated.')),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Sync failed: ${e.toString()}'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      : null,
                  isSyncing: state.isSyncing,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.labelLarge,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
