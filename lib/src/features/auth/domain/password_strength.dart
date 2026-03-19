/// Requirements for a strong password and validation result.
class PasswordStrength {
  const PasswordStrength._();

  static const int minLength = 10;

  static bool hasMinLength(String value) =>
      value.length >= minLength;

  static bool hasUppercase(String value) =>
      value.contains(RegExp(r'[A-Z]'));

  static bool hasLowercase(String value) =>
      value.contains(RegExp(r'[a-z]'));

  static bool hasDigit(String value) =>
      value.contains(RegExp(r'[0-9]'));

  static bool hasSpecialChar(String value) =>
      value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;/`~]'));

  /// Returns null if valid, or an error message.
  static String? validate(String? value) {
    final s = value ?? '';
    if (s.isEmpty) return 'Enter a password.';
    if (!hasMinLength(s)) return 'Use at least $minLength characters.';
    if (!hasUppercase(s)) return 'Include at least one uppercase letter.';
    if (!hasLowercase(s)) return 'Include at least one lowercase letter.';
    if (!hasDigit(s)) return 'Include at least one number.';
    if (!hasSpecialChar(s)) return 'Include at least one special character (!@#\$%^&* etc.).';
    return null;
  }

  /// Number of requirements met (0..5).
  static int requirementsMet(String value) {
    var n = 0;
    if (hasMinLength(value)) n++;
    if (hasUppercase(value)) n++;
    if (hasLowercase(value)) n++;
    if (hasDigit(value)) n++;
    if (hasSpecialChar(value)) n++;
    return n;
  }

  static const List<String> requirementLabels = [
    'At least $minLength characters',
    'One uppercase letter',
    'One lowercase letter',
    'One number',
    'One special character (!@#\$%^&* etc.)',
  ];
}
