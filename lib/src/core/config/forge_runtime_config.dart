class ForgeRuntimeConfig {
  const ForgeRuntimeConfig({
    required this.appEnv,
    required this.firebaseProjectId,
    required this.firebaseRegion,
    required this.releaseChannel,
    required this.enableAnalytics,
    required this.enableCrashlytics,
    required this.enableScreenshotRoutes,
    required this.screenshotScene,
    required this.bootWithPreviewData,
  });

  static const ForgeRuntimeConfig current = ForgeRuntimeConfig(
    appEnv: String.fromEnvironment('FORGEAI_APP_ENV', defaultValue: 'beta'),
    firebaseProjectId: String.fromEnvironment(
      'FORGEAI_FIREBASE_PROJECT_ID',
      defaultValue: 'forgeai-555ee',
    ),
    firebaseRegion: String.fromEnvironment(
      'FORGEAI_FIREBASE_REGION',
      defaultValue: 'us-central1',
    ),
    releaseChannel: String.fromEnvironment(
      'FORGEAI_RELEASE_CHANNEL',
      defaultValue: 'beta',
    ),
    enableAnalytics: bool.fromEnvironment(
      'FORGEAI_ENABLE_ANALYTICS',
      defaultValue: true,
    ),
    enableCrashlytics: bool.fromEnvironment(
      'FORGEAI_ENABLE_CRASHLYTICS',
      defaultValue: true,
    ),
    enableScreenshotRoutes: bool.fromEnvironment(
      'FORGEAI_ENABLE_SCREENSHOT_ROUTES',
      defaultValue: false,
    ),
    screenshotScene: String.fromEnvironment('FORGEAI_SCREENSHOT_SCENE'),
    bootWithPreviewData: bool.fromEnvironment(
      'FORGEAI_BOOT_WITH_PREVIEW_DATA',
      defaultValue: false,
    ),
  );

  final String appEnv;
  final String firebaseProjectId;
  final String firebaseRegion;
  final String releaseChannel;
  final bool enableAnalytics;
  final bool enableCrashlytics;
  final bool enableScreenshotRoutes;
  final String screenshotScene;
  final bool bootWithPreviewData;

  bool get bootIntoPreview =>
      bootWithPreviewData || screenshotScene.trim().isNotEmpty;
}
