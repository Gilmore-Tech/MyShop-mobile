import 'package:api_client/api_client.dart';
import 'package:test/test.dart';

void main() {
  // A fixed "now" so the expiry maths is deterministic.
  final now = DateTime(2026, 7, 2);

  DocumentInfo doc({
    String status = 'approved',
    String? expiresAt,
    String providerType = 'driver',
    String documentType = 'drivers_licence',
  }) {
    return DocumentInfo(
      id: 'doc_1',
      providerType: providerType,
      documentType: documentType,
      status: status,
      isCurrent: true,
      createdAt: '2026-01-01T00:00:00Z',
      expiresAt: expiresAt,
    );
  }

  group('DocumentType.requiresExpiry', () {
    test('is true for documents with a printed expiry date', () {
      expect(DocumentType.driversLicence.requiresExpiry, isTrue);
      expect(DocumentType.roadworthinessCertificate.requiresExpiry, isTrue);
      expect(DocumentType.ghanaCard.requiresExpiry, isTrue);
      expect(DocumentType.businessRegistration.requiresExpiry, isTrue);
    });

    test('is false for documents that do not expire', () {
      expect(DocumentType.profilePhoto.requiresExpiry, isFalse);
      expect(DocumentType.tradeCertificate.requiresExpiry, isFalse);
      expect(DocumentType.nationalId.requiresExpiry, isFalse);
      expect(DocumentType.portfolioPhoto.requiresExpiry, isFalse);
      expect(DocumentType.vehicleRegistration.requiresExpiry, isFalse);
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

    test('is false for a non-approved doc even if the date has passed', () {
      final rejected =
          doc(status: 'rejected', expiresAt: '2026-06-01T00:00:00Z');
      expect(rejected.isExpired(now), isFalse);
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
  });
}
