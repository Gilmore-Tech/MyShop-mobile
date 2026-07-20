import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../providers/provider_type_provider.dart';
import '../providers/provider_vehicle_provider.dart';
import '../providers/verification_provider.dart';

/// Documents & Verification — adapts to the active provider role.
///
/// - **Driver** sees: Driver's License, Roadworthiness, Vehicle Insurance,
///   Ghana Card.
/// - **Artisan** sees core required docs (Ghana Card, Business Certificate,
///   Trade Certificate) plus optional SME documents.
///
/// PRD Reference: PRD 5.5 — provider verification & compliance.
class DocumentsVerificationScreen extends ConsumerStatefulWidget {
  const DocumentsVerificationScreen({super.key});

  @override
  ConsumerState<DocumentsVerificationScreen> createState() =>
      _DocumentsVerificationScreenState();
}

class _DocumentsVerificationScreenState
    extends ConsumerState<DocumentsVerificationScreen> {
  String? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    // Document decisions happen server-side and the status provider is cached
    // for the session, so refetch on entry to pick up an admin approval /
    // rejection without an app restart.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(verificationStatusProvider);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(verificationStatusProvider);
    ref.invalidate(providerVehiclesProvider);
    await ref.read(verificationStatusProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final isArtisan = ref.watch(providerTypeProvider).isArtisan;
    final user = ref.watch(currentUserProvider);
    final verificationAsync = ref.watch(verificationStatusProvider);
    final uploadState = ref.watch(documentUploadProvider);

    // Once the backend reflects a submission (pending review) or an admin
    // decision (approved), retire the per-session optimistic "uploaded" flag so
    // the backend status becomes the single source of truth. Without this the
    // flag pins the row to "pending review" for the whole session and a later
    // approval never shows until the app is restarted.
    ref.listen(verificationStatusProvider, (_, next) {
      final data = next.valueOrNull;
      if (data == null) return;
      final notifier = ref.read(documentUploadProvider.notifier);
      for (final d in data.documents) {
        if (d.isCurrent && (d.isPendingReview || d.isApproved)) {
          notifier.clearUploaded(d.documentType, vehicleId: d.vehicleId);
        }
      }
    });

    // Build doc lists based on role, using real backend status where available.
    // valueOrNull (not whenOrNull(data:)) keeps the previous list visible while
    // a refresh is in flight, so pull-to-refresh / entry-refresh don't blank the
    // rows back to their fallbacks.
    final providerType = isArtisan ? 'artisan' : 'driver';
    final backendDocs =
        verificationAsync.valueOrNull?.documents ?? const <DocumentInfo>[];
    final roleDocs = backendDocs
        .where((d) => d.providerType == providerType)
        .toList(growable: false);

    final vehicleAsync = isArtisan ? null : ref.watch(providerVehiclesProvider);
    final vehicleData = vehicleAsync?.valueOrNull;
    final selectableVehicles = vehicleData?.vehicles
            .where(
              (vehicle) =>
                  vehicle.approvalStatus !=
                  ProviderVehicleApprovalStatus.retired,
            )
            .toList(growable: false) ??
        const <ProviderVehicle>[];
    final selectedVehicleId = selectableVehicles.any(
      (vehicle) => vehicle.id == _selectedVehicleId,
    )
        ? _selectedVehicleId
        : selectableVehicles.any(
            (vehicle) => vehicle.id == vehicleData?.activeVehicleId,
          )
            ? vehicleData?.activeVehicleId
            : selectableVehicles.firstOrNull?.id;

    final requiredDocs = isArtisan
        ? _buildArtisanRequired(user, roleDocs, uploadState)
        : _buildDriverRequired(
            user,
            roleDocs,
            uploadState,
            selectedVehicleId,
          );
    // Artisans must provide the Ghana Card plus exactly one trade credential.
    final oneOfDocs = isArtisan
        ? _buildArtisanOneOf(roleDocs, uploadState)
        : const <_DocItem>[];
    final optionalDocs = isArtisan
        ? _buildArtisanOptional(roleDocs, uploadState)
        : const <_DocItem>[];

    final uploadedRequired =
        requiredDocs.where((d) => d.status != _DocStatus.missing).length;
    final selectedCredentialCount =
        oneOfDocs.where((d) => d.status != _DocStatus.missing).length;
    final oneOfSatisfied = selectedCredentialCount == 1;
    final oneOfConflict = selectedCredentialCount > 1;
    // The mutually exclusive group counts as one requirement only when exactly
    // one credential is present.
    final docsCompleted =
        uploadedRequired + (oneOfDocs.isEmpty ? 0 : (oneOfSatisfied ? 1 : 0));
    final docsTotal = requiredDocs.length + (oneOfDocs.isEmpty ? 0 : 1);
    final approvedRequired =
        requiredDocs.where((document) => document.isCurrentlyApproved).length;
    final approvedCredentialCount =
        oneOfDocs.where((document) => document.isCurrentlyApproved).length;
    final docsApproved = approvedRequired +
        (oneOfDocs.isEmpty
            ? 0
            : (oneOfSatisfied && approvedCredentialCount == 1 ? 1 : 0));

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: MyShopColors.primaryGold,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    MyShopSpacing.md,
                    MyShopSpacing.md,
                    MyShopSpacing.md,
                    MyShopSpacing.lg,
                  ),
                  children: [
                    _ProgressCard(
                      docsCompleted: docsCompleted,
                      docsApproved: docsApproved,
                      docsTotal: docsTotal,
                    ),
                    if (!isArtisan) ...[
                      const SizedBox(height: MyShopSpacing.md),
                      _VehicleDocumentSelector(
                        vehicles: selectableVehicles,
                        selectedVehicleId: selectedVehicleId,
                        loading: vehicleAsync?.isLoading == true,
                        hasError: vehicleAsync?.hasError == true,
                        onRetry: () => ref.invalidate(providerVehiclesProvider),
                        onChanged: (value) {
                          setState(() => _selectedVehicleId = value);
                        },
                      ),
                    ],
                    const SizedBox(height: MyShopSpacing.lg),
                    const _SectionHeading(
                      icon: Icons.task_alt,
                      label: 'REQUIRED DOCUMENTS',
                      iconColor: MyShopColors.error,
                      badgeLabel: 'Mandatory',
                      badgeBackground: MyShopColors.errorLight,
                      badgeForeground: MyShopColors.error,
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    _DocsCard(
                      items: requiredDocs,
                      providerType: providerType,
                      ref: ref,
                    ),
                    if (oneOfDocs.isNotEmpty) ...[
                      const SizedBox(height: MyShopSpacing.lg),
                      _SectionHeading(
                        icon: Icons.rule,
                        label: 'PROVIDE EXACTLY ONE',
                        iconColor: MyShopColors.error,
                        badgeLabel: oneOfSatisfied
                            ? 'Done'
                            : oneOfConflict
                                ? 'Keep one only'
                                : 'Pick one',
                        badgeBackground: oneOfSatisfied
                            ? MyShopColors.successLight
                            : MyShopColors.errorLight,
                        badgeForeground: oneOfSatisfied
                            ? MyShopColors.success
                            : MyShopColors.error,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload either your Trade Certificate or Business Registration — '
                        'never both.',
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
                      const _SectionHeading(
                        icon: Icons.add_circle_outline,
                        label: 'OPTIONAL PROFILE & DOCUMENTS',
                        iconColor: MyShopColors.textSecondary,
                        badgeLabel: 'Does not block online',
                        badgeBackground: MyShopColors.surfaceGrey,
                        badgeForeground: MyShopColors.textSecondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'These items are reviewed independently but are not required to go online.',
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
    String? vehicleId,
  ) {
    final dp = user?.driverProfile;
    return [
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.profilePhoto,
        icon: Icons.account_circle_outlined,
        title: 'Profile Photo',
        fallbackMeta: 'Upload a clear face photo',
        fallbackStatus: _DocStatus.missing,
      ),
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.driversLicence,
        icon: Icons.badge_outlined,
        title: "Driver's License",
        fallbackMeta: dp?.licenceExpiry != null
            ? 'Expires: ${dp!.licenceExpiry}'
            : dp?.licenceNumber != null
                ? 'Licence number saved — upload document'
                : 'Tap to upload',
        fallbackStatus: _DocStatus.missing,
      ),
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.roadworthinessCertificate,
        icon: Icons.directions_car_outlined,
        title: 'Roadworthiness Certificate',
        fallbackMeta: 'Tap to upload',
        fallbackStatus: _DocStatus.missing,
        vehicleId: vehicleId,
      ),
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.vehicleInsurance,
        icon: Icons.shield_outlined,
        title: 'Insurance Certificate',
        fallbackMeta: 'Tap to upload',
        fallbackStatus: _DocStatus.missing,
        vehicleId: vehicleId,
      ),
      _docItemFromBackend(
        docs: docs,
        uploadState: uploadState,
        type: DocumentType.ghanaCard,
        icon: Icons.credit_card,
        title: 'Ghana Card',
        fallbackMeta: dp?.ghanaCardVerified == true
            ? 'Identity verified — upload document'
            : 'Tap to upload front & back',
        fallbackStatus: _DocStatus.missing,
      ),
    ];
  }

  /// Strictly mandatory artisan documents — only the Ghana Card. The trade
  /// credential is a separate "provide exactly one" group (see
  /// [_buildArtisanOneOf]).
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
        fallbackMeta: ap?.ghanaCardVerified == true
            ? 'Identity verified — upload document'
            : 'Tap to upload',
        fallbackStatus: _DocStatus.missing,
      ),
    ];
  }

  /// The trade credential — an artisan must supply exactly one of these
  /// alongside the Ghana Card.
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
        type: DocumentType.profilePhoto,
        icon: Icons.account_circle_outlined,
        title: 'Profile Photo',
        fallbackMeta: 'Optional · reviewed independently',
        fallbackStatus: _DocStatus.missing,
      ),
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

  /// Merge backend document info with a fallback for when this active role has
  /// no document row yet. Profile fields such as a typed licence number or a
  /// Ghana Card KYC flag are not document approvals. A document may only render
  /// render as approved only when its own backend row is independently approved.
  /// Aggregate provider eligibility is a separate state and must never rewrite
  /// an administrator's document-level decision.
  static _DocItem _docItemFromBackend({
    required List<DocumentInfo> docs,
    required DocumentUploadState uploadState,
    required DocumentType type,
    required IconData icon,
    required String title,
    required String fallbackMeta,
    required _DocStatus fallbackStatus,
    String? vehicleId,
  }) {
    final uploadKey = documentUploadKey(type, vehicleId: vehicleId);
    // Check if just uploaded in this session
    if (uploadState.uploaded[uploadKey] == true) {
      return _DocItem(
        icon: icon,
        title: title,
        meta: 'Uploaded — pending review',
        status: _DocStatus.uploaded,
        documentType: type,
        vehicleId: vehicleId,
      );
    }

    // Check if uploading right now
    if (uploadState.uploading[uploadKey] == true) {
      return _DocItem(
        icon: icon,
        title: title,
        meta: 'Uploading...',
        status: _DocStatus.uploading,
        documentType: type,
        vehicleId: vehicleId,
      );
    }

    // Check backend documents list
    final doc = docs
        .where(
          (d) =>
              d.documentType == type.value &&
              d.isCurrent &&
              (!type.isVehicleScoped || d.vehicleId == vehicleId),
        )
        .firstOrNull;

    if (doc != null) {
      if (doc.isApproved) {
        final expiry = doc.expiresAtDate;
        if (type.requiresExpiry && expiry == null) {
          return _DocItem(
            icon: icon,
            title: title,
            meta: 'Expiry date required — contact support',
            status: _DocStatus.expiryMissing,
            documentType: type,
            vehicleId: vehicleId,
          );
        }
        // An approved document can still lapse. Provider-controlled upload is
        // deliberately closed until the exact GMT invalidity boundary; an
        // expiring-soon row is therefore a notice, not a renewal control.
        if (doc.isExpired()) {
          return _DocItem(
            icon: icon,
            title: title,
            meta: expiry != null
                ? 'Expired ${_formatDate(expiry)} — tap to re-upload'
                : 'Expired — tap to re-upload',
            status: _DocStatus.expired,
            documentType: type,
            vehicleId: vehicleId,
          );
        }
        if (doc.isExpiringSoon()) {
          return _DocItem(
            icon: icon,
            title: title,
            meta:
                'Valid through ${_formatDate(expiry!)} · upload opens after expiry',
            status: _DocStatus.expiringSoon,
            documentType: type,
            vehicleId: vehicleId,
          );
        }
        return _DocItem(
          icon: icon,
          title: title,
          meta: type == DocumentType.profilePhoto
              ? 'Approved — contact support to change'
              : expiry != null
                  ? 'Valid until ${_formatDate(expiry)}'
                  : 'Approved',
          status: _DocStatus.approved,
          documentType: type,
          vehicleId: vehicleId,
        );
      } else if (doc.isRejected) {
        return _DocItem(
          icon: icon,
          title: title,
          meta: doc.rejectionReason ?? 'Rejected — please re-upload',
          status: _DocStatus.rejected,
          documentType: type,
          vehicleId: vehicleId,
        );
      } else if (doc.isPendingReview) {
        return _DocItem(
          icon: icon,
          title: title,
          meta: 'Pending admin review',
          status: _DocStatus.pendingReview,
          documentType: type,
          vehicleId: vehicleId,
        );
      } else if (doc.isAdminVerified) {
        return _DocItem(
          icon: icon,
          title: title,
          meta: 'Admin verified — awaiting category Coordinator',
          status: _DocStatus.adminVerified,
          documentType: type,
          vehicleId: vehicleId,
        );
      } else if (doc.isCoordinatorValidated) {
        return _DocItem(
          icon: icon,
          title: title,
          meta: 'Coordinator validated — awaiting Regional Manager',
          status: _DocStatus.coordinatorValidated,
          documentType: type,
          vehicleId: vehicleId,
        );
      } else {
        // uploaded — file not yet in storage
        return _DocItem(
          icon: icon,
          title: title,
          meta: 'Processing upload…',
          status: _DocStatus.uploaded,
          documentType: type,
          vehicleId: vehicleId,
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
      vehicleId: vehicleId,
    );
  }

  /// Human-friendly expiry date, e.g. "12 Aug 2026".
  static String _formatDate(DateTime date) =>
      DateFormat('d MMM yyyy').format(date);
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
          Expanded(
            child: Text(
              'Documents & Verification',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MyShopTypography.h1.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
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
    required this.docsCompleted,
    required this.docsApproved,
    required this.docsTotal,
  });

  final int docsCompleted;
  final int docsApproved;
  final int docsTotal;

  @override
  Widget build(BuildContext context) {
    final progress = docsTotal == 0 ? 0.0 : docsCompleted / docsTotal;
    final percentage = (progress * 100).round();
    final allUploaded = docsTotal > 0 && docsCompleted == docsTotal;
    final allApproved = docsTotal > 0 && docsApproved == docsTotal;
    final accent =
        allApproved ? MyShopColors.success : MyShopColors.primaryGold;
    final accentLight =
        allApproved ? MyShopColors.successLight : MyShopColors.primaryGoldLight;

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
                  allApproved ? Icons.check : Icons.schedule,
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
                      allApproved
                          ? 'Required documents approved'
                          : allUploaded
                              ? 'Documents require review or action'
                              : 'Complete your documents',
                      style: MyShopTypography.h3.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$percentage% uploaded · $docsCompleted of $docsTotal documents · $docsApproved approved',
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

class _VehicleDocumentSelector extends StatelessWidget {
  const _VehicleDocumentSelector({
    required this.vehicles,
    required this.selectedVehicleId,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    required this.onChanged,
  });

  final List<ProviderVehicle> vehicles;
  final String? selectedVehicleId;
  final bool loading;
  final bool hasError;
  final VoidCallback onRetry;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.infoLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.info.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vehicle for roadworthiness and insurance',
              style: MyShopTypography.body1),
          const SizedBox(height: MyShopSpacing.xs),
          Text(
            'These two documents are reviewed separately for each vehicle.',
            style: MyShopTypography.body2,
          ),
          const SizedBox(height: MyShopSpacing.sm),
          if (loading)
            const LinearProgressIndicator(color: MyShopColors.primaryGold)
          else if (hasError)
            TextButton(onPressed: onRetry, child: const Text('Retry vehicles'))
          else if (vehicles.isEmpty)
            Text(
              'Add a vehicle before uploading its documents.',
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.error,
              ),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: selectedVehicleId,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                filled: true,
                fillColor: MyShopColors.surfaceWhite,
              ),
              items: vehicles
                  .map(
                    (vehicle) => DropdownMenuItem(
                      value: vehicle.id,
                      child: Text('${vehicle.displayName} · ${vehicle.plate}'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.badgeLabel,
    required this.badgeBackground,
    required this.badgeForeground,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final String badgeLabel;
  final Color badgeBackground;
  final Color badgeForeground;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: badgeBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        badgeLabel,
        style: MyShopTypography.body2.copyWith(
          color: badgeForeground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledLabelSize =
            MediaQuery.textScalerOf(context).scale(12).toDouble();
        final stack = constraints.maxWidth < 420 || scaledLabelSize > 14;
        final sectionLabel = _SectionLabel(
          icon: icon,
          label: label,
          iconColor: iconColor,
        );

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              sectionLabel,
              const SizedBox(height: MyShopSpacing.xs),
              badge,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: sectionLabel),
            const SizedBox(width: MyShopSpacing.sm),
            badge,
          ],
        );
      },
    );
  }
}

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
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MyShopTypography.overline.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
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
///   adminVerified → Admin accepted; awaiting category Coordinator
///   coordinatorValidated → Coordinator accepted; awaiting Regional Manager
///   approved → Regional Manager gave final approval
///   rejected → admin rejected
///   expired → approved but past its expiry date (client-derived, re-uploadable)
///   expiryMissing → approved legacy record without its required expiry date
///   expiringSoon → approved and lapsing within 30 days (client-derived)
///   uploading → local upload in progress (client-only state)
///   missing → no document uploaded yet (client-only state)
enum _DocStatus {
  approved,
  pendingReview,
  adminVerified,
  coordinatorValidated,
  uploaded,
  uploading,
  rejected,
  expired,
  expiryMissing,
  expiringSoon,
  missing,
}

class _DocItem {
  const _DocItem({
    required this.icon,
    required this.title,
    required this.meta,
    required this.status,
    this.documentType,
    this.vehicleId,
  });

  final IconData icon;
  final String title;
  final String meta;
  final _DocStatus status;
  final DocumentType? documentType;
  final String? vehicleId;

  bool get isCurrentlyApproved =>
      status == _DocStatus.approved || status == _DocStatus.expiringSoon;
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
            _DocRow(item: items[i], providerType: providerType, ref: ref),
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

  bool get _canUpload {
    final type = item.documentType;
    if (type == null || (type.isVehicleScoped && item.vehicleId == null)) {
      return false;
    }
    return item.status == _DocStatus.missing ||
        item.status == _DocStatus.rejected ||
        item.status == _DocStatus.expired;
  }

  /// A re-upload replaces an existing document (rejected or expired),
  /// so we confirm before discarding it. A first-time upload goes straight
  /// to the picker.
  bool get _isReupload =>
      item.status == _DocStatus.rejected || item.status == _DocStatus.expired;

  Future<void> _handleUpload(BuildContext context) async {
    if (item.documentType == null) return;

    if (_isReupload) {
      final confirmed = await _confirmReplace(context);
      if (confirmed != true || !context.mounted) return;
    }

    final file = await MediaPickerHelper.pickDocumentWithCamera(context);
    if (file == null || !context.mounted) return;

    // Documents that carry a printed expiry date (driver's licence,
    // roadworthiness and insurance) must supply it so the platform can prompt
    // renewal before they lapse.
    String? expiresAt;
    if (item.documentType!.requiresExpiry) {
      final expiry = await _pickExpiryDate(context);
      if (!context.mounted) return;
      if (expiry == null) {
        MyShopToast.show(
          context,
          message: 'Add the expiry date shown on your document to continue.',
          type: ToastType.info,
        );
        return;
      }
      // The API contract is a calendar date, not a timestamp. Keeping it
      // date-only also prevents device timezone conversion from shifting the
      // printed expiry day.
      expiresAt = DateFormat('yyyy-MM-dd').format(expiry);
    }

    final error = await ref.read(documentUploadProvider.notifier).upload(
          providerType: providerType,
          documentType: item.documentType!,
          file: file,
          vehicleId: item.vehicleId,
          expiresAt: expiresAt,
        );

    if (!context.mounted) return;
    if (error != null) {
      MyShopToast.show(context, message: error, type: ToastType.error);
    } else {
      // Pull the fresh document list so the new version's status (and any
      // updated expiry) replaces the old one on next rebuild.
      ref.invalidate(verificationStatusProvider);
    }
  }

  /// Prompts for the expiry date printed on the document. The date must be in
  /// the future — a renewal always carries a fresh expiry.
  Future<DateTime?> _pickExpiryDate(BuildContext context) {
    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);
    return showDatePicker(
      context: context,
      helpText: 'Expiry date on your ${item.title}',
      firstDate: firstDate,
      initialDate: DateTime(today.year + 1, today.month, today.day),
      lastDate: DateTime(today.year + 20),
    );
  }

  Future<bool?> _confirmReplace(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: MyShopColors.surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _ReplaceDocSheet(title: item.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _canUpload ? () => _handleUpload(context) : null,
      child: Padding(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaledTitleSize =
                MediaQuery.textScalerOf(context).scale(16).toDouble();
            final compact = constraints.maxWidth < 360 || scaledTitleSize > 18;
            final icon = Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, size: 20, color: MyShopColors.textPrimary),
            );
            final details = Column(
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
                        maxLines: compact ? 2 : 1,
                        style: MyShopTypography.body2.copyWith(
                          color: switch (item.status) {
                            _DocStatus.rejected ||
                            _DocStatus.expired =>
                              MyShopColors.error,
                            _DocStatus.expiryMissing ||
                            _DocStatus.expiringSoon =>
                              MyShopColors.warning,
                            _ => null,
                          },
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            );

            if (compact) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: MyShopSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        details,
                        const SizedBox(height: MyShopSpacing.sm),
                        _StatusPill(status: item.status),
                      ],
                    ),
                  ),
                ],
              );
            }

            return Row(
              children: [
                icon,
                const SizedBox(width: MyShopSpacing.md),
                Expanded(child: details),
                const SizedBox(width: MyShopSpacing.sm),
                _StatusPill(status: item.status),
              ],
            );
          },
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
      _DocStatus.adminVerified => (
          MyShopColors.warningLight,
          MyShopColors.warning,
          'Coordinator',
          Icons.fact_check_outlined,
        ),
      _DocStatus.coordinatorValidated => (
          MyShopColors.primaryGoldLight,
          MyShopColors.primaryGold,
          'RM Review',
          Icons.verified_outlined,
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
      _DocStatus.expired => (
          MyShopColors.errorLight,
          MyShopColors.error,
          'Expired',
          Icons.event_busy_outlined,
        ),
      _DocStatus.expiryMissing => (
          MyShopColors.warningLight,
          MyShopColors.warning,
          'Action needed',
          Icons.event_busy_outlined,
        ),
      _DocStatus.expiringSoon => (
          MyShopColors.warningLight,
          MyShopColors.warning,
          'Expiring',
          Icons.event_outlined,
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
// Replace-document confirmation sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Confirms replacing an existing document before opening the file picker.
/// Shown when re-uploading a rejected or expired document.
class _ReplaceDocSheet extends StatelessWidget {
  const _ReplaceDocSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(MyShopSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: MyShopColors.primaryGoldLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.autorenew,
                    color: MyShopColors.primaryGold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: Text(
                    'Re-upload $title',
                    style: MyShopTypography.h3.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              'Your current document will be replaced with the new one and '
              'sent back to our compliance team for review. This usually takes '
              'up to 24 hours.',
              style: MyShopTypography.body2.copyWith(height: 1.5),
            ),
            const SizedBox(height: MyShopSpacing.lg),
            MyShopPrimaryButton(
              label: 'Choose new document',
              icon: Icons.upload_outlined,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: MyShopSpacing.sm),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: MyShopTypography.body1.copyWith(
                    color: MyShopColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
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
