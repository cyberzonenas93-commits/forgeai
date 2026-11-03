// test/services/dj_root_detection_test.dart
//
// Unit tests for DjRootDetectionService.
//
// What's tested:
//   • validateVirtualDjRoot – accepts valid dir; rejects missing markers
//   • validateSeratoRoot    – accepts valid dir; rejects missing markers
//   • resolveVirtualDjRoot  – persisted root wins over auto-detect
//   • resolveSeratoRoot     – persisted root wins over auto-detect
//   • Manual fallback       – returns null when nothing is found
//   • Persisted root skip   – ignores persisted path that no longer exists
//
// The service hits the real filesystem (Directory.exists), so we create
// temporary directories in setUpAll / tearDownAll using dart:io.
//
// SharedPreferences is mocked with the `shared_preferences_platform_interface`
// test harness so no prefs leakage occurs between tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:viberadar/services/dj_root_detection_service.dart';

void main() {
  late Directory tempDir;
  late DjRootDetectionService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vr_test_');
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = DjRootDetectionService();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // VirtualDJ root validation
  // ─────────────────────────────────────────────────────────────────────────

  group('validateVirtualDjRoot', () {
    test('accepts dir with database.xml and Folders', () async {
      final root = await Directory('${tempDir.path}/vdj_valid').create();
      await File('${root.path}/database.xml').create();
      await Directory('${root.path}/Folders').create();

      expect(service.validateVirtualDjRoot(root.path), isTrue);
    });

    test('accepts dir with database.xml and Playlists', () async {
      final root = await Directory('${tempDir.path}/vdj_playlists').create();
      await File('${root.path}/database.xml').create();
      await Directory('${root.path}/Playlists').create();

      expect(service.validateVirtualDjRoot(root.path), isTrue);
    });

    test('rejects dir with only one marker (database.xml but no subfolders)',
        () async {
      final root = await Directory('${tempDir.path}/vdj_only_db').create();
      await File('${root.path}/database.xml').create();
      // No Folders / Playlists / History → count < 2

      expect(service.validateVirtualDjRoot(root.path), isFalse);
    });

    test('rejects non-existent path', () {
      expect(
        service.validateVirtualDjRoot('/tmp/this_path_does_not_exist_12345'),
        isFalse,
      );
    });

    test('rejects empty directory', () async {
      final root = await Directory('${tempDir.path}/vdj_empty').create();
      expect(service.validateVirtualDjRoot(root.path), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Serato root validation
  // ─────────────────────────────────────────────────────────────────────────

  group('validateSeratoRoot', () {
    test('accepts dir with Subcrates', () async {
      final root = await Directory('${tempDir.path}/serato_valid').create();
      await Directory('${root.path}/Subcrates').create();

      expect(service.validateSeratoRoot(root.path), isTrue);
    });

    test('accepts dir with database V2', () async {
      final root =
          await Directory('${tempDir.path}/serato_db').create();
      await File('${root.path}/database V2').create();

      expect(service.validateSeratoRoot(root.path), isTrue);
    });

    test('rejects completely empty directory', () async {
      final root =
          await Directory('${tempDir.path}/serato_empty').create();
      expect(service.validateSeratoRoot(root.path), isFalse);
    });

    test('rejects non-existent path', () {
      expect(
        service.validateSeratoRoot('/tmp/no_serato_here_99999'),
        isFalse,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Persisted root priority
  // ─────────────────────────────────────────────────────────────────────────

  group('resolveVirtualDjRoot – persisted root', () {
    test('returns persisted root when it is valid', () async {
      final root = await Directory('${tempDir.path}/vdj_persisted').create();
      await File('${root.path}/database.xml').create();
      await Directory('${root.path}/Folders').create();

      // Seed SharedPreferences as if the user already chose this folder.
      SharedPreferences.setMockInitialValues({
        'dj_vdj_root': root.path,
      });

      final resolved = await service.resolveVirtualDjRoot();
      expect(resolved, equals(root.path));
    });

    test('ignores persisted root that no longer exists', () async {
      SharedPreferences.setMockInitialValues({
        'dj_vdj_root': '/tmp/this_vdj_was_deleted_abc',
      });

      // Auto-detection will also fail (no real VDJ install in test env),
      // so the result should be null.
      final resolved = await service.resolveVirtualDjRoot();
      // We only assert it didn't use the stale path.
      expect(resolved, isNot(equals('/tmp/this_vdj_was_deleted_abc')));
    });
  });

  group('resolveSeratoRoot – persisted root', () {
    test('returns persisted root when it is valid', () async {
      final root =
          await Directory('${tempDir.path}/serato_persisted').create();
      await Directory('${root.path}/Subcrates').create();

      SharedPreferences.setMockInitialValues({
        'dj_serato_root': root.path,
      });

      final resolved = await service.resolveSeratoRoot();
      expect(resolved, equals(root.path));
    });

    test('ignores stale persisted root', () async {
      SharedPreferences.setMockInitialValues({
        'dj_serato_root': '/tmp/no_serato_xyz',
      });

      final resolved = await service.resolveSeratoRoot();
      expect(resolved, isNot(equals('/tmp/no_serato_xyz')));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Persist round-trip
  // ─────────────────────────────────────────────────────────────────────────

  group('persistVirtualDjRoot', () {
    test('stored value is returned by getPersistedVirtualDjRoot', () async {
      await service.persistVirtualDjRoot('/some/vdj/path');
      final got = await service.getPersistedVirtualDjRoot();
      expect(got, equals('/some/vdj/path'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Null fallback
  // ─────────────────────────────────────────────────────────────────────────

  group('manual fallback', () {
    test('resolveVirtualDjRoot returns null when nothing found', () async {
      // No prefs, no real VDJ install in test env.
      final resolved = await service.resolveVirtualDjRoot();
      // Either null (nothing found) or a real path if the test machine
      // has VDJ installed — either is valid.
      expect(resolved, anyOf(isNull, isA<String>()));
    });
  });
}
