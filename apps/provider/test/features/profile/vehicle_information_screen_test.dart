import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_vehicle_provider.dart';
import 'package:myshop_provider/src/features/profile/screens/vehicle_information_screen.dart';

void main() {
  const vehicle = ProviderVehicle(
    id: 'vehicle-1',
    make: 'Toyota',
    model: 'Corolla',
    year: 2018,
    plate: 'GR-1234-20',
    color: 'Silver',
    isActive: true,
    approvalStatus: ProviderVehicleApprovalStatus.approved,
    version: 4,
    rejectionReason: null,
    coordinatorReviewedAt: null,
    regionalManagerReviewedAt: null,
    retirementRequestedAt: null,
    retirementRequestReason: null,
    rideCategories: [
      ProviderVehicleCategoryAssignment(
        id: 'regular-id',
        name: 'Regular',
        slug: 'regular',
        isActive: true,
        status: ProviderVehicleCategoryStatus.approved,
        rejectionReason: null,
        reviewedAt: null,
      ),
    ],
    pendingRevision: null,
    eligible: true,
    reasonCodes: [],
  );

  Widget screen() {
    return ProviderScope(
      overrides: [
        providerTypeProvider.overrideWith((ref) => ProviderType.driver),
        providerVehiclesProvider.overrideWith(
          (ref) async => const ProviderVehiclesResponse(
            activeVehicleId: 'vehicle-1',
            onlineStatus: 'online',
            legacyBackfillRequired: false,
            legacyReasonCode: null,
            vehicles: [vehicle],
          ),
        ),
      ],
      child: const MaterialApp(home: VehicleInformationScreen()),
    );
  }

  testWidgets('shows server vehicle lifecycle and category authority',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();

    expect(find.text('Toyota Corolla'), findsOneWidget);
    expect(find.textContaining('GR-1234-20'), findsOneWidget);
    expect(find.text('Approved'), findsNWidgets(2));
    expect(find.text('Regular'), findsOneWidget);
    expect(
        find.text('Selected for the current online session'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Request removal'), findsOneWidget);
  });
}
