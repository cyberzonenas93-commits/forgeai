import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../features/auth/domain/auth_account.dart';
import '../firebase/forge_firebase_readiness.dart';
import '../config/forge_release_config.dart';

final forgeTelemetryProvider = Provider<ForgeTelemetry>(
  (ref) => ForgeTelemetry.instance,
);

class ForgeTelemetry {
  ForgeTelemetry._();

  static final ForgeTelemetry instance = ForgeTelemetry._();

  FirebaseAnalytics? get _analytics =>
      ForgeReleaseConfig.enableAnalytics && _firebaseReady
      ? FirebaseAnalytics.instance
      : null;
  FirebaseCrashlytics? get _crashlytics =>
      ForgeReleaseConfig.enableCrashlytics && _firebaseReady
      ? FirebaseCrashlytics.instance
      : null;
  PackageInfo? _packageInfo;

  bool get _firebaseReady => forgeHasInitializedFirebaseApp();

  List<NavigatorObserver> get navigatorObservers {
    final analytics = _analytics;
    if (analytics == null) {
      return const <NavigatorObserver>[];
    }
    return <NavigatorObserver>[FirebaseAnalyticsObserver(analytics: analytics)];
  }

  Future<void> initialize() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    if (!_firebaseReady) {
      return;
    }
    await _analytics?.setAnalyticsCollectionEnabled(
      ForgeReleaseConfig.enableAnalytics,
    );
    await _crashlytics?.setCrashlyticsCollectionEnabled(
      ForgeReleaseConfig.enableCrashlytics,
    );
    if (_packageInfo != null) {
      await _analytics?.setUserProperty(
        name: 'app_version',
        value: _packageInfo!.version,
      );
      await _crashlytics?.setCustomKey('app_version', _packageInfo!.version);
      await _crashlytics?.setCustomKey(
        'build_number',
        _packageInfo!.buildNumber,
      );
    }
    await _crashlytics?.setCustomKey(
      'environment',
      ForgeReleaseConfig.environment,
    );
    await _crashlytics?.setCustomKey(
      'beta_channel',
      ForgeReleaseConfig.betaChannel,
    );
    await logEvent(
      'forge_app_boot',
      parameters: <String, Object?>{
        'environment': ForgeReleaseConfig.environment,
        'beta_channel': ForgeReleaseConfig.betaChannel,
        'app_version': _packageInfo?.version,
        'build_number': _packageInfo?.buildNumber,
      },
    );
  }

  Future<void> attachUser(AuthAccount? account) async {
    if (account == null) {
      await _analytics?.resetAnalyticsData();
      await _crashlytics?.setUserIdentifier('');
      return;
    }

    await _analytics?.setUserId(id: account.id);
    await _analytics?.setUserProperty(
      name: 'auth_provider',
      value: account.provider.name,
    );
    await _analytics?.setUserProperty(
      name: 'beta_channel',
      value: ForgeReleaseConfig.betaChannel,
    );
    await _analytics?.setUserProperty(
      name: 'app_version',
      value: _packageInfo?.version,
    );
    await _crashlytics?.setUserIdentifier(account.id);
    await _crashlytics?.setCustomKey('auth_provider', account.provider.name);
    await logEvent(
      'forge_auth_state_changed',
      parameters: <String, Object?>{
        'provider': account.provider.name,
        'is_guest': account.isGuest ? 1 : 0,
      },
    );
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    final analytics = _analytics;
    if (analytics == null) {
      return;
    }
    await analytics.logEvent(name: name, parameters: _sanitize(parameters));
  }

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? reason,
    Iterable<Object> information = const <Object>[],
  }) async {
    final crashlytics = _crashlytics;
    if (crashlytics == null) {
      return;
    }
    await crashlytics.recordError(
      error,
      stackTrace,
      fatal: fatal,
      reason: reason,
      information: information,
    );
  }

  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    final crashlytics = _crashlytics;
    if (crashlytics == null) {
      return;
    }
    await crashlytics.recordFlutterFatalError(details);
  }

  Map<String, Object> _sanitize(Map<String, Object?> values) {
    final output = <String, Object>{};
    values.forEach((key, value) {
      if (value == null) {
        return;
      }
      if (value is String || value is num) {
        output[key] = value;
      } else {
        output[key] = value.toString();
      }
    });
    return output;
  }
}
