import 'package:characters/characters.dart';

/// Reusable input validators for the MyShop auth and registration flows.
///
/// Each method returns `null` when the value is valid, or an error message
/// string when it is not. This matches the Flutter `FormField.validator`
/// signature and the `errorText` parameter on [MyShopTextField].
class Validators {
  Validators._();

  // ── Name ──────────────────────────────────────────────────────────────

  static const invalidFullNameMessage =
      'Names cannot contain numbers or emojis. Use letters, spaces, hyphens, and apostrophes only.';

  static final RegExp _nameSpaceSeparator = RegExp(r'\p{Zs}+', unicode: true);
  static final RegExp _nameEdgeSpaces = RegExp(r'^ +| +$');
  static final RegExp _nameVariationSelector = RegExp(r'[\uFE0E\uFE0F]');
  static final RegExp _fullNamePattern = RegExp(
    r"^(?:(?!\u02BC)\p{L}[\p{Mn}\p{Mc}]*)+(?:[- '\u2019\u02BC\u2010\u2011](?:(?!\u02BC)\p{L}[\p{Mn}\p{Mc}]*)+)*$",
    unicode: true,
  );

  static String? fullName(String value) {
    // Normalise every Unicode space-separator to an ordinary space for the
    // validation decision, while deliberately leaving tabs, line breaks, and
    // other control characters untouched so the structural rule rejects them.
    final normalized = value
        .replaceAll(_nameSpaceSeparator, ' ')
        .replaceAll(_nameEdgeSpaces, '');
    if (normalized.isEmpty) return 'Full name is required.';
    if (_nameVariationSelector.hasMatch(normalized)) {
      return invalidFullNameMessage;
    }
    // The backend applies NFC before persistence and uses the same user-
    // perceived character semantics. Grapheme clusters keep composed and
    // decomposed names equivalent for the length limits.
    final logicalLength = normalized.characters.length;
    if (logicalLength > 120) {
      return 'Name must be 120 characters or fewer.';
    }
    final structuralMatch = _fullNamePattern.matchAsPrefix(normalized);
    if (structuralMatch == null || structuralMatch.end != normalized.length) {
      return invalidFullNameMessage;
    }
    if (logicalLength < 2) {
      return 'Name must be at least 2 characters.';
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

  /// Validates a Ghana mobile number. Accepts either the 9-digit form
  /// (`24XXXXXXX`) or the 10-digit local form with a leading `0`
  /// (`024XXXXXXX`); the latter is what most users type by habit.
  static String? ghanaPhone(String value) {
    final digits = normalizeGhanaPhoneDigits(value);
    if (digits.isEmpty) return 'Phone number is required.';
    if (digits.length != 9) return 'Enter a 9-digit Ghana phone number.';
    // After stripping any leading 0, the first digit must be a valid
    // Ghana mobile prefix (2 = MTN/AirtelTigo, 5 = Telecel/others).
    if (!RegExp(r'^[25]').hasMatch(digits)) {
      return 'Enter a valid Ghana mobile number.';
    }
    return null;
  }

  /// Validates the canonical E.164 value produced by the shared phone field
  /// when Ghana is selected.
  static String? ghanaE164Phone(String value) {
    final compact = value.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!RegExp(r'^\+233\d{9}$').hasMatch(compact)) {
      return 'Enter a valid Ghana phone number.';
    }
    return null;
  }

  /// Strip a leading `0` from a 10-digit local Ghana mobile number, returning
  /// the 9-digit form expected by the `+233` prefix. Returns digits-only for
  /// any other input so [ghanaPhone] can report the right error message.
  static String normalizeGhanaPhoneDigits(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    return digits;
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
  static String? minLength(
    String value,
    int min, [
    String fieldName = 'This field',
  ]) {
    if (value.trim().length < min) {
      return '$fieldName must be at least $min characters.';
    }
    return null;
  }
}
