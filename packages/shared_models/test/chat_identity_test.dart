import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  test('typing update prefers the public exact role-account id', () {
    final update = ChatTypingUpdate.fromJson({
      'bookingType': 'ride',
      'bookingId': 'ride-1',
      'roleAccountId': 'driver-role-account',
      'userId': 'private-auth-id-must-not-win',
      'isTyping': true,
    });

    expect(update.userId, 'driver-role-account');
  });

  test('read receipt accepts the public exact role-account id contract', () {
    final receipt = ChatReadReceipt.fromJson({
      'messageId': 'message-1',
      'readAt': '2026-07-18T12:00:00.000Z',
      'readByRoleAccountId': 'client-role-account',
    });

    expect(receipt.readBy, 'client-role-account');
  });
}
