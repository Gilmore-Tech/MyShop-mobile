import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/features/profile/screens/emergency_contacts_screen.dart';

class _MockUserService extends Mock implements UserService {}

void main() {
  testWidgets('loads only the authenticated provider-role contact collection',
      (tester) async {
    final service = _MockUserService();
    when(service.getEmergencyContacts).thenAnswer(
      (_) async => [
        {
          'id': 'driver-contact-1',
          'name': 'Akua Driver Contact',
          'phone': '+233241234567',
          'relationship': 'Sister',
          'isPrimary': true,
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [userServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: ProviderEmergencyContactsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Akua Driver Contact'), findsOneWidget);
    expect(
        find.textContaining('only to your current driver or artisan account'),
        findsOneWidget);
    expect(find.text('1 of 3 contacts added for this provider role.'),
        findsOneWidget);
    verify(service.getEmergencyContacts).called(1);
  });

  testWidgets('zero-contact role stays truthful and offers contact setup',
      (tester) async {
    final service = _MockUserService();
    when(service.getEmergencyContacts).thenAnswer((_) async => []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [userServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: ProviderEmergencyContactsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No contacts added for this role yet'), findsOneWidget);
    expect(find.text('Add emergency contact'), findsOneWidget);
    expect(find.text('0 of 3 contacts added for this provider role.'),
        findsOneWidget);
  });
}
