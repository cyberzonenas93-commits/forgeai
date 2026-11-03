# DJ Export Feature — Developer Notes

## Files Changed / Added

### New files (drop straight into your project)

| Destination in VibeRadar | File in this bundle |
|---|---|
| `lib/models/dj_export_models.dart` | *(written in previous session)* |
| `lib/services/dj_root_detection_service.dart` | *(written in previous session)* |
| `lib/services/virtual_dj_export_service.dart` | *(written in previous session)* |
| `lib/services/serato_export_service.dart` | *(written in previous session)* |
| `lib/services/export_service.dart` | *(updated in previous session)* |
| `lib/providers/dj_export_provider.dart` | `lib/providers/dj_export_provider.dart` |
| `lib/ui/features/exports/dj_export_sheet.dart` | `lib/ui/features/exports/dj_export_sheet.dart` |
| `test/services/dj_root_detection_test.dart` | `test/services/dj_root_detection_test.dart` |
| `test/services/virtual_dj_export_test.dart` | `test/services/virtual_dj_export_test.dart` |
| `test/services/serato_export_test.dart` | `test/services/serato_export_test.dart` |

### Existing file to update

`lib/ui/features/exports/exports_screen.dart` — see `exports_screen_patch.dart`.

The patch adds two imports and drops the `DjSoftwareSection` widget into
your existing exports list. No other logic changes.

---

## Architecture fit

```
ExportsScreen
  └─ DjSoftwareSection           (new — exports_screen_patch.dart)
        ├─ "VirtualDJ" tile  ──► showDjExportSheet(target: virtualDj)
        └─ "Serato" tile     ──► showDjExportSheet(target: serato)

showDjExportSheet                (dj_export_sheet.dart)
  └─ _DjExportSheet (modal)
        Step 0 – Setup       reads/writes djExportProvider (useTidal toggle)
        Step 1 – Root        shows detected path, offers folder picker
        Step 2 – Result      shows stats: local / TIDAL / skipped

djExportProvider                 (dj_export_provider.dart)
  └─ DjExportNotifier
        detectRoots()    ──► DjRootDetectionService (SharedPreferences + fs probe)
        exportToVirtualDj() ─► ExportService.exportToVirtualDj()
        exportToSerato()    ─► ExportService.exportToSerato()

ExportService                    (updated — export_service.dart)
  ├─ exportToVirtualDj()  ──► VirtualDjExportService
  └─ exportToSerato()     ──► SeratoExportService
```

The feature plugs into VibeRadar's existing Riverpod + ExportService
architecture. No Cloud Functions are involved; all file I/O is local.

---

## pubspec.yaml — required additions

```yaml
dependencies:
  file_picker: ^8.0.0        # folder picker in the sheet
  shared_preferences: ^2.3.0 # already likely present — used for root persistence

dev_dependencies:
  # Nothing new; tests use flutter_test + dart:io only
```

`file_picker` on macOS requires adding the entitlement
`com.apple.security.files.user-selected.read-write` to your
`*.entitlements` files — you already have this from the macOS signing work.

---

## Data flow: TrackMatch → DjExportTrack

`ExportService.exportToVirtualDj()` and `exportToSerato()` each receive a
`List<TrackMatch>` (the same model used everywhere in VibeRadar).

Resolution order per track:
1. **Local match** — `TrackMatch.localTrack?.filePath` is set → use it.
2. **TIDAL fallback** (VirtualDJ only, when `useTidal = true`) — parse TIDAL
   ID from `track.platformLinks['tidal']` URL or from the caller-supplied
   `tidalIds` map → write `netsearch://td<id>` path.
3. **Skipped** — everything else. Counted in summary; omitted from output.

Serato never includes TIDAL tracks (no standardised streaming format).

---

## VirtualDJ format details

- Output: `<vdjRoot>/Folders/LocalMusic/<PlaylistName>.vdjfolder`
- Format: UTF-8 XML with `<VirtualFolder>` root and `<song path="…" idx="N"/>` children.
- `order` file at `Folders/LocalMusic/order` is updated idempotently (new
  name inserted once; existing entries preserved).
- TIDAL paths: `netsearch://td<TIDAL_TRACK_ID>`.
- All path attribute values are XML-escaped (`&amp;`, `&quot;`, `&apos;`, `&lt;`, `&gt;`).

## Serato format details

- Output: `<seratoRoot>/Subcrates/<CrateName>.crate`
  (or `<Parent>%%<CrateName>.crate` when `parentCrateName` is supplied)
- Format: binary TLV — `[4-byte ASCII tag][4-byte BE uint32 length][UTF-16BE value]`
- Tags: `vrsn` (header, "1.0/Serato ScratchLive Crate"), `otrk` (per-track
  wrapper), `ptrk` (absolute file path as UTF-16BE, nested inside `otrk`).
- No streaming entries; TIDAL tracks count as skipped.

---

## Running the tests

```bash
flutter test test/services/dj_root_detection_test.dart
flutter test test/services/virtual_dj_export_test.dart
flutter test test/services/serato_export_test.dart
```

All three test files use only `dart:io` and `flutter_test`. No mocking
library is needed beyond `SharedPreferences.setMockInitialValues({})`.
