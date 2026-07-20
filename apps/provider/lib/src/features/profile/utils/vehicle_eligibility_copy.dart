const _vehicleEligibilityCopy = <String, String>{
  'ROLE_ACCOUNT_NOT_ACTIVE':
      'This provider account is not active. Contact support.',
  'LEGACY_VEHICLE_BACKFILL_REQUIRED':
      'Support must finish migrating this vehicle record.',
  'VEHICLE_NOT_AVAILABLE':
      'This vehicle is not approved and available for online work.',
  'VEHICLE_RIDE_CATEGORY_NOT_APPROVED':
      'At least one active ride category must be approved.',
  'VEHICLE_DOCUMENT_MISSING_ROADWORTHINESS':
      'Upload this vehicle’s roadworthiness certificate.',
  'VEHICLE_DOCUMENT_NOT_APPROVED_ROADWORTHINESS':
      'The roadworthiness certificate is awaiting approval or was rejected.',
  'VEHICLE_DOCUMENT_EXPIRY_MISSING_ROADWORTHINESS':
      'The approved roadworthiness certificate needs an expiry date from support.',
  'VEHICLE_DOCUMENT_EXPIRED_ROADWORTHINESS':
      'The roadworthiness certificate has expired.',
  'VEHICLE_DOCUMENT_MISSING_INSURANCE':
      'Upload this vehicle’s insurance certificate.',
  'VEHICLE_DOCUMENT_NOT_APPROVED_INSURANCE':
      'The insurance certificate is awaiting approval or was rejected.',
  'VEHICLE_DOCUMENT_EXPIRY_MISSING_INSURANCE':
      'The approved insurance certificate needs an expiry date from support.',
  'VEHICLE_DOCUMENT_EXPIRED_INSURANCE':
      'The insurance certificate has expired.',
  'OFFER_RECEIPT_CAPABILITY_REQUIRED':
      'Notification delivery must be ready before you can go online.',
  'RM_FINAL_APPROVAL_REQUIRED': 'Regional Manager approval is required.',
  'PROVIDER_APPROVAL_REQUIRED': 'Final provider approval is required.',
  'DOCUMENT_MISSING_GHANA_CARD': 'Upload your Ghana Card.',
  'DOCUMENT_NOT_APPROVED_GHANA_CARD':
      'Your Ghana Card is awaiting approval or was rejected.',
  'DOCUMENT_MISSING_DRIVERS_LICENCE': "Upload your driver's licence.",
  'DOCUMENT_NOT_APPROVED_DRIVERS_LICENCE':
      "Your driver's licence is awaiting approval or was rejected.",
  'DOCUMENT_EXPIRY_MISSING_DRIVERS_LICENCE':
      "The approved driver's licence needs an expiry date from support.",
  'DOCUMENT_EXPIRED_DRIVERS_LICENCE': "Your driver's licence has expired.",
  'DOCUMENT_MISSING_PROFILE_PHOTO': 'Upload a profile photo.',
  'DOCUMENT_NOT_APPROVED_PROFILE_PHOTO':
      'Your profile photo is awaiting approval or was rejected.',
  'DOCUMENT_REPLACEMENT_GRACE_EXPIRED':
      'A document replacement grace period has ended.',
};

List<String> vehicleEligibilityMessages(List<String> reasonCodes) {
  final messages = <String>[];
  for (final code in reasonCodes.toSet()) {
    final message = _vehicleEligibilityCopy[code];
    if (message != null && !messages.contains(message)) messages.add(message);
  }
  if (messages.isEmpty) {
    messages.add(
      'This vehicle is not currently eligible. Review Documents & Verification.',
    );
  }
  return List.unmodifiable(messages);
}

String vehicleEligibilitySummary(List<String> reasonCodes) =>
    vehicleEligibilityMessages(reasonCodes).join('\n');
