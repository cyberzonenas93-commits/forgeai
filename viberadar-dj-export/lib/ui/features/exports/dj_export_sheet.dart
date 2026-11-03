// lib/ui/features/exports/dj_export_sheet.dart
//
// Modal bottom sheet that drives the DJ export flow.
//
// Usage (from exports_screen.dart or any playlist action):
//
//   await showDjExportSheet(
//     context: context,
//     ref: ref,
//     target: DjTarget.virtualDj,
//     playlistName: playlist.name,
//     matches: playlist.trackMatches,
//   );
//
// The sheet walks the user through three steps:
//   Step 1 – Setup   (VirtualDJ: TIDAL toggle; Serato: crate parent name)
//   Step 2 – Root    (auto-detected path shown; folder-picker fallback)
//   Step 3 – Result  (stats: local / TIDAL / skipped counts + output path)
//
// On Serato, TIDAL tracks are silently skipped (no streaming format),
// so Step 1 is only shown for VirtualDJ.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/dj_export_models.dart';
import '../../../models/library_models.dart'; // TrackMatch
import '../../../providers/dj_export_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry-point helper
// ─────────────────────────────────────────────────────────────────────────────

Future<DjExportResult?> showDjExportSheet({
  required BuildContext context,
  required WidgetRef ref,
  required DjTarget target,
  required String playlistName,
  required List<TrackMatch> matches,
  /// Optional: pre-seeded TIDAL IDs keyed by VibeRadar track ID.
  Map<String, String> tidalIds = const {},
  String? parentCrateName,
}) async {
  // Kick off root detection early so it's usually done before the user
  // finishes reading the first step.
  ref.read(djExportProvider.notifier).detectRoots();

  final result = await showModalBottomSheet<DjExportResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: _DjExportSheet(
        target: target,
        playlistName: playlistName,
        matches: matches,
        tidalIds: tidalIds,
        parentCrateName: parentCrateName,
      ),
    ),
  );

  // Reset the notifier so re-opening the sheet starts fresh (but keeps roots).
  ref.read(djExportProvider.notifier).reset();
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet widget
// ─────────────────────────────────────────────────────────────────────────────

class _DjExportSheet extends ConsumerStatefulWidget {
  const _DjExportSheet({
    required this.target,
    required this.playlistName,
    required this.matches,
    required this.tidalIds,
    this.parentCrateName,
  });

  final DjTarget target;
  final String playlistName;
  final List<TrackMatch> matches;
  final Map<String, String> tidalIds;
  final String? parentCrateName;

  @override
  ConsumerState<_DjExportSheet> createState() => _DjExportSheetState();
}

class _DjExportSheetState extends ConsumerState<_DjExportSheet> {
  int _step = 0; // 0 = setup, 1 = root, 2 = result

  @override
  void initState() {
    super.initState();
    // Skip setup step for Serato (no user choices needed).
    if (widget.target == DjTarget.serato) _step = 1;
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _advance() => setState(() => _step++);

  Future<void> _startExport() async {
    final notifier = ref.read(djExportProvider.notifier);
    if (widget.target == DjTarget.virtualDj) {
      await notifier.exportToVirtualDj(
        playlistName: widget.playlistName,
        matches: widget.matches,
        tidalIds: widget.tidalIds,
      );
    } else {
      await notifier.exportToSerato(
        playlistName: widget.playlistName,
        matches: widget.matches,
        parentCrateName: widget.parentCrateName,
      );
    }
    // Result step is driven by the provider status listener in build().
  }

  // ── Root folder picker ────────────────────────────────────────────────────

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: widget.target == DjTarget.virtualDj
          ? 'Select VirtualDJ Library Folder'
          : 'Select Serato Library Folder (_Serato_)',
    );
    if (path == null || !mounted) return;

    final notifier = ref.read(djExportProvider.notifier);
    if (widget.target == DjTarget.virtualDj) {
      await notifier.setVdjRoot(path);
    } else {
      await notifier.setSeratoRoot(path);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(djExportProvider);

    // Automatically advance to result step when export finishes.
    ref.listen<DjExportState>(djExportProvider, (_, next) {
      if ((next.status == DjExportStatus.done ||
              next.status == DjExportStatus.error) &&
          _step < 2) {
        setState(() => _step = 2);
      }
    });

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(
                    widget.target == DjTarget.virtualDj
                        ? Icons.queue_music
                        : Icons.album,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.target == DjTarget.virtualDj
                          ? 'Export to VirtualDJ'
                          : 'Export to Serato',
                      style: tt.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 24),

            // Step content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: switch (_step) {
                    0 => _SetupStep(
                        key: const ValueKey('setup'),
                        onNext: _advance,
                      ),
                    1 => _RootStep(
                        key: const ValueKey('root'),
                        target: widget.target,
                        exportState: exportState,
                        onPickFolder: _pickFolder,
                        onExport: _startExport,
                      ),
                    _ => _ResultStep(
                        key: const ValueKey('result'),
                        exportState: exportState,
                        onDone: (result) => Navigator.of(context).pop(result),
                        onRetry: () => setState(() => _step = 1),
                      ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 0 – Setup (VirtualDJ only: TIDAL toggle)
// ─────────────────────────────────────────────────────────────────────────────

class _SetupStep extends ConsumerWidget {
  const _SetupStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useTidal = ref.watch(djExportProvider.select((s) => s.useTidal));
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Export options', style: tt.titleMedium),
        const SizedBox(height: 8),
        Text(
          'VibeRadar will try to match each track to a local file on your '
          'computer. Tracks that cannot be matched will be skipped unless '
          'you enable TIDAL fallback below.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurface.withOpacity(0.7)),
        ),
        const SizedBox(height: 24),

        // TIDAL toggle
        Card(
          margin: EdgeInsets.zero,
          child: SwitchListTile(
            title: const Text('Include TIDAL tracks'),
            subtitle: const Text(
              'Unmatched tracks will appear as TIDAL streaming links in VirtualDJ.',
            ),
            value: useTidal,
            onChanged: (v) =>
                ref.read(djExportProvider.notifier).setUseTidal(value: v),
          ),
        ),

        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onNext,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 – Root path + Export trigger
// ─────────────────────────────────────────────────────────────────────────────

class _RootStep extends StatelessWidget {
  const _RootStep({
    super.key,
    required this.target,
    required this.exportState,
    required this.onPickFolder,
    required this.onExport,
  });

  final DjTarget target;
  final DjExportState exportState;
  final VoidCallback onPickFolder;
  final Future<void> Function() onExport;

  String? get _currentRoot => target == DjTarget.virtualDj
      ? exportState.vdjRoot
      : exportState.seratoRoot;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isLoading = exportState.isLoading;

    final rootLabel = target == DjTarget.virtualDj
        ? 'VirtualDJ library folder'
        : 'Serato library folder (_Serato_)';

    final defaultPath = target == DjTarget.virtualDj
        ? '~/Library/Application Support/VirtualDJ'
        : '~/Music/_Serato_';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Library location', style: tt.titleMedium),
        const SizedBox(height: 8),

        if (exportState.status == DjExportStatus.detectingRoots)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Detecting library folder…'),
              ],
            ),
          )
        else ...[
          Text(
            _currentRoot != null
                ? 'Auto-detected library folder:'
                : 'Could not find $rootLabel automatically.\n'
                    'Default location: $defaultPath',
            style: tt.bodyMedium
                ?.copyWith(color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 8),
          if (_currentRoot != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentRoot!,
                      style: tt.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],

        const SizedBox(height: 12),

        OutlinedButton.icon(
          icon: const Icon(Icons.folder_open, size: 18),
          label: Text(_currentRoot != null
              ? 'Change folder'
              : 'Choose library folder'),
          onPressed: isLoading ? null : onPickFolder,
        ),

        if (exportState.errorMessage != null &&
            exportState.status != DjExportStatus.exporting) ...[
          const SizedBox(height: 16),
          _ErrorBanner(message: exportState.errorMessage!),
        ],

        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.upload),
            label: Text(isLoading ? 'Exporting…' : 'Export'),
            onPressed: (_currentRoot == null || isLoading) ? null : onExport,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 – Result summary
// ─────────────────────────────────────────────────────────────────────────────

class _ResultStep extends StatelessWidget {
  const _ResultStep({
    super.key,
    required this.exportState,
    required this.onDone,
    required this.onRetry,
  });

  final DjExportState exportState;
  final void Function(DjExportResult? result) onDone;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (exportState.status == DjExportStatus.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 48),
          const SizedBox(height: 16),
          Text('Export failed', style: tt.titleMedium),
          const SizedBox(height: 8),
          _ErrorBanner(message: exportState.errorMessage ?? 'Unknown error'),
          const SizedBox(height: 24),
          Row(
            children: [
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => onDone(null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      );
    }

    // Loading guard (shouldn't be visible, but be safe).
    if (exportState.status == DjExportStatus.exporting ||
        exportState.result == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final r = exportState.result!;
    final targetName =
        r.target == DjTarget.virtualDj ? 'VirtualDJ' : 'Serato';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: cs.primary, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Exported to $targetName',
                      style: tt.titleMedium),
                  Text(
                    r.playlistName,
                    style: tt.bodyMedium
                        ?.copyWith(color: cs.onSurface.withOpacity(0.7)),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Stats grid
        _StatGrid(result: r),

        const SizedBox(height: 20),

        // Output path
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saved to', style: tt.labelSmall),
              const SizedBox(height: 4),
              Text(
                r.outputPath,
                style:
                    tt.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
        ),

        // Warning (e.g. skipped tracks)
        if (r.warning != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber, size: 18,
                  color: cs.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.warning!,
                    style: tt.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.7))),
              ),
            ],
          ),
        ],

        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => onDone(r),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.result});

  final DjExportResult result;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatTile(
          label: 'Total',
          value: result.totalTracks.toString(),
          icon: Icons.library_music,
        ),
        const SizedBox(width: 8),
        _StatTile(
          label: 'Local',
          value: result.localMatchCount.toString(),
          icon: Icons.storage,
          color: Colors.green,
        ),
        if (result.tidalCount > 0) ...[
          const SizedBox(width: 8),
          _StatTile(
            label: 'TIDAL',
            value: result.tidalCount.toString(),
            icon: Icons.cloud,
            color: Colors.blue,
          ),
        ],
        if (result.skippedCount > 0) ...[
          const SizedBox(width: 8),
          _StatTile(
            label: 'Skipped',
            value: result.skippedCount.toString(),
            icon: Icons.block,
            color: Colors.orange,
          ),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = color ?? cs.primary;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: 4),
            Text(value,
                style: tt.titleMedium?.copyWith(
                    color: c, fontWeight: FontWeight.bold)),
            Text(label,
                style: tt.labelSmall
                    ?.copyWith(color: cs.onSurface.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
