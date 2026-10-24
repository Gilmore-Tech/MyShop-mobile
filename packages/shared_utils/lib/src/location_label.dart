final RegExp _leadingPlusCode = RegExp(
  r'^[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}(?=\s*(?:,|$))',
  caseSensitive: false,
);

/// Returns a driver-friendly location label without changing its map point.
///
/// Google can prefix otherwise useful addresses with a Plus Code, for example
/// `MCFG+RPC, Queens Rd, Kumasi, Ghana`. The code identifies the same precise
/// coordinate but is harder to recognise while driving, so only that leading
/// segment is removed. Named premises, roads, neighbourhoods and cities remain
/// untouched.
String humanReadableLocationLabel(
  String? raw, {
  String fallback = 'Pinned location',
}) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return fallback;
  if (!_leadingPlusCode.hasMatch(value)) return value;

  final withoutCode = value.replaceFirst(_leadingPlusCode, '').trimLeft();
  final cleaned = withoutCode.replaceFirst(RegExp(r'^,\s*'), '').trim();
  return cleaned.isEmpty ? fallback : cleaned;
}
