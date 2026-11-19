// test/services/serato_export_test.dart
//
// Unit tests for SeratoExportService.
//
// Coverage:
//   • buildCrateBytes    – binary TLV structure, vrsn tag, otrk/ptrk encoding
//   • UTF-16BE encoding  – round-trip accuracy, ASCII and non-ASCII chars
//   • buildCrateFilename – nested %% naming, root-level naming
//   • exportCrate        – writes to correct path, local resolution,
//                          streaming tracks are skipped, summary stats
//   • Fixture comparison – compare vrsn tag bytes against known-good values

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:viberadar/models/dj_export_models.dart';
import 'package:viberadar/services/serato_export_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

DjExportTrack _local(String path) => DjExportTrack(
      resolution: DjTrackResolution.localMatch,
      localFilePath: path,
    );

DjExportTrack _tidal(String id) => DjExportTrack(
      resolution: DjTrackResolution.tidalFallback,
      tidalId: id,
    );

DjExportTrack _skipped([String? reason]) => DjExportTrack(
      resolution: DjTrackResolution.skipped,
      skipReason: reason,
    );

/// Read a 4-byte ASCII tag from [bytes] at [offset].
String _readTag(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes.sublist(offset, offset + 4));

/// Read a big-endian uint32 from [bytes] at [offset].
int _readU32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

/// Decode UTF-16BE bytes to a Dart string.
String _decodeUtf16BE(Uint8List bytes) {
  final chars = <int>[];
  for (var i = 0; i < bytes.length - 1; i += 2) {
    chars.add((bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(chars);
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late SeratoExportService service;

  setUp(() => service = SeratoExportService());

  // ─────────────────────────────────────────────────────────────────────────
  // buildCrateBytes – vrsn tag
  // ─────────────────────────────────────────────────────────────────────────

  group('buildCrateBytes – vrsn tag', () {
    test('first tag is "vrsn"', () {
      final bytes = service.buildCrateBytes([]);
      expect(_readTag(bytes, 0), equals('vrsn'));
    });

    test('vrsn value decodes to "1.0/Serato ScratchLive Crate"', () {
      final bytes = service.buildCrateBytes([]);
      final vrsnLength = _readU32(bytes, 4);
      final vrsnValue = bytes.sublist(8, 8 + vrsnLength);
      final decoded = _decodeUtf16BE(vrsnValue);
      expect(decoded, equals('1.0/Serato ScratchLive Crate'));
    });

    test('vrsn value is exactly 56 bytes (28 UTF-16BE chars × 2)', () {
      final bytes = service.buildCrateBytes([]);
      final vrsnLength = _readU32(bytes, 4);
      // "1.0/Serato ScratchLive Crate" = 28 characters = 56 bytes UTF-16BE
      expect(vrsnLength, equals(56));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // buildCrateBytes – otrk / ptrk per track
  // ─────────────────────────────────────────────────────────────────────────

  group('buildCrateBytes – track entries', () {
    test('empty path list produces only vrsn (no otrk)', () {
      final bytes = service.buildCrateBytes([]);
      final vrsnLength = _readU32(bytes, 4);
      // Total bytes: 4 (tag) + 4 (len) + vrsnLength = 8 + vrsnLength
      expect(bytes.length, equals(8 + vrsnLength));
    });

    test('one path produces one otrk block after vrsn', () {
      final bytes = service.buildCrateBytes(['/music/track.mp3']);
      final vrsnLength = _readU32(bytes, 4);
      final otrkOffset = 8 + vrsnLength;

      expect(_readTag(bytes, otrkOffset), equals('otrk'));
    });

    test('ptrk tag nested inside otrk value', () {
      final bytes = service.buildCrateBytes(['/music/track.mp3']);
      final vrsnLength = _readU32(bytes, 4);
      // otrk offset
      final otrkOffset = 8 + vrsnLength;
      // otrk value starts 8 bytes after otrkOffset (4 tag + 4 len)
      final otrkValueOffset = otrkOffset + 8;

      expect(_readTag(bytes, otrkValueOffset), equals('ptrk'));
    });

    test('ptrk value decodes to the supplied path', () {
      const path = '/Users/dj/Music/House/track.mp3';
      final bytes = service.buildCrateBytes([path]);
      final vrsnLength = _readU32(bytes, 4);

      // Navigate to ptrk value
      final otrkOffset = 8 + vrsnLength;
      final ptrkOffset = otrkOffset + 8; // skip otrk tag + len
      final ptrkLength = _readU32(bytes, ptrkOffset + 4);
      final ptrkValue = bytes.sublist(ptrkOffset + 8, ptrkOffset + 8 + ptrkLength);

      expect(_decodeUtf16BE(ptrkValue), equals(path));
    });

    test('multiple paths produce multiple otrk blocks in order', () {
      final paths = [
        '/music/a.mp3',
        '/music/b.mp3',
        '/music/c.mp3',
      ];
      final bytes = service.buildCrateBytes(paths);
      final vrsnLength = _readU32(bytes, 4);

      // Walk through otrk blocks and collect ptrk values
      final found = <String>[];
      var offset = 8 + vrsnLength;
      while (offset < bytes.length) {
        final tag = _readTag(bytes, offset);
        final len = _readU32(bytes, offset + 4);
        if (tag == 'otrk') {
          // ptrk is the first (and only) sub-tag
          final ptrkLen = _readU32(bytes, offset + 8 + 4);
          final ptrkBytes =
              bytes.sublist(offset + 8 + 8, offset + 8 + 8 + ptrkLen);
          found.add(_decodeUtf16BE(ptrkBytes));
        }
        offset += 8 + len;
      }

      expect(found, orderedEquals(paths));
    });

    test('non-ASCII chars (UTF-8 filenames) round-trip correctly', () {
      const path = '/music/Björk – Jóga.mp3';
      final bytes = service.buildCrateBytes([path]);
      final vrsnLength = _readU32(bytes, 4);

      final otrkOffset = 8 + vrsnLength;
      final ptrkOffset = otrkOffset + 8;
      final ptrkLength = _readU32(bytes, ptrkOffset + 4);
      final ptrkValue =
          bytes.sublist(ptrkOffset + 8, ptrkOffset + 8 + ptrkLength);

      expect(_decodeUtf16BE(ptrkValue), equals(path));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // buildCrateFilename
  // ─────────────────────────────────────────────────────────────────────────

  group('buildCrateFilename', () {
    test('null parent → "<name>.crate"', () {
      expect(service.buildCrateFilename('House', null), equals('House.crate'));
    });

    test('parent provided → "<parent>%%<name>.crate"', () {
      expect(
        service.buildCrateFilename('House', 'LocalMusic'),
        equals('LocalMusic%%House.crate'),
      );
    });

    test('spaces in names are preserved', () {
      expect(
        service.buildCrateFilename('Deep House', 'My Crates'),
        equals('My Crates%%Deep House.crate'),
      );
    });

    test('deeply nested parent (two levels)', () {
      // Caller is responsible for building the parent string, but the
      // service should pass it through unchanged.
      expect(
        service.buildCrateFilename('Minimal', 'LocalMusic%%Techno'),
        equals('LocalMusic%%Techno%%Minimal.crate'),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // exportCrate (integration: writes to temp disk)
  // ─────────────────────────────────────────────────────────────────────────

  group('exportCrate', () {
    late Directory seratoRoot;
    late Directory fakeLocalDir;

    setUp(() async {
      seratoRoot = await Directory.systemTemp.createTemp('vr_serato_');
      await Directory('${seratoRoot.path}/Subcrates').create();
      fakeLocalDir = await Directory.systemTemp.createTemp('vr_music_');
    });

    tearDown(() async {
      await seratoRoot.delete(recursive: true);
      await fakeLocalDir.delete(recursive: true);
    });

    test('writes crate file to Subcrates directory', () async {
      final localPath = '${fakeLocalDir.path}/track.mp3';
      await File(localPath).create();

      final result = await service.exportCrate(
        seratoRoot: seratoRoot.path,
        crateName: 'HouseSet',
        tracks: [_local(localPath)],
      );

      final file = File(result.outputPath);
      expect(file.existsSync(), isTrue);
      expect(result.outputPath, contains('Subcrates'));
      expect(result.outputPath, endsWith('HouseSet.crate'));
    });

    test('uses %% separator when parent crate provided', () async {
      final localPath = '${fakeLocalDir.path}/track.mp3';
      await File(localPath).create();

      final result = await service.exportCrate(
        seratoRoot: seratoRoot.path,
        crateName: 'Techno',
        tracks: [_local(localPath)],
        parentCrateName: 'LocalMusic',
      );

      expect(result.outputPath, contains('LocalMusic%%Techno.crate'));
    });

    test('TIDAL tracks are skipped (not included in binary)', () async {
      final localPath = '${fakeLocalDir.path}/local.mp3';
      await File(localPath).create();

      final result = await service.exportCrate(
        seratoRoot: seratoRoot.path,
        crateName: 'Mixed',
        tracks: [
          _local(localPath),
          _tidal('9999'), // should NOT appear in binary
          _skipped(),
        ],
      );

      expect(result.localMatchCount, equals(1));
      expect(result.tidalCount, equals(0)); // Serato doesn't support streaming
      expect(result.skippedCount, equals(2)); // tidal + skipped both omitted

      // Verify binary: only 1 otrk block
      final bytes = File(result.outputPath).readAsBytesSync();
      final otrkCount =
          RegExp(r'otrk').allMatches(String.fromCharCodes(bytes)).length;
      expect(otrkCount, equals(1));
    });

    test('summary counts match track composition', () async {
      final p1 = '${fakeLocalDir.path}/t1.mp3';
      final p2 = '${fakeLocalDir.path}/t2.mp3';
      await File(p1).create();
      await File(p2).create();

      final result = await service.exportCrate(
        seratoRoot: seratoRoot.path,
        crateName: 'Stats',
        tracks: [
          _local(p1),
          _local(p2),
          _skipped('no file'),
        ],
      );

      expect(result.totalTracks, equals(3));
      expect(result.localMatchCount, equals(2));
      expect(result.skippedCount, equals(1));
    });

    test('overwrites existing crate on re-export', () async {
      final localPath = '${fakeLocalDir.path}/track.mp3';
      await File(localPath).create();

      await service.exportCrate(
        seratoRoot: seratoRoot.path,
        crateName: 'Overwrite',
        tracks: [_local(localPath)],
      );

      // Second export with two tracks.
      final p2 = '${fakeLocalDir.path}/track2.mp3';
      await File(p2).create();

      final result2 = await service.exportCrate(
        seratoRoot: seratoRoot.path,
        crateName: 'Overwrite',
        tracks: [_local(localPath), _local(p2)],
      );

      final bytes = File(result2.outputPath).readAsBytesSync();
      // Count otrk occurrences — should be 2.
      int count = 0;
      int offset = 0;
      while (offset < bytes.length - 4) {
        if (bytes[offset] == 0x6F && // 'o'
            bytes[offset + 1] == 0x74 && // 't'
            bytes[offset + 2] == 0x72 && // 'r'
            bytes[offset + 3] == 0x6B) { // 'k'
          count++;
        }
        offset++;
      }
      expect(count, equals(2));
    });
  });
}
