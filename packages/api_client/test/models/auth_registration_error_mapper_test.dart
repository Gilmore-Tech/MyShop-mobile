import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

void main() {
  test('maps provider registration failures to corrective safe copy', () {
    const expectations = <String, String>{
      'CATEGORIES_REQUIRED': 'Select at least one service',
      'INVALID_CATEGORY': 'selected services is no longer available',
      'VEHICLE_DETAILS_REQUIRED': 'Complete all vehicle details',
      'INVALID_VEHICLE_PLATE': 'valid Ghana vehicle plate',
      'VEHICLE_PLATE_IN_USE': 'vehicle plate is already registered',
      'VEHICLE_CREATION_FAILED': 'contact support for help',
      'RIDE_CATEGORIES_REQUIRED': 'Select at least one ride category',
      'INVALID_RIDE_CATEGORY': 'ride categories is no longer available',
      'EMAIL_ALREADY_EXISTS': 'email is already used',
      'DRIVER_ACCOUNT_EXISTS': 'driver account already exists',
      'ARTISAN_ACCOUNT_EXISTS': 'artisan account already exists',
      'INVALID_REFERRAL_CODE': 'referral code is not valid',
      'SELF_REFERRAL_NOT_ALLOWED': 'cannot use a referral code owned',
      'REFERRAL_ALREADY_LINKED': 'already linked to this account',
      'SIGNUP_ATTRIBUTION_ALREADY_LINKED': 'already linked to this account',
      'ROLE_ACCOUNT_REFERRALS_SUSPENDED': 'Remove the optional referral code',
      'INVALID_PLATFORM_REFERRAL_CODE': 'promotional code is not valid',
      'PLATFORM_REFERRAL_CODE_INACTIVE': 'promotional code is no longer active',
      'PLATFORM_SIGNUP_ATTRIBUTION_SUSPENDED':
          'Promotional signup codes are temporarily unavailable',
      'INVALID_REGION': 'region is no longer available',
      'LEGAL_DOCUMENT_CHANGED': 'Terms or Privacy Notice changed',
      'LEGAL_DOCUMENTS_UNAVAILABLE':
          'Terms and Privacy Notice are temporarily unavailable',
      'INVALID_PERSON_NAME': 'Names cannot contain numbers or emojis',
      'REGISTRATION_RESTART_REQUIRED':
          'Return to account creation and try again',
      'REGISTRATION_VERIFICATION_IN_PROGRESS': 'finishing your registration',
      'REGISTRATION_VERIFICATION_RETRY':
          'registration was saved, but sign-in did not finish',
      'REGISTRATION_STATE_CHANGED': 'registration details changed',
    };

    for (final entry in expectations.entries) {
      final message = AuthErrorMapper.message(
        ApiException(
          message: 'backend prose must stay hidden',
          statusCode: 400,
          errorCode: entry.key,
        ),
      );
      expect(message, contains(entry.value), reason: entry.key);
      expect(message, isNot(contains('backend prose')), reason: entry.key);
      expect(
        message,
        isNot('Something went wrong. Please try again.'),
        reason: entry.key,
      );
    }
  });

  test('identifies only referral registration failures as removable', () {
    for (final code in const [
      'INVALID_REFERRAL_CODE',
      'SELF_REFERRAL_NOT_ALLOWED',
      'REFERRAL_ALREADY_LINKED',
      'ROLE_ACCOUNT_REFERRALS_SUSPENDED',
      'INVALID_PLATFORM_REFERRAL_CODE',
      'PLATFORM_REFERRAL_CODE_INACTIVE',
      'PLATFORM_SIGNUP_ATTRIBUTION_SUSPENDED',
      'SIGNUP_ATTRIBUTION_ALREADY_LINKED',
    ]) {
      expect(
        AuthErrorMapper.isReferralRegistrationErrorCode(code),
        isTrue,
        reason: code,
      );
    }

    expect(
      AuthErrorMapper.isReferralRegistrationErrorCode('INVALID_RIDE_CATEGORY'),
      isFalse,
    );
    expect(
      AuthErrorMapper.isReferralRegistrationErrorCode(null),
      isFalse,
    );
  });

  test('derives safe registration fields from validation summaries', () {
    const error = ValidationException(
      message: 'raw class-validator detail',
      details: {
        'validation': [
          'email must be an email',
          'each value in rideCategories must match the required format',
        ],
      },
    );

    expect(
      AuthErrorMapper.fieldErrors(error),
      const {
        'email': 'Enter a valid email address.',
        'rideCategories': 'Check this field and try again.',
      },
    );
    expect(
      AuthErrorMapper.fieldErrors(
        const ValidationException(
          message: 'raw',
          details: {
            'validation': ['attackerControlledField contains invalid data'],
          },
        ),
      ),
      isEmpty,
    );
  });

  test('keeps only a valid backend support UUID available for diagnostics', () {
    const valid = ApiException(
      message: 'database internals',
      statusCode: 400,
      errorCode: 'INVALID_REFERRAL_CODE',
      details: {
        'supportReference': '15286d11-fceb-43e6-ac0e-41f96d9a1b77',
      },
    );
    const attackerControlled = ApiException(
      message: 'database internals',
      statusCode: 400,
      errorCode: 'INVALID_REFERRAL_CODE',
      details: {'supportReference': 'paste-the-database-password'},
    );

    expect(
      AuthErrorMapper.supportReference(valid),
      '15286d11-fceb-43e6-ac0e-41f96d9a1b77',
    );
    expect(AuthErrorMapper.supportReference(attackerControlled), isNull);
    expect(AuthErrorMapper.message(valid), isNot(contains('15286d11')));
    expect(
      AuthErrorMapper.message(attackerControlled),
      isNot(contains('paste-the-database-password')),
    );
  });
}
