import 'package:shared_preferences/shared_preferences.dart';

const String _keyOnboardingCompleted = 'forge_onboarding_completed';

class OnboardingStorage {
  OnboardingStorage(this._prefs);

  final SharedPreferences _prefs;

  bool get hasCompletedOnboarding =>
      _prefs.getBool(_keyOnboardingCompleted) ?? false;

  Future<void> setOnboardingCompleted(bool value) async {
    await _prefs.setBool(_keyOnboardingCompleted, value);
  }

  static Future<OnboardingStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingStorage(prefs);
  }
}
