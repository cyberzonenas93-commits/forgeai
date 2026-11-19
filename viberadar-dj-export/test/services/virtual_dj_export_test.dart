// test/services/virtual_dj_export_test.dart
//
// Unit tests for VirtualDjExportService.
//
// Coverage:
//   • buildVdjFolderXml  – XML structure, idx ordering, XML escaping
//   • updateOrderFile    – insertion, duplicate prevention, preservation of
//                          existing entries, creation when absent
//   • exportPlaylist     – local track resolution, TIDAL fallback, skipping,
//                          summary stats, overwrite behaviour
//   • TIDAL ID extraction – from supplied map and from platformLinks URL

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:viberadar/models/dj_export_models.dart';
import 'package:viberadar/models/library_models.dart';
import 'package:viberadar/services/virtual_dj_export_service.dart';

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

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late VirtualDjExportService service;

  setUp(() => service = VirtualDjExportService());

  // ─────────────────────────────────────────────────────────────────────────
  // buildVdjFolderXml
  // ─────────────────────────────────────────────────────────────────────────

  group('buildVdjFolderXml', () {
    test('produces valid XML declaration and VirtualFolder root', () {
      final xml = service.buildVdjFolderXml([_local('/music/a.mp3')]);
      expect(xml, startsWith("<?xml version='1.0' encoding='UTF-8'?>"));
      expect(xml, contains('<VirtualFolder>'));
      expect(xml, contains('</VirtualFolder>'));
    });

    test('each track gets sequential zero-based idx', () {
      final xml = service.buildVdjFolderXml([
        _local('/music/a.mp3'),
        _local('/music/b.mp3'),
        _local('/music/c.mp3'),
      ]);
      expect(xml, contains('idx="0"'));
      expect(xml, contains('idx="1"'));
      expect(xml, contains('idx="2"'));
      expect(xml, isNot(contains('idx="3"')));
    });

    test('local track path appears in path attribute', () {
      final xml = service.buildVdjFolderXml([
        _local('/Users/dj/Music/House/track.mp3'),
      ]);
      expect(xml, contains('path="/Users/dj/Music/House/track.mp3"'));
    });

    test('TIDAL track uses netsearch:// scheme', () {
      final xml = service.buildVdjFolderXml([_tidal('12345678')]);
      expect(xml, contains('path="netsearch://td12345678"'));
    });

    test('skipped tracks are omitted from XML', () {
      final xml = service.buildVdjFolderXml([
        _local('/music/a.mp3'),
        _skipped('no local match'),
        _local('/music/c.mp3'),
      ]);
      // Only two <song> elements should appear.
      final matches = RegExp(r'<song ').allMatches(xml);
      expect(matches.length, equals(2));
      // idx should be 0 and 1 (consecutive, not 0 and 2).
      expect(xml, contains('idx="0"'));
      expect(xml, contains('idx="1"'));
    });

    test('empty track list produces empty VirtualFolder', () {
      final xml = service.buildVdjFolderXml([]);
      expect(xml, contains('<VirtualFolder>'));
      expect(xml, contains('</VirtualFolder>'));
      expect(xml, isNot(contains('<song')));
    });

    // XML escaping
    test('ampersand in path is XML-escaped', () {
      final xml = service.buildVdjFolderXml(
        [_local('/music/Rock & Roll/track.mp3')],
      );
      expect(xml, contains('&amp;'));
      expect(xml, isNot(contains('Rock & Roll')));
    });

    test('double-quote in path is XML-escaped', () {
      final xml =
          service.buildVdjFolderXml([_local('/music/Say "Hello"/t.mp3')]);
      expect(xml, contains('&quot;'));
    });

    test('apostrophe in path is XML-escaped', () {
      final xml =
          service.buildVdjFolderXml([_local("/music/Ain't That/t.mp3")]);
      expect(xml, contains('&apos;'));
    });

    test('angle brackets in path are XML-escaped', () {
      final xml =
          service.buildVdjFolderXml([_local('/music/<weird>/t.mp3')]);
      expect(xml, contains('&lt;'));
      expect(xml, contains('&gt;'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // updateOrderFile
  // ─────────────────────────────────────────────────────────────────────────

  group('updateOrderFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('vr_vdj_');
      await Directory('${tempDir.path}/Folders/LocalMusic').create(recursive: true);
    });

    tearDown(() async => tempDir.delete(recursive: true));

    test('creates order file when absent', () async {
      await service.updateOrderFile(tempDir.path, 'HouseSet');
      final file = File('${tempDir.path}/Folders/LocalMusic/order');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('HouseSet'));
    });

    test('appends playlist name to existing order file', () async {
      final file = File('${tempDir.path}/Folders/LocalMusic/order');
      file.writeAsStringSync('OldPlaylist\n');

      await service.updateOrderFile(tempDir.path, 'NewPlaylist');
      final content = file.readAsStringSync();
      expect(content, contains('OldPlaylist'));
      expect(content, contains('NewPlaylist'));
    });

    test('does NOT duplicate an already-present entry', () async {
      final file = File('${tempDir.path}/Folders/LocalMusic/order');
      file.writeAsStringSync('HouseSet\n');

      await service.updateOrderFile(tempDir.path, 'HouseSet');
      await service.updateOrderFile(tempDir.path, 'HouseSet');

      final content = file.readAsStringSync();
      final count = 'HouseSet'.allMatches(content).length;
      expect(count, equals(1));
    });

    test('preserves order of existing entries', () async {
      final file = File('${tempDir.path}/Folders/LocalMusic/order');
      file.writeAsStringSync('Alpha\nBeta\n');

      await service.updateOrderFile(tempDir.path, 'Gamma');
      final lines = file
          .readAsStringSync()
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();
      expect(lines.indexOf('Alpha'), lessThan(lines.indexOf('Beta')));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // exportPlaylist (integration-level: writes to temp disk)
  // ─────────────────────────────────────────────────────────────────────────

  group('exportPlaylist', () {
    late Directory vdjRoot;
    late Directory fakeLocalDir;

    setUp(() async {
      vdjRoot = await Directory.systemTemp.createTemp('vr_vdj_root_');
      await Directory('${vdjRoot.path}/Folders/LocalMusic').create(recursive: true);

      fakeLocalDir = await Directory.systemTemp.createTemp('vr_music_');
    });

    tearDown(() async {
      await vdjRoot.delete(recursive: true);
      await fakeLocalDir.delete(recursive: true);
    });

    test('writes .vdjfolder file to correct location', () async {
      final trackPath = '${fakeLocalDir.path}/track.mp3';
      await File(trackPath).create();

      final tracks = [_local(trackPath)];
      final result = await service.exportPlaylist(
        vdjRoot: vdjRoot.path,
        playlistName: 'TestSet',
        tracks: tracks,
      );

      final outFile = File(result.outputPath);
      expect(outFile.existsSync(), isTrue);
      expect(result.outputPath, endsWith('TestSet.vdjfolder'));
    });

    test('overwrites existing .vdjfolder on re-export', () async {
      final trackPath = '${fakeLocalDir.path}/track.mp3';
      await File(trackPath).create();

      final tracks = [_local(trackPath)];

      // First export
      await service.exportPlaylist(
        vdjRoot: vdjRoot.path,
        playlistName: 'Overwrite',
        tracks: tracks,
      );

      // Second export with different tracks
      final tracks2 = [
        _local(trackPath),
        _local(trackPath), // duplicate — still valid
      ];
      final result2 = await service.exportPlaylist(
        vdjRoot: vdjRoot.path,
        playlistName: 'Overwrite',
        tracks: tracks2,
      );

      final content = File(result2.outputPath).readAsStringSync();
      expect(RegExp(r'<song ').allMatches(content).length, equals(2));
    });

    test('summary counts match track list composition', () async {
      final localPath = '${fakeLocalDir.path}/local.mp3';
      await File(localPath).create();

      final tracks = [
        _local(localPath),
        _tidal('999'),
        _skipped('not found'),
      ];

      final result = await service.exportPlaylist(
        vdjRoot: vdjRoot.path,
        playlistName: 'MixedSet',
        tracks: tracks,
      );

      expect(result.totalTracks, equals(3));
      expect(result.localMatchCount, equals(1));
      expect(result.tidalCount, equals(1));
      expect(result.skippedCount, equals(1));
    });

    test('warning is set when skipped tracks exist', () async {
      final tracks = [_skipped('no match'), _skipped('no match')];

      final result = await service.exportPlaylist(
        vdjRoot: vdjRoot.path,
        playlistName: 'SkippedSet',
        tracks: tracks,
      );

      expect(result.warning, isNotNull);
    });

    test('warning is null when no tracks are skipped', () async {
      final localPath = '${fakeLocalDir.path}/good.mp3';
      await File(localPath).create();

      final result = await service.exportPlaylist(
        vdjRoot: vdjRoot.path,
        playlistName: 'CleanSet',
        tracks: [_local(localPath)],
      );

      expect(result.warning, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // TIDAL ID extraction
  // ─────────────────────────────────────────────────────────────────────────

  group('extractTidalId', () {
    test('extracts ID from /track/ URL pattern', () {
      const url = 'https://tidal.com/browse/track/123456789';
      expect(service.extractTidalId(url), equals('123456789'));
    });

    test('extracts ID from URL with query params', () {
      const url = 'https://tidal.com/browse/track/987654321?u=1';
      expect(service.extractTidalId(url), equals('987654321'));
    });

    test('returns null for non-TIDAL URL', () {
      const url = 'https://open.spotify.com/track/abc';
      expect(service.extractTidalId(url), isNull);
    });

    test('returns null for empty string', () {
      expect(service.extractTidalId(''), isNull);
    });
  });
}
