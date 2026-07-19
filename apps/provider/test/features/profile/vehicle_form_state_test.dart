import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/profile/models/vehicle_form_state.dart';

void main() {
  test('vehicle form requires all identity fields and at least one category',
      () {
    const draft = VehicleFormState();

    expect(
      draft.validate(currentUtcYear: 2026).keys,
      containsAll(<String>[
        'make',
        'model',
        'year',
        'plate',
        'color',
        'rideCategoryIds',
      ]),
    );
  });

  test('valid vehicle form keeps category IDs as vehicle-specific choices', () {
    const draft = VehicleFormState(
      make: ' Toyota ',
      model: 'Corolla',
      year: '2025',
      plate: 'GR-1234-25',
      color: 'Silver',
      rideCategoryIds: {'category-regular'},
    );

    expect(draft.validate(currentUtcYear: 2026), isEmpty);
  });

  test('plate validation runs after the transport canonicalization', () {
    const draft = VehicleFormState(
      make: 'Toyota',
      model: 'Corolla',
      year: '2025',
      plate: 'A ',
      color: 'Silver',
      rideCategoryIds: {'category-regular'},
    );

    expect(draft.normalizedPlate, 'A');
    expect(draft.canonicalPlate, 'A');
    expect(
      draft.validate(currentUtcYear: 2026),
      containsPair('plate', isNotEmpty),
    );
  });

  test('plate canonical form must contain an alphanumeric character', () {
    const draft = VehicleFormState(
      make: 'Toyota',
      model: 'Corolla',
      year: '2025',
      plate: ' -- ',
      color: 'Silver',
      rideCategoryIds: {'category-regular'},
    );

    expect(draft.normalizedPlate, '--');
    expect(draft.canonicalPlate, isEmpty);
    expect(
      draft.validate(currentUtcYear: 2026),
      containsPair('plate', isNotEmpty),
    );
  });

  test('provider edit stops after RM approval or a removal request', () {
    expect(
      VehicleLifecycleStatus.pendingCoordinator
          .canProviderEdit(removalRequested: false),
      isTrue,
    );
    expect(
      VehicleLifecycleStatus.coordinatorApproved
          .canProviderEdit(removalRequested: false),
      isTrue,
    );
    expect(
      VehicleLifecycleStatus.approved.canProviderEdit(removalRequested: false),
      isFalse,
    );
    expect(
      VehicleLifecycleStatus.rejected.canProviderEdit(removalRequested: true),
      isFalse,
    );
  });
}
