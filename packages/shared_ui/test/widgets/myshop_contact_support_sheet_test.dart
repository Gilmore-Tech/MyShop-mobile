import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  test('WhatsApp destinations require exact E.164 digits without plus', () {
    expect(
      SupportChannels.validWhatsAppNumber('233242924671'),
      '233242924671',
    );
    expect(SupportChannels.validWhatsAppNumber(null), isNull);
    expect(SupportChannels.validWhatsAppNumber(''), isNull);
    expect(SupportChannels.validWhatsAppNumber('+233242924671'), isNull);
    expect(SupportChannels.validWhatsAppNumber('233 242 924 671'), isNull);
    expect(SupportChannels.validWhatsAppNumber('0242924671'), isNull);
    expect(SupportChannels.validWhatsAppNumber('2333000000000000'), isNull);
  });

  testWidgets('unverified WhatsApp is hidden while ticket and email remain', (
    tester,
  ) async {
    var openedTicket = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyShopContactSupportSheet(
            whatsappNumber: '233 024 292 4671',
            supportEmail: 'support@example.test',
            onNewTicket: () => openedTicket = true,
          ),
        ),
      ),
    );

    expect(find.text('WhatsApp'), findsNothing);
    expect(find.text('Open a ticket'), findsOneWidget);
    expect(find.text('Email us'), findsOneWidget);

    await tester.tap(find.text('Open a ticket'));
    await tester.pump();
    expect(openedTicket, isTrue);
  });

  testWidgets('a verified WhatsApp destination is rendered exactly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyShopContactSupportSheet(
            whatsappNumber: '233242924671',
            supportEmail: 'support@example.test',
            onNewTicket: () {},
          ),
        ),
      ),
    );

    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('+233242924671'), findsOneWidget);
  });
}
