/// Reusable input validators for the MyShop auth and registration flows.
///
/// Each method returns `null` when the value is valid, or an error message
/// string when it is not. This matches the Flutter `FormField.validator`
/// signature and the `errorText` parameter on [MyShopTextField].
class Validators {
  Validators._();

  // ── Name ──────────────────────────────────────────────────────────────

  static String? fullName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Full name is required.';
    if (trimmed.length < 3) return 'Name must be at least 3 characters.';
    if (!RegExp(r"^[a-zA-ZÀ-ÿ\s\-']+$").hasMatch(trimmed)) {
      return 'Name can only contain letters, spaces, and hyphens.';
    }
    return null;
  }

  // ── Email ─────────────────────────────────────────────────────────────

  static String? email(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Email is required.';
    // Simple but effective RFC-style check.
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    if (!emailRegex.hasMatch(trimmed)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  // ── Ghana Card ────────────────────────────────────────────────────────

  /// Ghana Card format: GHA-XXXXXXXXX-X (3 letters, dash, 9 digits, dash,
  /// 1 digit). We also accept without dashes for convenience and normalise.
  static String? ghanaCard(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed.isEmpty) return 'Ghana Card number is required.';
    // Accept with or without dashes
    final withDashes = RegExp(r'^GHA-\d{9}-\d$');
    final noDashes = RegExp(r'^GHA\d{10}$');
    if (!withDashes.hasMatch(trimmed) && !noDashes.hasMatch(trimmed)) {
      return 'Enter a valid Ghana Card (e.g. GHA-123456789-0).';
    }
    return null;
  }

  // ── Phone ─────────────────────────────────────────────────────────────

  /// Validates a 9-digit Ghana phone number (without the +233 prefix).
  static String? ghanaPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Phone number is required.';
    if (digits.length != 9) return 'Enter a 9-digit Ghana phone number.';
    // First digit should be 2, 5, or 0 (valid Ghana mobile prefixes)
    if (!RegExp(r'^[250]').hasMatch(digits)) {
      return 'Enter a valid Ghana mobile number.';
    }
    return null;
  }

  // ── Vehicle ───────────────────────────────────────────────────────────

  /// Vehicle year must be 4 digits between 1990 and next year.
  static String? vehicleYear(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Vehicle year is required.';
    final year = int.tryParse(trimmed);
    if (year == null || trimmed.length != 4) return 'Enter a 4-digit year.';
    final currentYear = DateTime.now().year;
    if (year < 1990 || year > currentYear + 1) {
      return 'Year must be between 1990 and ${currentYear + 1}.';
    }
    return null;
  }

  /// Ghana license plate format: XX 1234-YY or XX-1234-YY.
  /// Region code (2 letters), space or dash, 1-4 digits, dash, 2 digits.
  static String? licensePlate(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed.isEmpty) return 'License plate is required.';
    final plateRegex = RegExp(r'^[A-Z]{2}[\s\-]?\d{1,4}[\s\-]?\d{2}$');
    if (!plateRegex.hasMatch(trimmed)) {
      return 'Enter a valid plate (e.g. GR 1234-20).';
    }
    return null;
  }

  // ── Generic helpers ───────────────────────────────────────────────────

  /// Field must not be empty.
  static String? required(String value, [String fieldName = 'This field']) {
    if (value.trim().isEmpty) return '$fieldName is required.';
    return null;
  }

  /// Field must have a minimum length.
  static String? minLength(String value, int min, [String fieldName = 'This field']) {
    if (value.trim().length < min) {
      return '$fieldName must be at least $min characters.';
    }
    return null;
  }
}
