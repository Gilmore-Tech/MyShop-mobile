import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_vehicle_provider.dart';
import 'package:myshop_provider/src/features/profile/screens/vehicle_information_screen.dart';

void main() {
  ProviderVehicle vehicle(ProviderVehicleApprovalStatus status) =>
      ProviderVehicle(
        id: 'vehicle-1',
        make: 'Toyota',
        model: 'Corolla',
        year: 2018,
        plate: 'GR-1234-20',
        color: 'Silver',
        isActive: true,
        approvalStatus: status,
        version: 4,
        rejectionReason: null,
        coordinatorReviewedAt: null,
        regionalManagerReviewedAt: null,
        retirementRequestedAt: null,
        retirementRequestReason: null,
        rideCategories: const [
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
        eligible: status == ProviderVehicleApprovalStatus.approved,
        reasonCodes: const [],
      );

  final categoryService = _CategoryService();

  Widget screen({
    ProviderVehicleApprovalStatus status =
        ProviderVehicleApprovalStatus.approved,
  }) {
    return ProviderScope(
      overrides: [
        providerVehicleServiceProvider.overrideWithValue(categoryService),
        providerVehicleRideCategoriesProvider
            .overrideWith((ref) async => const [
                  ProviderRideCategoryChoice(
                      id: 'regular-id',
                      name: 'Regular',
                      slug: 'regular',
                      description: ''),
                  ProviderRideCategoryChoice(
                      id: 'comfort-id',
                      name: 'Comfort',
                      slug: 'comfort',
                      description: ''),
                ]),
        providerTypeProvider.overrideWith((ref) => ProviderType.driver),
        providerVehiclesProvider.overrideWith(
          (ref) async => ProviderVehiclesResponse(
            activeVehicleId: 'vehicle-1',
            onlineStatus: 'online',
            legacyBackfillRequired: false,
            legacyReasonCode: null,
            vehicles: [vehicle(status)],
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
    expect(find.text('Details approved'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Regular'), findsOneWidget);
    expect(
        find.text('Selected for the current online session'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Request removal'), findsOneWidget);
    expect(
      find.textContaining('Approved vehicle details are locked'),
      findsOneWidget,
    );
  });

  testWidgets('requests another category while keeping approved categories',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request categories'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Regular'), findsNothing);
    await tester.tap(find.text('Comfort'));
    await tester.pump();
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(categoryService.requested, ['comfort-id']);
    expect(categoryService.expectedVersion, 4);
    expect(find.text('Request ride categories'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('keeps a failed request open for retry', (tester) async {
    categoryService.fail = true;
    addTearDown(() => categoryService.fail = false);
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comfort'));
    await tester.pump();
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not send this request'), findsOneWidget);
    expect(find.text('Request ride categories'), findsOneWidget);
    categoryService.fail = false;
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(find.text('Request ride categories'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('does not expose direct editing while a vehicle is under review',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      screen(status: ProviderVehicleApprovalStatus.pendingCoordinator),
    );
    await tester.pumpAndSettle();

    expect(find.text('Awaiting Coordinator'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Add another vehicle'), findsOneWidget);
  });
}

class _CategoryService extends ProviderVehicleService {
  _CategoryService() : super(Dio());
  List<String>? requested;
  int? expectedVersion;
  bool fail = false;

  @override
  Future<ProviderVehicleMutationResult> requestCategories(
      {required String vehicleId,
      required int expectedVersion,
      required List<String> rideCategoryIds}) async {
    if (fail) {
      throw ApiException.fromDioException(DioException(
          requestOptions: RequestOptions(path: '/category-requests'),
          type: DioExceptionType.connectionError));
    }
    requested = rideCategoryIds;
    this.expectedVersion = expectedVersion;
    return ProviderVehicleMutationResult(
        vehicleId: vehicleId, version: expectedVersion + 1);
  }
}
