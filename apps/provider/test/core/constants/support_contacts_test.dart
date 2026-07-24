import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/constants/support_contacts.dart';

void main() {
  test('provider support uses the owner-approved monitored mailbox', () {
    expect(providerSupportEmail, 'support@gilmoretechnologiesgh.com');
  });
}
