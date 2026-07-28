import 'dart:convert';

import 'package:shared_models/shared_models.dart';

/// Exact role-session identity carried by a MyShop access token.
///
/// Decoding here is used only to scope local cache/state. It is never an
/// authorization decision: the backend remains the authority for every
/// protected operation.
class RoleSessionIdentity {
  const RoleSessionIdentity({
    required this.subject,
    required this.role,
    required this.roleAccountId,
    required this.sessionId,
  });

  /// Reads the non-secret identity claims from a JWT payload.
  ///
  /// Returns null for malformed/legacy tokens instead of guessing. A caller
  /// must treat null as "status unavailable", never as legal non-compliance.
  static RoleSessionIdentity? tryParseAccessToken(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;

    try {
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final payload = jsonDecode(decoded);
      if (payload is! Map) return null;
      final claims = Map<String, dynamic>.from(payload);
      final subject = _nonEmptyString(claims['sub']);
      final role = _nonEmptyString(claims['role']);
      final roleAccountId = _nonEmptyString(claims['roleAccountId']);
      final sessionId = _nonEmptyString(claims['sid']);
      if (subject == null ||
          role == null ||
          roleAccountId == null ||
          sessionId == null) {
        return null;
      }
      if (role != 'client' && role != 'driver' && role != 'artisan') {
        return null;
      }
      return RoleSessionIdentity(
        subject: subject,
        role: role,
        roleAccountId: roleAccountId,
        sessionId: sessionId,
      );
    } catch (_) {
      return null;
    }
  }

  final String subject;
  final String role;
  final String roleAccountId;
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is RoleSessionIdentity &&
      other.subject == subject &&
      other.role == role &&
      other.roleAccountId == roleAccountId &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(subject, role, roleAccountId, sessionId);
}

/// A consent response bound to the exact authenticated role and session that
/// fetched it. This prevents a cached response from one sibling role, account,
/// or prior login from gating the current UI.
class ScopedLegalConsentStatus {
  const ScopedLegalConsentStatus({
    required this.identity,
    required this.status,
  });

  final RoleSessionIdentity identity;
  final LegalConsentStatus status;

  bool belongsTo(RoleSessionIdentity currentIdentity) =>
      identity == currentIdentity && status.role == currentIdentity.role;
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
