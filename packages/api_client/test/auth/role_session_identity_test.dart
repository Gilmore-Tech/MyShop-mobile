import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

String _token(Map<String, Object?> claims) {
  final header =
      base64Url.encode(utf8.encode('{"alg":"none"}')).replaceAll('=', '');
  final payload =
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  return '$header.$payload.signature';
}

void main() {
  test(
    'parses the exact subject, role account and sid from an access token',
    () {
      final identity = RoleSessionIdentity.tryParseAccessToken(
        _token(const {
          'sub': 'private-auth-id',
          'role': 'client',
          'roleAccountId': 'client-role-id',
          'sid': 'session-id',
        }),
      );

      expect(identity?.subject, 'private-auth-id');
      expect(identity?.role, 'client');
      expect(identity?.roleAccountId, 'client-role-id');
      expect(identity?.sessionId, 'session-id');
    },
  );

  test('rejects malformed, legacy and unsupported-role tokens', () {
    expect(RoleSessionIdentity.tryParseAccessToken('not-a-jwt'), isNull);
    expect(
      RoleSessionIdentity.tryParseAccessToken(
        _token(const {'role': 'client', 'roleAccountId': 'client-role-id'}),
      ),
      isNull,
    );
    expect(
      RoleSessionIdentity.tryParseAccessToken(
        _token(const {
          'role': 'client',
          'roleAccountId': 'client-role-id',
          'sid': 'session-id',
        }),
      ),
      isNull,
    );
    expect(
      RoleSessionIdentity.tryParseAccessToken(
        _token(const {
          'role': 'admin',
          'roleAccountId': 'admin-id',
          'sid': 'session-id',
        }),
      ),
      isNull,
    );
  });

  test(
    'scoped legal status belongs only to its exact role-account session',
    () {
      const snapshot = ScopedLegalConsentStatus(
        identity: RoleSessionIdentity(
          subject: 'private-auth-id',
          role: 'driver',
          roleAccountId: 'driver-a',
          sessionId: 'sid-a',
        ),
        status: LegalConsentStatus(
          role: 'driver',
          current: false,
          requiresConsent: true,
          hasActiveWork: false,
          missingSlugs: ['terms'],
          documents: [],
        ),
      );

      expect(
        snapshot.belongsTo(
          const RoleSessionIdentity(
            subject: 'private-auth-id',
            role: 'driver',
            roleAccountId: 'driver-a',
            sessionId: 'sid-a',
          ),
        ),
        isTrue,
      );
      expect(
        snapshot.belongsTo(
          const RoleSessionIdentity(
            subject: 'private-auth-id',
            role: 'driver',
            roleAccountId: 'driver-b',
            sessionId: 'sid-a',
          ),
        ),
        isFalse,
      );
      expect(
        snapshot.belongsTo(
          const RoleSessionIdentity(
            subject: 'private-auth-id',
            role: 'artisan',
            roleAccountId: 'driver-a',
            sessionId: 'sid-a',
          ),
        ),
        isFalse,
      );
      expect(
        snapshot.belongsTo(
          const RoleSessionIdentity(
            subject: 'private-auth-id',
            role: 'driver',
            roleAccountId: 'driver-a',
            sessionId: 'sid-b',
          ),
        ),
        isFalse,
      );
      expect(
        snapshot.belongsTo(
          const RoleSessionIdentity(
            subject: 'different-private-auth-id',
            role: 'driver',
            roleAccountId: 'driver-a',
            sessionId: 'sid-a',
          ),
        ),
        isFalse,
      );
    },
  );
}
