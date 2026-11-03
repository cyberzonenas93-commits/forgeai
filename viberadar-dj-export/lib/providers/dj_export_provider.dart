// lib/providers/dj_export_provider.dart
//
// Riverpod state management for the DJ export flow.
// Matches the Notifier/NotifierProvider pattern used by LibraryNotifier.
//
// State machine:
//   idle → loading (detectRoots) → ready
//   ready → exporting → done | error
//
// Usage:
//   final notifier = ref.read(djExportProvider.notifier);
//   await notifier.detectRoots();
//   await notifier.exportToVirtualDj(playlistName: 'House Set', matches: matches);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dj_export_models.dart';
import '../services/dj_root_detection_service.dart';
import '../services/export_service.dart';
import '../models/library_models.dart'; // TrackMatch

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

enum DjExportStatus { idle, detectingRoots, ready, exporting, done, error }

class DjExportState {
  const DjExportState({
    this.status = DjExportStatus.idle,
    this.vdjRoot,
    this.seratoRoot,
    this.result,
    this.errorMessage,
    this.useTidal = false,
  });

  final DjExportStatus status;

  /// Auto-detected or user-overridden VirtualDJ root (may be null if not found).
  final String? vdjRoot;

  /// Auto-detected or user-overridden Serato root (may be null if not found).
  final String? seratoRoot;

  /// Populated after a successful export.
  final DjExportResult? result;

  /// Populated after a failed export.
  final String? errorMessage;

  /// Whether TIDAL fallback links should be included in VirtualDJ exports.
  final bool useTidal;

  bool get isLoading =>
      status == DjExportStatus.detectingRoots ||
      status == DjExportStatus.exporting;

  bool get hasVdjRoot => vdjRoot != null && vdjRoot!.isNotEmpty;
  bool get hasSeratoRoot => seratoRoot != null && seratoRoot!.isNotEmpty;

  DjExportState copyWith({
    DjExportStatus? status,
    String? vdjRoot,
    String? seratoRoot,
    DjExportResult? result,
    String? errorMessage,
    bool? useTidal,
    bool clearResult = false,
    bool clearError = false,
    bool clearVdjRoot = false,
    bool clearSeratoRoot = false,
  }) {
    return DjExportState(
      status: status ?? this.status,
      vdjRoot: clearVdjRoot ? null : (vdjRoot ?? this.vdjRoot),
      seratoRoot:
          clearSeratoRoot ? null : (seratoRoot ?? this.seratoRoot),
      result: clearResult ? null : (result ?? this.result),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      useTidal: useTidal ?? this.useTidal,
    );
  }

  @override
  String toString() =>
      'DjExportState(status=$status, vdjRoot=$vdjRoot, '
      'seratoRoot=$seratoRoot, useTidal=$useTidal)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class DjExportNotifier extends Notifier<DjExportState> {
  late final DjRootDetectionService _rootDetection;
  late final ExportService _exportService;

  @override
  DjExportState build() {
    _rootDetection = DjRootDetectionService();
    _exportService = ExportService();
    return const DjExportState();
  }

  // ── Root detection ────────────────────────────────────────────────────────

  /// Auto-detect VirtualDJ and Serato roots.  Call this when the DJ export
  /// sheet opens so roots are ready before the user taps Export.
  Future<void> detectRoots() async {
    state = state.copyWith(status: DjExportStatus.detectingRoots);

    final vdjRoot = await _rootDetection.resolveVirtualDjRoot();
    final seratoRoot = await _rootDetection.resolveSeratoRoot();

    state = state.copyWith(
      status: DjExportStatus.ready,
      vdjRoot: vdjRoot,
      seratoRoot: seratoRoot,
      clearVdjRoot: vdjRoot == null,
      clearSeratoRoot: seratoRoot == null,
    );
  }

  /// Override the VirtualDJ root manually (from a folder picker).
  /// Persists the selection for future sessions.
  Future<void> setVdjRoot(String path) async {
    final valid = _rootDetection.validateVirtualDjRoot(path);
    if (!valid) {
      state = state.copyWith(
        errorMessage:
            'The selected folder does not look like a VirtualDJ library '
            '(missing database.xml or Folders directory).',
      );
      return;
    }
    await _rootDetection.persistVirtualDjRoot(path);
    state = state.copyWith(vdjRoot: path, clearError: true);
  }

  /// Override the Serato root manually (from a folder picker).
  /// Persists the selection for future sessions.
  Future<void> setSeratoRoot(String path) async {
    final valid = _rootDetection.validateSeratoRoot(path);
    if (!valid) {
      state = state.copyWith(
        errorMessage:
            'The selected folder does not look like a Serato library '
            '(missing Subcrates or database V2).',
      );
      return;
    }
    await _rootDetection.persistSeratoRoot(path);
    state = state.copyWith(seratoRoot: path, clearError: true);
  }

  // ── TIDAL toggle ──────────────────────────────────────────────────────────

  void setUseTidal({required bool value}) {
    state = state.copyWith(useTidal: value);
  }

  // ── Export ────────────────────────────────────────────────────────────────

  /// Export [matches] to a VirtualDJ playlist folder.
  ///
  /// [overrideRoot] bypasses auto-detection; use when the user picks a root
  /// via folder picker inline in the sheet.
  Future<void> exportToVirtualDj({
    required String playlistName,
    required List<TrackMatch> matches,
    Map<String, String> tidalIds = const {},
    String? overrideRoot,
  }) async {
    state = state.copyWith(
      status: DjExportStatus.exporting,
      clearResult: true,
      clearError: true,
    );

    try {
      final result = await _exportService.exportToVirtualDj(
        playlistName: playlistName,
        matches: matches,
        useTidal: state.useTidal,
        tidalIds: tidalIds,
        overrideRoot: overrideRoot ?? state.vdjRoot,
      );

      // Keep the resolved root in state so the UI can show it.
      state = state.copyWith(
        status: DjExportStatus.done,
        result: result,
        vdjRoot: result.djRoot,
      );
    } catch (e) {
      state = state.copyWith(
        status: DjExportStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Export [matches] to a Serato crate file.
  Future<void> exportToSerato({
    required String playlistName,
    required List<TrackMatch> matches,
    String? parentCrateName,
    String? overrideRoot,
  }) async {
    state = state.copyWith(
      status: DjExportStatus.exporting,
      clearResult: true,
      clearError: true,
    );

    try {
      final result = await _exportService.exportToSerato(
        playlistName: playlistName,
        matches: matches,
        parentCrateName: parentCrateName,
        overrideRoot: overrideRoot ?? state.seratoRoot,
      );

      state = state.copyWith(
        status: DjExportStatus.done,
        result: result,
        seratoRoot: result.djRoot,
      );
    } catch (e) {
      state = state.copyWith(
        status: DjExportStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Return to ready state so the sheet can be reused for another export.
  void reset() {
    state = state.copyWith(
      status: DjExportStatus.ready,
      clearResult: true,
      clearError: true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

/// Global provider for the DJ export flow.
/// Keep as an `autoDispose` variant if you want the state cleared whenever
/// the sheet is dismissed:
///
///   final djExportProvider =
///       NotifierProvider.autoDispose<DjExportNotifier, DjExportState>(
///         DjExportNotifier.new,
///       );
///
/// Using a non-autoDispose provider retains the detected root paths between
/// sheet openings, which avoids repeated filesystem probing.
final djExportProvider =
    NotifierProvider<DjExportNotifier, DjExportState>(DjExportNotifier.new);
