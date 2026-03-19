import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'src/app.dart';
import 'src/core/notifications/forge_push_service.dart';
import 'src/core/observability/forge_telemetry.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(
        forgeFirebaseMessagingBackgroundHandler,
      );
      await ForgeTelemetry.instance.initialize();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(ForgeTelemetry.instance.recordFlutterError(details));
      };

      PlatformDispatcher.instance.onError = (error, stackTrace) {
        unawaited(
          ForgeTelemetry.instance.recordError(
            error,
            stackTrace,
            fatal: true,
            reason: 'platform_dispatcher',
          ),
        );
        return true;
      };

      runApp(const ProviderScope(child: ForgeAiApp()));
    },
    (error, stackTrace) {
      unawaited(
        ForgeTelemetry.instance.recordError(
          error,
          stackTrace,
          fatal: true,
          reason: 'run_zoned_guarded',
        ),
      );
    },
  );
}
