import 'package:shared_preferences/shared_preferences.dart';

const String _keyOnboardingCompleted = 'forge_onboarding_completed';
const String _keyDeployAuthMethod = 'forge_deploy_auth_method';
const String _keyDeploySetupConfigured = 'forge_deploy_setup_configured';

enum DeployAuthMethodOption {
  token,
  serviceAccount,
}

class OnboardingStorage {
  OnboardingStorage(this._prefs);

  final SharedPreferences _prefs;

  bool get hasCompletedOnboarding =>
      _prefs.getBool(_keyOnboardingCompleted) ?? false;

  Future<void> setOnboardingCompleted(bool value) async {
    await _prefs.setBool(_keyOnboardingCompleted, value);
  }

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

  static Future<OnboardingStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingStorage(prefs);
  }
}
