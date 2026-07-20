enum VehicleLifecycleStatus {
  pendingCoordinator,
  coordinatorApproved,
  approved,
  rejected,
  retired,
}

extension VehicleLifecycleStatusUi on VehicleLifecycleStatus {
  String get label => switch (this) {
        VehicleLifecycleStatus.pendingCoordinator => 'Awaiting Coordinator',
        VehicleLifecycleStatus.coordinatorApproved =>
          'Awaiting Regional Manager',
        VehicleLifecycleStatus.approved => 'Approved',
        VehicleLifecycleStatus.rejected => 'Rejected',
        VehicleLifecycleStatus.retired => 'Retired',
      };

  bool canProviderEdit({required bool removalRequested}) =>
      this != VehicleLifecycleStatus.approved &&
      this != VehicleLifecycleStatus.retired &&
      !removalRequested;
}

class VehicleFormState {
  const VehicleFormState({
    this.make = '',
    this.model = '',
    this.year = '',
    this.plate = '',
    this.color = '',
    this.rideCategoryIds = const {},
  });

  final String make;
  final String model;
  final String year;
  final String plate;
  final String color;
  final Set<String> rideCategoryIds;

  VehicleFormState copyWith({
    String? make,
    String? model,
    String? year,
    String? plate,
    String? color,
    Set<String>? rideCategoryIds,
  }) {
    return VehicleFormState(
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      plate: plate ?? this.plate,
      color: color ?? this.color,
      rideCategoryIds: rideCategoryIds ?? this.rideCategoryIds,
    );
  }

  String get normalizedPlate => plate.trim().toUpperCase();

  String get canonicalPlate =>
      normalizedPlate.replaceAll(RegExp('[^A-Z0-9]'), '');

  Map<String, String> validate({int? currentUtcYear}) {
    final errors = <String, String>{};
    final maxYear = (currentUtcYear ?? DateTime.now().toUtc().year) + 1;
    final parsedYear = int.tryParse(year.trim());

    if (make.trim().isEmpty) errors['make'] = 'Enter the vehicle make.';
    if (model.trim().isEmpty) errors['model'] = 'Enter the vehicle model.';
    if (parsedYear == null || parsedYear < 1 || parsedYear > maxYear) {
      errors['year'] = 'Enter a whole-number year from 1 to $maxYear.';
    }
    if (normalizedPlate.length < 2 ||
        normalizedPlate.length > 32 ||
        canonicalPlate.isEmpty) {
      errors['plate'] = 'Enter a valid registration plate.';
    }
    if (color.trim().isEmpty) errors['color'] = 'Enter the vehicle colour.';
    if (rideCategoryIds.isEmpty) {
      errors['rideCategoryIds'] = 'Select at least one ride category.';
    }
    return errors;
  }

  bool isValid({int? currentUtcYear}) =>
      validate(currentUtcYear: currentUtcYear).isEmpty;
}
