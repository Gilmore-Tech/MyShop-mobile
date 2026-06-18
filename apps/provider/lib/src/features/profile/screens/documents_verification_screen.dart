import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../providers/provider_type_provider.dart';
import '../providers/verification_provider.dart';

/// Documents & Verification — adapts to the active provider role.
///
/// - **Driver** sees: Driver's License, Roadworthiness, Vehicle Insurance,
///   Ghana Card.
/// - **Artisan** sees core required docs (Ghana Card, Business Certificate,
///   Trade Certificate) plus optional SME documents.
///
/// PRD Reference: PRD 5.5 — provider verification & compliance.
class DocumentsVerificationScreen extends ConsumerWidget {
  const DocumentsVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArtisan = ref.watch(providerTypeProvider).isArtisan;
    final user = ref.watch(currentUserProvider);
    final completion = ref.watch(profileCompletionProvider);
    final verificationAsync = ref.watch(verificationStatusProvider);
    final uploadState = ref.watch(documentUploadProvider);

    // Build doc lists based on role, using real backend status where available
    final backendDocs = verificationAsync.whenOrNull(
          data: (status) => status.documents,
        ) ??
        const <DocumentInfo>[];

    final requiredDocs = isArtisan
        ? _buildArtisanRequired(user, backendDocs, uploadState)
        : _buildDriverRequired(user, backendDocs, uploadState);
    // Artisans must provide the Ghana Card PLUS any one of these trade
    // credentials (not all of them).
    final oneOfDocs = isArtisan
        ? _buildArtisanOneOf(backendDocs, uploadState)
        : const <_DocItem>[];
    final optionalDocs = isArtisan
        ? _buildArtisanOptional(backendDocs, uploadState)
        : const <_DocItem>[];

    final uploadedRequired =
        requiredDocs.where((d) => d.status != _DocStatus.missing).length;
    final oneOfSatisfied =
        oneOfDocs.any((d) => d.status != _DocStatus.missing);
    // The "any one of" group counts as a single requirement towards progress:
    // satisfied as soon as one credential is uploaded.
    final docsCompleted =
        uploadedRequired + (oneOfDocs.isEmpty ? 0 : (oneOfSatisfied ? 1 : 0));
    final docsTotal = requiredDocs.length + (oneOfDocs.isEmpty ? 0 : 1);

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.lg,
                ),
                children: [
                  _ProgressCard(
                    completed: completion.completed,
                    total: completion.total,
                    docsCompleted: docsCompleted,
                    docsTotal: docsTotal,
                    isArtisan: isArtisan,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: _SectionLabel(
                          icon: Icons.task_alt,
                          label: 'REQUIRED DOCUMENTS',
                          iconColor: MyShopColors.error,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: MyShopColors.errorLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Mandatory',
                          style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _DocsCard(
                    items: requiredDocs,
                    providerType: isArtisan ? 'artisan' : 'driver',
                    ref: ref,
                  ),
                  if (oneOfDocs.isNotEmpty) ...[
                    const SizedBox(height: MyShopSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: _SectionLabel(
                            icon: Icons.rule,
                            label: 'PROVIDE ANY ONE',
                            iconColor: MyShopColors.error,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: oneOfSatisfied
                                ? MyShopColors.successLight
                                : MyShopColors.errorLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            oneOfSatisfied ? 'Done' : 'Pick one',
                            style: MyShopTypography.body2.copyWith(
                              color: oneOfSatisfied
                                  ? MyShopColors.success
                                  : MyShopColors.error,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Upload your Trade Certificate OR Business Registration — '
                      'whichever you have. One is enough.',
                      style: MyShopTypography.body2.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    _DocsCard(
                      items: oneOfDocs,
                      providerType: 'artisan',
                      ref: ref,
                    ),
                  ],
                  if (optionalDocs.isNotEmpty) ...[
                    const SizedBox(height: MyShopSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: _SectionLabel(
                            icon: Icons.add_circle_outline,
                            label: 'OPTIONAL DOCUMENTS',
                            iconColor: MyShopColors.textSecondary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: MyShopColors.surfaceGrey,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'For SMEs',
                            style: MyShopTypography.body2.copyWith(
                              color: MyShopColors.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add these to unlock larger contracts and stand out to enterprise clients.',
                      style: MyShopTypography.body2.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    _DocsCard(
                      items: optionalDocs,
                      providerType: 'artisan',
                      ref: ref,
                    ),
                  ],
                  const SizedBox(height: MyShopSpacing.lg),
                  const _PolicyNote(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build doc lists from real data ──

  static List<_DocItem> _buildDriverRequired(
    AuthUser? user,
    List<DocumentInfo> docs,
    DocumentUploadState uploadState,
  ) {
    final dp = user?.driverProfile;
    return [
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.driversLicence,
        icon: Icons.badge_outlined,
        title: "Driver's License",
        fallbackMeta: dp?.licenceExpiry != null
            ? 'Expires: ${dp!.licenceExpiry}'
            : 'Tap to upload',
        fallbackStatus: dp?.licenceNumber != null
            ? _DocStatus.approved
            : _DocStatus.missing,
      ),
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.roadworthinessCertificate,
        icon: Icons.directions_car_outlined,
        title: 'Roadworthiness Certificate',
        fallbackMeta: 'Tap to upload',
        fallbackStatus: _DocStatus.missing,
      ),
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.vehicleRegistration,
        icon: Icons.shield_outlined,
        title: 'Vehicle Registration',
        fallbackMeta: 'Tap to upload',
        fallbackStatus: _DocStatus.missing,
      ),
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.ghanaCard,
        icon: Icons.credit_card,
        title: 'Ghana Card',
        fallbackMeta: dp?.ghanaCardVerified == true
            ? 'Verified'
            : 'Tap to upload front & back',
        fallbackStatus: dp?.ghanaCardVerified == true
            ? _DocStatus.approved
            : _DocStatus.missing,
      ),
    ];
  }

  /// Strictly mandatory artisan documents — only the Ghana Card. The trade
  /// credential is a separate "provide any one" group (see [_buildArtisanOneOf]).
  static List<_DocItem> _buildArtisanRequired(
    AuthUser? user,
    List<DocumentInfo> docs,
    DocumentUploadState uploadState,
  ) {
    final ap = user?.artisanProfile;
    return [
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.ghanaCard,
        icon: Icons.credit_card,
        title: 'Ghana Card',
        fallbackMeta:
            ap?.ghanaCardVerified == true ? 'Verified' : 'Tap to upload',
        fallbackStatus: ap?.ghanaCardVerified == true
            ? _DocStatus.approved
            : _DocStatus.missing,
      ),
    ];
  }

  /// The trade credential — an artisan must supply **any one** of these
  /// alongside the Ghana Card (not all of them).
  static List<_DocItem> _buildArtisanOneOf(
    List<DocumentInfo> docs,
    DocumentUploadState uploadState,
  ) {
    return [
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.businessRegistration,
        icon: Icons.business_outlined,
        title: 'Business Registration Certificate',
        fallbackMeta: 'Tap to upload',
        fallbackStatus: _DocStatus.missing,
      ),
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.tradeCertificate,
        icon: Icons.workspace_premium_outlined,
        title: 'Trade Certificate',
        fallbackMeta: 'Tap to upload',
        fallbackStatus: _DocStatus.missing,
      ),
    ];
  }

  static List<_DocItem> _buildArtisanOptional(
    List<DocumentInfo> docs,
    DocumentUploadState uploadState,
  ) {
    return [
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.nationalId,
        icon: Icons.description_outlined,
        title: 'National ID',
        fallbackMeta: 'Recommended for VAT-eligible jobs',
        fallbackStatus: _DocStatus.missing,
      ),
      const _DocItem(
        icon: Icons.health_and_safety_outlined,
        title: 'Public Liability Insurance',
        meta: 'Optional · unlocks enterprise contracts',
        status: _DocStatus.missing,
        documentType: null,
      ),
      const _DocItem(
        icon: Icons.school_outlined,
        title: 'Professional Body Membership',
        meta: 'e.g. GNAT, GIA, GIE',
        status: _DocStatus.missing,
        documentType: null,
      ),
    ];
  }

  /// Merge backend document info with a fallback for when the endpoint
  /// returns no data (fresh account or endpoint not available).
  static _DocItem _docItemFromBackend({
    required List<DocumentInfo> docs,
    required DocumentUploadState uploadState,
    required DocumentType type,
    required IconData icon,
    required String title,
    required String fallbackMeta,
    required _DocStatus fallbackStatus,
  }) {
    // Check if just uploaded in this session
    if (uploadState.uploaded[type.value] == true) {
      return _DocItem(
        icon: icon,
        title: title,
        meta: 'Uploaded — pending review',
        status: _DocStatus.uploaded,
        documentType: type,
      );
    }

    // Check if uploading right now
    if (uploadState.uploading[type.value] == true) {
      return _DocItem(
        icon: icon,
        title: title,
        meta: 'Uploading...',
        status: _DocStatus.uploading,
        documentType: type,
      );
    }

    // Check backend documents list
    final doc = docs
        .where((d) => d.documentType == type.value && d.isCurrent)
        .firstOrNull;

    if (doc != null) {
      if (doc.isApproved) {
        return _DocItem(
          icon: icon,
          title: title,
          meta:
              doc.expiresAt != null ? 'Expires: ${doc.expiresAt}' : 'Approved',
          status: _DocStatus.approved,
          documentType: type,
        );
      } else if (doc.isRejected) {
        return _DocItem(
          icon: icon,
          title: title,
          meta: doc.rejectionReason ?? 'Rejected — please re-upload',
          status: _DocStatus.rejected,
          documentType: type,
        );
      } else if (doc.isPendingReview) {
        return _DocItem(
          icon: icon,
          title: title,
          meta: 'Pending admin review',
          status: _DocStatus.pendingReview,
          documentType: type,
        );
      } else {
        // uploaded — file not yet in storage
        return _DocItem(
          icon: icon,
          title: title,
          meta: 'Processing upload…',
          status: _DocStatus.uploaded,
          documentType: type,
        );
      }
    }

    // No backend data — use fallback from profile fields
    return _DocItem(
      icon: icon,
      title: title,
      meta: fallbackMeta,
      status: fallbackStatus,
      documentType: type,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.sm,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          Text(
            'Documents & Verification',
            style: MyShopTypography.h1.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress card — shows both profile completion and document progress
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.completed,
    required this.total,
    required this.docsCompleted,
    required this.docsTotal,
    required this.isArtisan,
  });

  final int completed;
  final int total;
  final int docsCompleted;
  final int docsTotal;
  final bool isArtisan;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    final percentage = (progress * 100).round();
    final isComplete = completed == total;
    final accent = isComplete ? MyShopColors.success : MyShopColors.primaryGold;
    final accentLight =
        isComplete ? MyShopColors.successLight : MyShopColors.primaryGoldLight;

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: accentLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.4),
                ),
                child: Icon(
                  isComplete ? Icons.check : Icons.schedule,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isComplete
                          ? 'Profile verification complete'
                          : 'Complete your verification',
                      style: MyShopTypography.h3.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$percentage% complete · $docsCompleted of $docsTotal docs uploaded',
                      style: MyShopTypography.body2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: MyShopColors.surfaceWhite,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: MyShopSpacing.sm),
        Text(
          label,
          style: MyShopTypography.overline.copyWith(
            color: MyShopColors.textSecondary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Doc item + status
// ─────────────────────────────────────────────────────────────────────────────

/// Maps to the backend document status flow:
///   uploaded → presigned URL given, file not yet in storage
///   pendingReview → file in storage, awaiting admin review
///   approved → admin approved
///   rejected → admin rejected
///   uploading → local upload in progress (client-only state)
///   missing → no document uploaded yet (client-only state)
enum _DocStatus {
  approved,
  pendingReview,
  uploaded,
  uploading,
  rejected,
  missing
}

class _DocItem {
  const _DocItem({
    required this.icon,
    required this.title,
    required this.meta,
    required this.status,
    this.documentType,
  });

  final IconData icon;
  final String title;
  final String meta;
  final _DocStatus status;
  final DocumentType? documentType;
}

class _DocsCard extends StatelessWidget {
  const _DocsCard({
    required this.items,
    required this.providerType,
    required this.ref,
  });

  final List<_DocItem> items;
  final String providerType;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _DocRow(
              item: items[i],
              providerType: providerType,
              ref: ref,
            ),
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: MyShopSpacing.md,
                endIndent: MyShopSpacing.md,
                color: MyShopColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.item,
    required this.providerType,
    required this.ref,
  });

  final _DocItem item;
  final String providerType;
  final WidgetRef ref;

  bool get _canUpload =>
      item.status == _DocStatus.missing || item.status == _DocStatus.rejected;

  Future<void> _handleUpload(BuildContext context) async {
    if (item.documentType == null) return;

    final file = await MediaPickerHelper.pickDocumentWithCamera(context);
    if (file == null || !context.mounted) return;

    final error = await ref.read(documentUploadProvider.notifier).upload(
          providerType: providerType,
          documentType: item.documentType!,
          file: file,
        );

    if (error != null && context.mounted) {
      MyShopToast.show(context, message: error, type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _canUpload ? () => _handleUpload(context) : null,
      child: Padding(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 20, color: MyShopColors.textPrimary),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: MyShopTypography.h3.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (item.status != _DocStatus.missing &&
                          item.status != _DocStatus.uploading)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.access_time,
                            size: 12,
                            color: MyShopColors.textSecondary,
                          ),
                        ),
                      if (item.status == _DocStatus.uploading)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: MyShopColors.primaryGold,
                            ),
                          ),
                        ),
                      Flexible(
                        child: Text(
                          item.meta,
                          style: MyShopTypography.body2.copyWith(
                            color: item.status == _DocStatus.rejected
                                ? MyShopColors.error
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: MyShopSpacing.sm),
            _StatusPill(status: item.status),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final _DocStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, String label, IconData icon) = switch (status) {
      _DocStatus.approved => (
          MyShopColors.successLight,
          MyShopColors.success,
          'Approved',
          Icons.check_circle_outline,
        ),
      _DocStatus.pendingReview => (
          MyShopColors.warningLight,
          MyShopColors.warning,
          'In Review',
          Icons.hourglass_top,
        ),
      _DocStatus.uploaded => (
          MyShopColors.surfaceGrey,
          MyShopColors.textSecondary,
          'Processing',
          Icons.cloud_done_outlined,
        ),
      _DocStatus.uploading => (
          MyShopColors.primaryGoldLight,
          MyShopColors.primaryGold,
          'Uploading',
          Icons.cloud_upload_outlined,
        ),
      _DocStatus.rejected => (
          MyShopColors.errorLight,
          MyShopColors.error,
          'Rejected',
          Icons.cancel_outlined,
        ),
      _DocStatus.missing => (
          MyShopColors.surfaceWhite,
          MyShopColors.primaryGold,
          'Upload',
          Icons.upload_outlined,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status == _DocStatus.missing ? MyShopColors.primaryGold : bg,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: MyShopTypography.body2.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Policy note
// ─────────────────────────────────────────────────────────────────────────────

class _PolicyNote extends StatelessWidget {
  const _PolicyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 18,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              'Documents are encrypted in transit and reviewed by our compliance team within 24 hours.',
              style: MyShopTypography.body2.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
