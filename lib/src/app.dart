import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/firebase/firebase_providers.dart';
import 'core/firebase/forge_firebase_readiness.dart';
import 'shared/forge_models.dart';
import 'core/config/forge_release_config.dart';
import 'core/notifications/forge_push_controller.dart';
import 'core/notifications/forge_push_service.dart';
import 'core/observability/forge_telemetry.dart';
import 'core/branding/app_branding.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/onboarding/presentation/onboarding_gate.dart';
import 'features/screenshot/presentation/forge_screenshot_studio.dart';
import 'features/splash/presentation/forge_splash_screen.dart';
import 'features/workspace/application/forge_workspace_controller.dart';
import 'features/workspace/data/forge_workspace_repository.dart';
import 'shell/forge_home_shell.dart';

final authControllerProvider = Provider<AuthController>((ref) {
  final controller = AuthController(
    telemetry: ref.watch(forgeTelemetryProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final forgeWorkspaceRepositoryProvider = Provider<ForgeWorkspaceRepository>((
  ref,
) {
  return ForgeWorkspaceRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
  );
});

final workspaceControllerProvider = Provider<ForgeWorkspaceController>((ref) {
  final authController = ref.watch(authControllerProvider);
  final controller = !forgeHasInitializedFirebaseApp()
      ? ForgeWorkspaceController.preview(authController: authController)
      : ForgeWorkspaceController(
          repository: ref.watch(forgeWorkspaceRepositoryProvider),
          authController: authController,
          telemetry: ref.watch(forgeTelemetryProvider),
        );
  ref.onDispose(controller.dispose);
  return controller;
});

final forgePushServiceProvider = Provider<ForgePushService>((ref) {
  return ForgePushService();
});

final forgePushControllerProvider = Provider<ForgePushController>((ref) {
  final workspaceController = ref.watch(workspaceControllerProvider);
  final authController = ref.watch(authControllerProvider);
  final telemetry = ref.watch(forgeTelemetryProvider);
  final controller = !forgeHasInitializedFirebaseApp()
      ? ForgePushController.preview(
          authController: authController,
          telemetry: telemetry,
        )
      : ForgePushController(
          service: ref.watch(forgePushServiceProvider),
          authController: authController,
          registerToken:
              ({
                required String token,
                required String platform,
                required ForgePushPermissionStatus permissionStatus,
              }) {
                return workspaceController.registerPushToken(
                  token: token,
                  platform: platform,
                  permissionStatus: permissionStatus,
                );
              },
          unregisterToken: workspaceController.unregisterPushToken,
          telemetry: telemetry,
        );
  ref.onDispose(controller.dispose);
  return controller;
});

class ForgeAiApp extends ConsumerWidget {
  const ForgeAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(forgeTelemetryProvider);
    if (ForgeReleaseConfig.enableScreenshotStudio) {
      return MaterialApp(
        title: kAppDisplayName,
        debugShowCheckedModeBanner: false,
        theme: ForgeAiTheme.dark(),
        navigatorObservers: telemetry.navigatorObservers,
        home: ForgeScreenshotStudio(scene: ForgeReleaseConfig.screenshotScene),
      );
    }

    final controller = ref.watch(authControllerProvider);
    final workspaceController = ref.watch(workspaceControllerProvider);
    final pushController = ref.watch(forgePushControllerProvider);

    return MaterialApp(
      title: kAppDisplayName,
      debugShowCheckedModeBanner: false,
      theme: ForgeAiTheme.dark(),
      navigatorObservers: telemetry.navigatorObservers,
      home: ForgeSplashScreen(
        child: OnboardingGate(
          child: AuthGate(
            controller: controller,
            signedInBuilder: (context, account) => ForgeHomeShell(
              controller: controller,
              account: account,
              workspaceController: workspaceController,
              pushController: pushController,
              firebaseFunctions: forgeHasInitializedFirebaseApp()
                  ? ref.read(firebaseFunctionsProvider)
                  : null,
            ),
            loadingBuilder: (context) => const _ForgeLoadingScreen(),
          ),
        ),
      ),
    );
  }
}

class _ForgeLoadingScreen extends StatelessWidget {
  const _ForgeLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: ForgeAiTheme.backgroundGradient,
      ),
      child: const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
