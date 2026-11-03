import 'package:shared_preferences/shared_preferences.dart';

const String _keyOnboardingCompleted = 'onboarding_complete';
const String _keyDeployAuthMethod = 'forge_deploy_auth_method';
const String _keyDeploySetupConfigured = 'forge_deploy_setup_configured';
const String _keyOpenAiApiKey = 'openai_api_key';
const String _keyLibraryPath = 'library_path';
const String _keySelectedRegions = 'selected_regions';

enum DeployAuthMethodOption {
  token,
  serviceAccount,
}

class OnboardingStorage {
  OnboardingStorage(this._prefs);

  final SharedPreferences _prefs;

  // ── Onboarding gate ──────────────────────────────────────────────────────────

  bool get hasCompletedOnboarding =>
      _prefs.getBool(_keyOnboardingCompleted) ?? false;

  Future<void> setOnboardingCompleted(bool value) async {
    await _prefs.setBool(_keyOnboardingCompleted, value);
  }

  // ── VibeRadar onboarding data ────────────────────────────────────────────────

  String? get openAiApiKey => _prefs.getString(_keyOpenAiApiKey);

  String? get libraryPath => _prefs.getString(_keyLibraryPath);

  /// Comma-separated region codes, e.g. "US,GB,GH"
  String get selectedRegions =>
      _prefs.getString(_keySelectedRegions) ?? 'US,GB,GH,NG,ZA,DE';

  List<String> get selectedRegionList =>
      selectedRegions.split(',').where((s) => s.isNotEmpty).toList();

  /// Saves all VibeRadar onboarding data and marks onboarding as complete.
  Future<void> saveVibeRadarOnboarding({
    required String apiKey,
    String? libraryPath,
    required String selectedRegions,
  }) async {
    await _prefs.setBool(_keyOnboardingCompleted, true);
    if (apiKey.isNotEmpty) {
      await _prefs.setString(_keyOpenAiApiKey, apiKey);
    }
    if (libraryPath != null && libraryPath.isNotEmpty) {
      await _prefs.setString(_keyLibraryPath, libraryPath);
    }
    if (selectedRegions.isNotEmpty) {
      await _prefs.setString(_keySelectedRegions, selectedRegions);
    }
  }

  // ── Deploy setup (legacy CodeCatalyst feature) ───────────────────────────────

  DeployAuthMethodOption get deployAuthMethod {
    final raw = _prefs.getString(_keyDeployAuthMethod);
    return DeployAuthMethodOption.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => DeployAuthMethodOption.token,
    );
  }

  bool get hasConfiguredDeploySetup =>
      _prefs.getBool(_keyDeploySetupConfigured) ?? false;

  Future<void> saveDeploySetup({
    required DeployAuthMethodOption authMethod,
    required bool configured,
  }) async {
    await _prefs.setString(_keyDeployAuthMethod, authMethod.name);
    await _prefs.setBool(_keyDeploySetupConfigured, configured);
  }

  // ── Factory ──────────────────────────────────────────────────────────────────

  static Future<OnboardingStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingStorage(prefs);
  }
}
