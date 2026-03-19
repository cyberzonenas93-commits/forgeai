import 'package:flutter/material.dart';

import '../../../core/theme/forge_palette.dart';
import '../../../shared/forge_models.dart';

/// Searchable tree for repository files with expandable folders.
class ForgeFileExplorer extends StatefulWidget {
  const ForgeFileExplorer({
    super.key,
    required this.roots,
    this.selectedPath,
    required this.onFileSelected,
    this.onCreateFileRequested,
    this.onCreateFolderRequested,
    this.onRenameRequested,
    this.onDeleteRequested,
    this.focusedFolderPath,
    this.emptyMessage = 'No files yet. Open the Repo tab and tap Sync.',
    this.shrinkWrap = false,
    this.showSearchField = true,
  });

  final List<ForgeFileNode> roots;
  final String? selectedPath;
  final ValueChanged<ForgeFileNode> onFileSelected;
  final ValueChanged<String?>? onCreateFileRequested;
  final ValueChanged<String?>? onCreateFolderRequested;
  final ValueChanged<ForgeFileNode>? onRenameRequested;
  final ValueChanged<ForgeFileNode>? onDeleteRequested;
  final String? focusedFolderPath;
  final String emptyMessage;

  /// When true, avoids [Expanded] so the explorer can live inside a parent
  /// [ScrollView] (e.g. Repo tab). Uses a shrink-wrapped list.
  final bool shrinkWrap;

  /// When false, only the tree is shown (search is omitted).
  final bool showSearchField;

  @override
  State<ForgeFileExplorer> createState() => _ForgeFileExplorerState();
}

class _ForgeFileExplorerState extends State<ForgeFileExplorer> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _expandShallow(widget.roots, 0);
  }

  @override
  void didUpdateWidget(covariant ForgeFileExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roots != widget.roots) {
      _expanded.clear();
      _expandShallow(widget.roots, 0);
    }
    if (oldWidget.focusedFolderPath != widget.focusedFolderPath &&
        (widget.focusedFolderPath?.trim().isNotEmpty ?? false)) {
      _focusFolder(widget.focusedFolderPath!);
    }
  }

  /// Expand the first few levels so common paths are visible without taps.
  void _expandShallow(List<ForgeFileNode> nodes, int depth) {
    if (depth > 2) {
      return;
    }
    for (final n in nodes) {
      if (n.isFolder) {
        _expanded.add(n.path);
        _expandShallow(n.children, depth + 1);
      }
    }
  }

  void _expandAll(List<ForgeFileNode> nodes) {
    for (final n in nodes) {
      if (n.isFolder) {
        _expanded.add(n.path);
        _expandAll(n.children);
      }
    }
  }

  void _focusFolder(String folderPath) {
    final segments = folderPath
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return;
    }
    setState(() {
      _search.clear();
      _expanded.clear();
      var current = '';
      for (final segment in segments) {
        current = current.isEmpty ? '$segment/' : '$current$segment/';
        _expanded.add(current);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ForgeFileNode> _filter(List<ForgeFileNode> nodes, String q) {
    if (q.isEmpty) {
      return nodes;
    }
    final ql = q.toLowerCase();
    final out = <ForgeFileNode>[];
    for (final n in nodes) {
      if (n.isFolder) {
        final kids = _filter(n.children, q);
        final match =
            n.name.toLowerCase().contains(ql) ||
            n.path.toLowerCase().contains(ql);
        if (kids.isNotEmpty || match) {
          out.add(
            ForgeFileNode(
              name: n.name,
              path: n.path,
              language: n.language,
              sizeLabel: n.sizeLabel,
              changeLabel: n.changeLabel,
              children: kids,
              isFolder: true,
            ),
          );
        }
      } else if (n.name.toLowerCase().contains(ql) ||
          n.path.toLowerCase().contains(ql)) {
        out.add(n);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim();
    final visible = _filter(widget.roots, q);

    final search = widget.showSearchField
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search files…',
                prefixIcon: const Icon(Icons.search_rounded, size: 22),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) {
                setState(() {
                  final next = v.trim();
                  if (next.isEmpty) {
                    _expanded.clear();
                    _expandShallow(widget.roots, 0);
                  } else {
                    _expanded.clear();
                    _expandAll(_filter(widget.roots, next));
                  }
                });
              },
            ),
          )
        : const SizedBox.shrink();

    final hasActions =
        widget.onCreateFileRequested != null ||
        widget.onCreateFolderRequested != null;
    final actions = hasActions
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.onCreateFileRequested != null)
                  TextButton.icon(
                    onPressed: () => widget.onCreateFileRequested!(null),
                    icon: const Icon(Icons.note_add_rounded, size: 18),
                    label: const Text('New file'),
                  ),
                if (widget.onCreateFolderRequested != null)
                  TextButton.icon(
                    onPressed: () => widget.onCreateFolderRequested!(null),
                    icon: const Icon(Icons.create_new_folder_rounded, size: 18),
                    label: const Text('New folder'),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final body = visible.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
            child: Center(
              child: Text(
                q.isEmpty ? widget.emptyMessage : 'No matches for "$q".',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        : ListView(
            shrinkWrap: widget.shrinkWrap,
            physics: widget.shrinkWrap
                ? const NeverScrollableScrollPhysics()
                : null,
            padding: const EdgeInsets.only(bottom: 24),
            children: [for (final n in visible) _nodeTile(context, n, 0)],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        search,
        actions,
        if (widget.shrinkWrap) body else Expanded(child: body),
      ],
    );
  }

  Widget _nodeTile(BuildContext context, ForgeFileNode n, int depth) {
    if (n.isFolder) {
      final open = _expanded.contains(n.path);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() {
              if (open) {
                _expanded.remove(n.path);
              } else {
                _expanded.add(n.path);
              }
            }),
            child: Padding(
              padding: EdgeInsets.only(
                left: 12.0 + depth * 14,
                top: 6,
                bottom: 6,
                right: 12,
              ),
              child: Row(
                children: [
                  Icon(
                    open ? Icons.folder_open_rounded : Icons.folder_rounded,
                    size: 20,
                    color: ForgePalette.glowAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      n.name,
                      style: Theme.of(context).textTheme.labelLarge,
                      softWrap: true,
                    ),
                  ),
                  if (widget.onCreateFileRequested != null ||
                      widget.onCreateFolderRequested != null ||
                      widget.onRenameRequested != null ||
                      widget.onDeleteRequested != null)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz_rounded, size: 18),
                      onSelected: (value) {
                        switch (value) {
                          case 'new_file':
                            widget.onCreateFileRequested?.call(n.path);
                            break;
                          case 'new_folder':
                            widget.onCreateFolderRequested?.call(n.path);
                            break;
                          case 'rename':
                            widget.onRenameRequested?.call(n);
                            break;
                          case 'delete':
                            widget.onDeleteRequested?.call(n);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        if (widget.onCreateFileRequested != null)
                          const PopupMenuItem(
                            value: 'new_file',
                            child: Text('New file in folder'),
                          ),
                        if (widget.onCreateFolderRequested != null)
                          const PopupMenuItem(
                            value: 'new_folder',
                            child: Text('New subfolder'),
                          ),
                        if (widget.onRenameRequested != null)
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                        if (widget.onDeleteRequested != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete folder'),
                          ),
                      ],
                    ),
                  Icon(
                    open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: ForgePalette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            for (final c in n.children) _nodeTile(context, c, depth + 1),
        ],
      );
    }

    final selected = widget.selectedPath == n.path;
    return InkWell(
      onTap: () => widget.onFileSelected(n),
      child: ColoredBox(
        color: selected
            ? ForgePalette.primaryAccent.withValues(alpha: 0.12)
            : Colors.transparent,
        child: Padding(
          padding: EdgeInsets.only(
            left: 12.0 + depth * 14,
            top: 8,
            bottom: 8,
            right: 12,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.insert_drive_file_rounded,
                size: 18,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.name,
                      style: Theme.of(context).textTheme.labelLarge,
                      softWrap: true,
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${n.language} · ${n.sizeLabel}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (n.changeLabel.trim().isNotEmpty)
                          Text(
                            n.changeLabel,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.onRenameRequested != null ||
                  widget.onDeleteRequested != null)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  onSelected: (value) {
                    if (value == 'rename') {
                      widget.onRenameRequested?.call(n);
                    } else if (value == 'delete') {
                      widget.onDeleteRequested?.call(n);
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.onRenameRequested != null)
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Rename'),
                      ),
                    if (widget.onDeleteRequested != null)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete file'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
