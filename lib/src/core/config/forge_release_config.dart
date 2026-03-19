class ForgeReleaseConfig {
  static const String _environmentPrimary = String.fromEnvironment(
    'FORGEAI_ENV',
    defaultValue: '',
  );
  static const String _environmentLegacy = String.fromEnvironment(
    'FORGEAI_APP_ENV',
    defaultValue: 'beta',
  );
  static const String environment = _environmentPrimary == ''
      ? _environmentLegacy
      : _environmentPrimary;
  static const bool enableAnalytics = bool.fromEnvironment(
    'FORGEAI_ENABLE_ANALYTICS',
    defaultValue: true,
  );
  static const bool enableCrashlytics = bool.fromEnvironment(
    'FORGEAI_ENABLE_CRASHLYTICS',
    defaultValue: true,
  );
  static const bool enableScreenshotStudio =
      bool.fromEnvironment(
        'FORGEAI_ENABLE_SCREENSHOT_STUDIO',
        defaultValue: false,
      ) ||
      bool.fromEnvironment(
        'FORGEAI_ENABLE_SCREENSHOT_ROUTES',
        defaultValue: false,
      );
  static const String screenshotScene = String.fromEnvironment(
    'FORGEAI_SCREENSHOT_SCENE',
    defaultValue: 'dashboard',
  );
  static const String _betaChannelPrimary = String.fromEnvironment(
    'FORGEAI_BETA_CHANNEL',
    defaultValue: '',
  );
  static const String _betaChannelLegacy = String.fromEnvironment(
    'FORGEAI_RELEASE_CHANNEL',
    defaultValue: 'internal',
  );
  static const String betaChannel = _betaChannelPrimary == ''
      ? _betaChannelLegacy
      : _betaChannelPrimary;
  static const bool enableIapInDebug = bool.fromEnvironment(
    'FORGEAI_ENABLE_IAP_DEBUG',
    defaultValue: false,
  );
}
