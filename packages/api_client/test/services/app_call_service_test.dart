import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> sessionJson({Object? rtcToken}) => {
        'callId': 'call-123',
        'bookingType': 'ride',
        'bookingId': 'ride-123',
        'roomName': 'call:call-123',
        'status': 'accepted',
        'callerId': 'caller',
        'callerRole': 'client',
        'calleeId': 'callee',
        'calleeRole': 'driver',
        'createdAt': '2026-07-14T00:00:00Z',
        'expiresAt': '2026-07-14T01:00:00Z',
        'rtcProvider': 'cloudflare_turn',
        'rtcToken': rtcToken,
      };

  test('parses Cloudflare ICE servers', () {
    final session = AppCallSession.fromJson(
      sessionJson(
        rtcToken: {
          'iceServers': [
            {
              'urls': ['stun:stun.cloudflare.com:3478'],
            },
            {
              'urls': 'turns:turn.cloudflare.com:443?transport=tcp',
              'username': 'temporary-user',
              'credential': 'temporary-password',
            },
          ],
        },
      ),
    );

    expect(session.iceServers, hasLength(2));
    expect(session.iceServers.last['username'], 'temporary-user');
  });

  test('drops malformed ICE entries', () {
    final session = AppCallSession.fromJson(
      sessionJson(
        rtcToken: {
          'iceServers': [
            {'urls': []},
            {'urls': 42},
            {'urls': 'stun:stun.cloudflare.com:3478'},
          ],
        },
      ),
    );

    expect(session.iceServers, [
      {'urls': 'stun:stun.cloudflare.com:3478'},
    ]);
  });

  test('uses an empty list when rtcToken is absent', () {
    final session = AppCallSession.fromJson(sessionJson());
    expect(session.iceServers, isEmpty);
  });
}
