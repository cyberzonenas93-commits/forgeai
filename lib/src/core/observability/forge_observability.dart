import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/forge_runtime_config.dart';

class ForgeObservability {
  ForgeObservability._();

  static final ForgeObservability instance = ForgeObservability._();

  FirebaseAnalytics? _analytics;
  FirebaseCrashlytics? _crashlytics;
  PackageInfo? _packageInfo;

  List<NavigatorObserver> get navigatorObservers {
    final analytics = _analytics;
    if (analytics == null) {
      return const <NavigatorObserver>[];
    }
    return <NavigatorObserver>[FirebaseAnalyticsObserver(analytics: analytics)];
  }

  Future<void> bootstrap({required ForgeRuntimeConfig runtime}) async {
    if (Firebase.apps.isEmpty) {
      return;
    }

    _packageInfo ??= await PackageInfo.fromPlatform();
    if (runtime.enableAnalytics) {
      _analytics = FirebaseAnalytics.instance;
      await _analytics!.setAnalyticsCollectionEnabled(true);
      await _analytics!.setUserProperty(name: 'release_channel', value: runtime.releaseChannel);
      await _analytics!.setUserProperty(name: 'app_env', value: runtime.appEnv);
    }

    if (runtime.enableCrashlytics) {
      _crashlytics = FirebaseCrashlytics.instance;
      await _crashlytics!.setCrashlyticsCollectionEnabled(true);
      await _crashlytics!.setCustomKey('release_channel', runtime.releaseChannel);
      await _crashlytics!.setCustomKey('app_env', runtime.appEnv);
      await _crashlytics!.setCustomKey(
        'app_version',
        _packageInfo?.version ?? 'unknown',
      );
    }

    await recordEvent(
      'forgeai_app_boot',
      parameters: <String, Object?>{
        'release_channel': runtime.releaseChannel,
        'app_env': runtime.appEnv,
        'app_version': _packageInfo?.version ?? 'unknown',
        'build_number': _packageInfo?.buildNumber ?? 'unknown',
        'preview_mode': runtime.bootIntoPreview,
      },
    );
  }

  void recordFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(
      recordNonFatal(
        details.exception,
        details.stack ?? StackTrace.current,
        reason: details.context?.toDescription() ?? 'flutter_error',
      ),
    );
  }

  Future<void> recordEvent(
    String name, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    final analytics = _analytics;
    if (analytics == null) {
      return;
    }
    await analytics.logEvent(
      name: _sanitizeName(name),
      parameters: _sanitizeParameters(parameters),
    );
  }

  Future<void> recordScreen(String screenName) {
    final analytics = _analytics;
    if (analytics == null) {
      return Future<void>.value();
    }
    return analytics.logScreenView(screenName: screenName);
  }

  Future<void> recordNonFatal(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    await recordEvent(
      'forgeai_nonfatal',
      parameters: <String, Object?>{
        'reason': reason,
        ...context,
      },
    );

    final crashlytics = _crashlytics;
    if (crashlytics == null) {
      return;
    }
    await crashlytics.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: false,
      information: context.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .toList(),
    );
  }

  Future<void> trackOperationSuccess(
    String name, {
    required int durationMs,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    return recordEvent(
      '${_sanitizeName(name)}_success',
      parameters: <String, Object?>{
        'duration_ms': durationMs,
        ...context,
      },
    );
  }

  Future<void> trackOperationFailure(
    String name,
    Object error,
    StackTrace stackTrace, {
    required int durationMs,
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    await recordEvent(
      '${_sanitizeName(name)}_failure',
      parameters: <String, Object?>{
        'duration_ms': durationMs,
        'error_type': error.runtimeType.toString(),
        ...context,
      },
    );
    await recordNonFatal(
      error,
      stackTrace,
      reason: name,
      context: <String, Object?>{
        'duration_ms': durationMs,
        ...context,
      },
    );
  }

  String _sanitizeName(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  }

  Map<String, Object> _sanitizeParameters(Map<String, Object?> parameters) {
    final sanitized = <String, Object>{};
    for (final entry in parameters.entries) {
      final key = _sanitizeName(entry.key);
      final value = entry.value;
      if (value == null) {
        continue;
      }
      if (value is num || value is bool) {
        sanitized[key] = value;
      } else {
        sanitized[key] = '$value';
      }
    }
    return sanitized;
  }
}
