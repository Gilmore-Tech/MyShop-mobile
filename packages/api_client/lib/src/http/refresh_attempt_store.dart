import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Durable retry binding for one refresh-token credential.
///
/// The attempt identifier is not authentication on its own. It prevents a
/// party holding only a just-rotated predecessor token from using the server's
/// short response-loss recovery window. Implementations must persist the
/// identifier before the request is sent and return it for every retry of the
/// same refresh token.
abstract interface class RefreshAttemptStore {
  Future<String> readOrCreate(String refreshToken);

  /// Deletes only the record for this exact token/attempt pair. This must be
  /// called only after the successor token pair has been persisted.
  Future<void> clearIfMatches({
    required String refreshToken,
    required String attemptId,
  });
}

String refreshTokenDigest(String refreshToken) =>
    sha256.convert(utf8.encode(refreshToken)).toString();

bool isCanonicalRefreshAttemptId(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$').hasMatch(value)) {
    return false;
  }
  try {
    return base64Url.decode('$value=').length == 32;
  } on FormatException {
    return false;
  }
}

String generateRefreshAttemptId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = Uint8List.fromList(
    List<int>.generate(32, (_) => source.nextInt(256)),
  );
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Safe process-local fallback for tests and non-production TokenStorage
/// implementations. Production uses SecureTokenStorage.
class VolatileRefreshAttemptStore implements RefreshAttemptStore {
  final Map<String, String> _attempts = <String, String>{};

  @override
  Future<String> readOrCreate(String refreshToken) async {
    final digest = refreshTokenDigest(refreshToken);
    return _attempts.putIfAbsent(digest, generateRefreshAttemptId);
  }

  @override
  Future<void> clearIfMatches({
    required String refreshToken,
    required String attemptId,
  }) async {
    final digest = refreshTokenDigest(refreshToken);
    if (_attempts[digest] == attemptId) {
      _attempts.remove(digest);
    }
  }
}
