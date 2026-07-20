import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

void main() {
  // A fixed "now" so the expiry maths is deterministic.
  final now = DateTime.utc(2026, 7, 2);

  DocumentInfo doc({
    String id = 'doc_1',
    String status = 'approved',
    String? expiresAt,
    String providerType = 'driver',
    String documentType = 'drivers_licence',
    bool isCurrent = true,
    int version = 1,
    String createdAt = '2026-01-01T00:00:00Z',
    bool? expired,
    bool? providerReplacementAllowed,
  }) {
    return DocumentInfo(
      id: id,
      providerType: providerType,
      documentType: documentType,
      status: status,
      isCurrent: isCurrent,
      version: version,
      createdAt: createdAt,
      expiresAt: expiresAt,
      expired: expired,
      providerReplacementAllowed: providerReplacementAllowed,
    );
  }

  group('DocumentType.requiresExpiry', () {
    test('is true for documents with a printed expiry date', () {
      expect(DocumentType.driversLicence.requiresExpiry, isTrue);
      expect(DocumentType.roadworthinessCertificate.requiresExpiry, isTrue);
      expect(DocumentType.vehicleInsurance.requiresExpiry, isTrue);
    });

    test('is false for documents that do not expire', () {
      expect(DocumentType.profilePhoto.requiresExpiry, isFalse);
      expect(DocumentType.tradeCertificate.requiresExpiry, isFalse);
      expect(DocumentType.nationalId.requiresExpiry, isFalse);
      expect(DocumentType.portfolioPhoto.requiresExpiry, isFalse);
      expect(DocumentType.vehicleRegistration.requiresExpiry, isFalse);
      expect(DocumentType.ghanaCard.requiresExpiry, isFalse);
      expect(DocumentType.businessRegistration.requiresExpiry, isFalse);
    });
  });

  group('DocumentInfo.expiresAtDate', () {
    test('is null when no expiry is set', () {
      expect(doc().expiresAtDate, isNull);
    });

    test('parses an ISO expiry string', () {
      final parsed = doc(expiresAt: '2026-08-12T00:00:00Z').expiresAtDate;
      expect(parsed, isNotNull);
      expect(parsed!.toUtc().year, 2026);
      expect(parsed.toUtc().month, 8);
    });

    test('is null for an unparseable value', () {
      expect(doc(expiresAt: 'not-a-date').expiresAtDate, isNull);
    });
  });

  group('DocumentInfo review chain', () {
    test('keeps Admin and Coordinator decisions provisional', () {
      final adminVerified = doc(status: 'confirmed');
      final coordinatorValidated = doc(status: 'coordinator_validated');

      expect(adminVerified.isAdminVerified, isTrue);
      expect(coordinatorValidated.isCoordinatorValidated, isTrue);
      expect(adminVerified.isSubmitted, isTrue);
      expect(coordinatorValidated.isSubmitted, isTrue);
      expect(adminVerified.isApproved, isFalse);
      expect(coordinatorValidated.isApproved, isFalse);
    });
  });

  group('DocumentInfo.isExpired', () {
    test('is false when there is no expiry date', () {
      expect(doc().isExpired(now), isFalse);
    });

    test('is true when an approved doc is past its expiry', () {
      expect(doc(expiresAt: '2026-06-01T00:00:00Z').isExpired(now), isTrue);
    });

    test('is false when the expiry is still in the future', () {
      expect(doc(expiresAt: '2026-12-01T00:00:00Z').isExpired(now), isFalse);
    });

    test('is false throughout the printed expiry date in GMT', () {
      final d = doc(expiresAt: '2026-07-17');
      expect(d.isExpired(DateTime.utc(2026, 7, 17, 23, 59, 59, 999)), isFalse);
    });

    test('becomes invalid at 00:00 GMT on the following day', () {
      final d = doc(expiresAt: '2026-07-17T00:00:00.000Z');
      expect(d.isExpired(DateTime.utc(2026, 7, 18)), isTrue);
    });

    test('is false for a non-approved doc even if the date has passed', () {
      final rejected =
          doc(status: 'rejected', expiresAt: '2026-06-01T00:00:00Z');
      expect(rejected.isExpired(now), isFalse);
    });

    test('prefers server expiry authority over a conflicting handset clock',
        () {
      expect(
        doc(expiresAt: '2020-01-01', expired: false).isExpired(now),
        isFalse,
      );
      expect(
        doc(expiresAt: '2099-01-01', expired: true).isExpired(now),
        isTrue,
      );
    });
  });

  group('DocumentInfo.canProviderReplace', () {
    test('keeps a valid approved document closed', () {
      expect(
        doc(
          expiresAt: '2099-01-01',
          expired: false,
          providerReplacementAllowed: false,
        ).canProviderReplace(now),
        isFalse,
      );
    });

    test('opens an expired approved document using server authority', () {
      expect(
        doc(
          expiresAt: '2099-01-01',
          expired: true,
          providerReplacementAllowed: true,
        ).canProviderReplace(now),
        isTrue,
      );
    });

    test('never gives the provider control of an approved profile photo', () {
      expect(
        doc(documentType: 'profile_photo').canProviderReplace(now),
        isFalse,
      );
    });
  });

  group('DocumentInfo.isExpiringSoon', () {
    test('is true when expiry falls inside the default 30-day window', () {
      final d = doc(expiresAt: '2026-07-20T00:00:00Z'); // 18 days out
      expect(d.isExpiringSoon(now: now), isTrue);
    });

    test('is false when expiry is well beyond the window', () {
      final d = doc(expiresAt: '2026-10-01T00:00:00Z');
      expect(d.isExpiringSoon(now: now), isFalse);
    });

    test('is false once already expired', () {
      final d = doc(expiresAt: '2026-06-01T00:00:00Z');
      expect(d.isExpiringSoon(now: now), isFalse);
      expect(d.isExpired(now), isTrue);
    });

    test('honours a custom window', () {
      final d = doc(expiresAt: '2026-07-20T00:00:00Z'); // 18 days out
      expect(
        d.isExpiringSoon(now: now, within: const Duration(days: 7)),
        isFalse,
      );
    });
  });

  group('VerificationStatusResponse.documentFor', () {
    test('can scope lookup to the active provider role', () {
      final response = VerificationStatusResponse(
        documents: [
          doc(
            providerType: 'artisan',
            documentType: DocumentType.ghanaCard.value,
          ),
          doc(
            providerType: 'driver',
            documentType: DocumentType.ghanaCard.value,
            status: 'pending_review',
          ),
        ],
      );

      expect(
        response
            .documentFor(
              DocumentType.ghanaCard.value,
              providerType: 'driver',
            )
            ?.status,
        'pending_review',
      );
      expect(
        response
            .documentFor(
              DocumentType.ghanaCard.value,
              providerType: 'artisan',
            )
            ?.status,
        'approved',
      );
    });

    test('does not let a sibling role satisfy a missing active-role document',
        () {
      final response = VerificationStatusResponse(
        documents: [
          doc(
            providerType: 'artisan',
            documentType: DocumentType.ghanaCard.value,
          ),
        ],
      );

      expect(
        response.documentFor(
          DocumentType.ghanaCard.value,
          providerType: 'driver',
        ),
        isNull,
      );
      expect(response.documentFor(DocumentType.ghanaCard.value), isNotNull);
    });

    test('chooses the newest row deterministically within a policy tier', () {
      final response = VerificationStatusResponse(
        documents: [
          doc(
            id: 'pending-v1',
            status: 'pending_review',
            version: 1,
          ),
          doc(
            id: 'pending-v2',
            status: 'pending_review',
            version: 2,
          ),
        ],
      );

      expect(response.documentFor('drivers_licence')?.id, 'pending-v2');
      expect(
        response.documentFor('drivers_licence')?.status,
        'pending_review',
      );
    });

    test('falls back to the newest approved legacy row when none is current',
        () {
      final response = VerificationStatusResponse(
        documents: [
          doc(id: 'v1', isCurrent: false, version: 1),
          doc(id: 'v2', isCurrent: false, version: 2),
        ],
      );

      expect(response.documentFor('drivers_licence')?.id, 'v2');
    });
  });

  group('VerificationStatusResponse.providerVerificationStatus', () {
    test('distinguishes an omitted role block from an explicit pending status',
        () {
      const omitted = VerificationStatusResponse(documents: []);
      const pending = VerificationStatusResponse(
        driverData: {'verificationStatus': 'pending'},
        documents: [],
      );

      expect(omitted.providerVerificationStatus('driver'), isNull);
      expect(pending.providerVerificationStatus('driver'), 'pending');
      expect(pending.isProviderFullyApproved('driver'), isFalse);
    });
  });
}
