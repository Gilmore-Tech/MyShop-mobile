import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../app/router.dart' show JobRequestRouteExtra;
import '../../../core/di/providers.dart';
import '../../artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../artisan_jobs/providers/submitted_bids_provider.dart';
import '../providers/bid_drafts_provider.dart';
import '../widgets/bid_confirmation_modal.dart';
import '../widgets/bid_status_banner.dart';

/// Submit bid bottom sheet — shown over the Request Details screen.
///
/// PRD Reference: PRD 5.3 — bid submission with category-minimum validation,
/// optional message to client.
class BidSubmissionScreen extends ConsumerStatefulWidget {
  const BidSubmissionScreen({
    super.key,
    required this.job,
    this.distanceKm = 0,
    this.marketAverage = 180,
  });

  final Job job;
  final double distanceKm;
  final num marketAverage;

  String get clientName => job.clientName ?? 'Client';
  String? get clientPhotoUrl => job.clientPhotoUrl;
  String get clientLocation => job.addressText ?? '';

  /// Pushes the sheet as a full-rounded modal bottom sheet.
  ///
  /// Drag-to-dismiss and barrier-tap are disabled — the artisan exits via
  /// the explicit "Cancel Bid Request" button (or, while submitting, has
  /// to wait for the request to settle). This prevents an accidental
  /// dismiss from leaving an in-flight bid in an ambiguous state.
  static Future<void> show(
    BuildContext context, {
    required Job job,
    double distanceKm = 0,
    num marketAverage = 180,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => BidSubmissionScreen(
        job: job,
        distanceKm: distanceKm,
        marketAverage: marketAverage,
      ),
    );
  }

  @override
  ConsumerState<BidSubmissionScreen> createState() =>
      _BidSubmissionScreenState();
}

class _BidSubmissionScreenState extends ConsumerState<BidSubmissionScreen> {
  late final TextEditingController _labour;
  late final TextEditingController _eta;
  late final TextEditingController _notes;
  late final TextEditingController _duration;
  final List<File> _attachments = [];
  bool _submitting = false;

  /// 600ms debounce so we don't write SharedPreferences on every keystroke.
  Timer? _saveDebounce;

  /// Inline error shown at the top of the sheet. Auto-dismisses after a
  /// few seconds — a SnackBar would be hidden behind the modal barrier and
  /// only surface once the sheet is dismissed, leaving the artisan with no
  /// signal that anything went wrong.
  String? _inlineError;
  Timer? _errorTimer;

  /// True once the artisan touches the form. We don't persist the empty
  /// initial state — only writes that have actual content survive.
  bool _isDirty = false;

  /// UUID generated on the first submit attempt and reused on retry so the
  /// backend can dedupe via `Idempotency-Key`. Survives in the draft.
  String? _clientRequestId;

  @override
  void initState() {
    super.initState();

    final draft = ref.read(bidDraftsProvider)[widget.job.id];
    _clientRequestId = draft?.clientRequestId;

    _labour = TextEditingController(text: _labourInitial(draft));
    _eta = TextEditingController(text: _etaInitial(draft));
    _duration = TextEditingController(text: _durationInitial(draft));
    _notes = TextEditingController(text: draft?.notes ?? '');
    if (draft != null) {
      for (final path in draft.attachmentPaths) {
        final f = File(path);
        if (f.existsSync()) _attachments.add(f);
      }
    }

    for (final c in [_labour, _eta, _duration, _notes]) {
      c.addListener(_scheduleSave);
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _errorTimer?.cancel();
    // Final flush — preserve the last keystroke if the artisan dismissed
    // (e.g. via the Cancel button) without explicitly submitting. The
    // future is intentionally not awaited; SharedPreferences writes are
    // fire-and-forget and the dispose path can't await.
    if (_isDirty) {
      _writeDraft();
    }
    for (final c in [_labour, _eta, _duration, _notes]) {
      c.removeListener(_scheduleSave);
    }
    _labour.dispose();
    _eta.dispose();
    _notes.dispose();
    _duration.dispose();
    super.dispose();
  }

  /// Pesewas → display GHS. `175` for `17500`. Returns empty when there's
  /// nothing to restore — controllers start blank.
  static String _labourInitial(BidDraft? draft) {
    final p = draft?.labourPesewas ?? 0;
    return p > 0 ? (p ~/ 100).toString() : '';
  }

  static String _etaInitial(BidDraft? draft) {
    final m = draft?.etaMinutes ?? 0;
    return m > 0 ? '$m' : '';
  }

  static String _durationInitial(BidDraft? draft) {
    final m = draft?.durationMinutes ?? 0;
    if (m <= 0) return '';
    final hh = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _scheduleSave() {
    _isDirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _writeDraft);
  }

  Future<void> _writeDraft() async {
    final ghs = num.tryParse(_labour.text.trim()) ?? 0;
    final etaMinutes = int.tryParse(_eta.text.trim()) ?? 0;
    final durationMinutes = _parseDurationMinutes(_duration.text);
    final notes = _notes.text.trim();

    final draft = BidDraft(
      jobId: widget.job.id,
      savedAt: DateTime.now(),
      clientRequestId: _clientRequestId,
      labourPesewas: ghs > 0 ? (ghs * 100).round() : 0,
      etaMinutes: etaMinutes,
      durationMinutes: durationMinutes,
      notes: notes.isEmpty ? null : notes,
      attachmentPaths: _attachments.map((f) => f.path).toList(growable: false),
    );

    if (!draft.hasContent) {
      // Empty form — drop any prior draft for this job so the resume banner
      // doesn't keep advertising a draft with nothing in it.
      await ref.read(bidDraftsProvider.notifier).remove(widget.job.id);
      return;
    }

    await ref.read(bidDraftsProvider.notifier).upsert(draft);
  }

  /// Copy the picked file into a per-job dir under app documents so the OS
  /// doesn't wipe it out from under us between sessions.
  Future<File> _persistAttachment(File source) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'bid_drafts', widget.job.id));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final dest = File(p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}_${p.basename(source.path)}',
    ));
    return source.copy(dest.path);
  }

  /// After a successful submit, clear out the per-job attachments dir so
  /// stale files don't pile up under app docs.
  Future<void> _clearAttachmentsDir() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'bid_drafts', widget.job.id));
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup — don't fail the submit on a leftover file.
    }
  }

  /// Extract `expiresAt` from the bid response so the countdown stays
  /// anchored to the backend's clock rather than the device's.
  DateTime? _expiresFromResponse(Map<String, dynamic>? response) {
    if (response == null) return null;
    final raw = response['expiresAt'] ?? response['bidExpiresAt'];
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// Turn the raw backend error into a human-friendly explanation.
  /// Falls back to the server's own message when the code isn't recognised.
  String _friendlyBidError(ApiException e) {
    switch (e.errorCode) {
      case 'JOB_NOT_OPEN':
        return "This job isn't accepting bids yet (it may be awaiting admin "
            'review or already assigned).';
      case 'BID_WINDOW_EXPIRED':
        return 'The bidding window for this job has closed.';
      case 'MAX_BIDS_REACHED':
        return "You've already placed the maximum number of bids (3) on "
            'this job.';
      case 'BID_BELOW_MINIMUM':
        return 'Your bid is below the minimum for this category. '
            'Increase the amount and try again.';
      default:
        return e.message;
    }
  }

  /// Show a failure as an inline banner pinned to the top of the sheet.
  /// Lives inside the modal's widget tree so it's actually visible (a
  /// `ScaffoldMessenger` SnackBar would queue behind the modal barrier and
  /// only flash after the sheet was dismissed). Auto-dismisses after 6s,
  /// or sooner if the artisan taps the close icon.
  void _notifyError(String message) {
    if (!mounted) return;
    _errorTimer?.cancel();
    setState(() => _inlineError = message);
    _errorTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() => _inlineError = null);
    });
  }

  void _dismissInlineError() {
    _errorTimer?.cancel();
    if (!mounted) return;
    setState(() => _inlineError = null);
  }

  /// Parse "HH:MM" → total minutes. Falls back to a single integer treated
  /// as minutes. Returns 0 if unparseable.
  int _parseDurationMinutes(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 0;
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      final hours = int.tryParse(parts[0]) ?? 0;
      final minutes = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return hours * 60 + minutes;
    }
    return int.tryParse(trimmed) ?? 0;
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;

    final ghs = num.tryParse(_labour.text.trim()) ?? 0;
    final etaMinutes = int.tryParse(_eta.text.trim()) ?? 0;
    final durationMinutes = _parseDurationMinutes(_duration.text);

    if (ghs <= 0 || etaMinutes <= 0 || durationMinutes <= 0) {
      _notifyError('Fill in labour, ETA, and duration first.');
      return;
    }

    // Cancel any pending debounce so we don't race the in-flight write.
    _saveDebounce?.cancel();

    setState(() => _submitting = true);

    final amountPesewas = (ghs * 100).round();
    final trimmedNotes = _notes.text.trim().isEmpty ? null : _notes.text.trim();

    // Persist a fresh draft snapshot + claim an idempotency key so a
    // crash/network-loss between here and ACK is recoverable. Reuses
    // the existing key on retry so the backend can dedupe a request that
    // landed last attempt but whose response we never saw.
    _clientRequestId ??= const Uuid().v4();
    await ref.read(bidDraftsProvider.notifier).upsert(
          BidDraft(
            jobId: widget.job.id,
            savedAt: DateTime.now(),
            clientRequestId: _clientRequestId,
            labourPesewas: amountPesewas,
            etaMinutes: etaMinutes,
            durationMinutes: durationMinutes,
            notes: trimmedNotes,
            attachmentPaths:
                _attachments.map((f) => f.path).toList(growable: false),
            submitting: true,
          ),
        );

    // Run the submission with a guaranteed `_submitting = false` reset on
    // any failure path. We deliberately keep `_submitting = true` on the
    // success branch so the button stays disabled until the bottom sheet
    // pops — avoids a one-frame flicker between "submitting" and the
    // confirmation modal.
    Map<String, dynamic>? bidResponse;
    String? failureMessage;
    try {
      bidResponse = await ref.read(jobServiceProvider).submitBid(
            widget.job.id,
            amountPesewas: amountPesewas,
            etaMinutes: etaMinutes,
            durationMinutes: durationMinutes,
            notes: trimmedNotes,
            clientRequestId: _clientRequestId,
          );
    } on ApiException catch (e) {
      failureMessage = _friendlyBidError(e);
    } catch (e) {
      // ignore: avoid_print
      print('[BidSubmissionScreen] unexpected submit error: $e');
      failureMessage = 'Failed to submit bid. Please try again.';
    }

    if (failureMessage != null) {
      // Roll the draft's `submitting` flag back so the resume banner
      // doesn't show a perpetual "Submitting…" state. The clientRequestId
      // stays attached for retry.
      await ref.read(bidDraftsProvider.notifier).markIdle(widget.job.id);
      if (!mounted) return;
      setState(() => _submitting = false);
      _notifyError(failureMessage);
      return;
    }
    if (bidResponse == null) {
      await ref.read(bidDraftsProvider.notifier).markIdle(widget.job.id);
      if (!mounted) return;
      setState(() => _submitting = false);
      return;
    }

    // Bid landed — discard the draft + on-disk attachments. Order matters:
    // remove from the provider first so the resume banner stops showing,
    // then async-clean the dir.
    await ref.read(bidDraftsProvider.notifier).remove(widget.job.id);
    unawaited(_clearAttachmentsDir());

    if (!mounted) return;

    // Persist the bid locally so the "Bids" tab can always show it with
    // accurate details, and the banner can anchor its countdown to the
    // real submission time even across app restarts.
    final submittedAt = DateTime.now();
    final expiresAt = _expiresFromResponse(bidResponse) ??
        submittedAt.add(const Duration(minutes: 5));
    await ref.read(submittedBidsProvider.notifier).add(
          SubmittedBid(
            job: widget.job,
            amountPesewas: amountPesewas,
            etaMinutes: etaMinutes,
            durationMinutes: durationMinutes,
            submittedAt: submittedAt,
            expiresAt: expiresAt,
            message: trimmedNotes,
          ),
        );

    // Bid is now on the backend — drop the job from the in-session
    // "New" list so the artisan doesn't see it as pending anymore.
    ref.read(pendingIncomingJobsProvider.notifier).remove(widget.job.id);

    // Pull fresh server state so `artisanJobsProvider.entries` picks up
    // the new bid (and `myBid.status`) — the job-request screen and the
    // "Bids" tab both key off that. Silent so the user never sees a
    // spinner flash between "submitting" and the confirmation modal.
    try {
      if (ref.exists(artisanJobsProvider)) {
        // Not awaited: the confirmation modal + nav can proceed in parallel
        // with the refresh. When it lands, the next screen rebuilds live.
        ref.read(artisanJobsProvider.notifier).silentReload();
      }
    } catch (_) {}

    // On an admin-assigned job the backend auto-confirms the bid and moves
    // the job straight to `confirmed` — we use that to skip the "pending"
    // banner below and land on the active-job flow.
    final wasAdminAssigned = widget.job.status == JobStatus.adminAssigned ||
        _wasAutoAccepted(bidResponse);

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final rootContext = navigator.context;
    navigator.pop();

    if (!rootContext.mounted) return;
    await BidConfirmationModal.show(
      rootContext,
      clientFirstName: widget.clientName.split(' ').first,
      bidAmount: ghs,
      arrivalEta: 'Within $etaMinutes mins',
    );
    if (!rootContext.mounted) return;

    if (wasAdminAssigned) {
      // Auto-confirmed — land the artisan directly on the active-job flow,
      // not the "pending, waiting for client" banner.
      rootContext.go('/active-job');
      return;
    }

    rootContext.pushReplacement(
      '/job-request',
      extra: JobRequestRouteExtra(
        job: widget.job,
        bidStatus: BidStatus.pending,
        submittedBidAmount: ghs,
      ),
    );
  }

  /// True when the submitBid response indicates the bid was auto-accepted
  /// (i.e. admin-assigned flow where the artisan was pre-picked).
  bool _wasAutoAccepted(Map<String, dynamic>? response) {
    if (response == null) return false;
    final bidStatus = response['status'] ?? response['bidStatus'];
    if (bidStatus == 'accepted') return true;
    final jobStatus = response['jobStatus'] ?? response['job']?['status'];
    if (jobStatus == 'confirmed') return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return PopScope(
      // Block Android back during an in-flight submit. The sheet is also
      // configured with `isDismissible: false, enableDrag: false` so the
      // only way out while submitting is for the request to settle.
      canPop: !_submitting,
      child: Container(
        decoration: const BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MyShopSpacing.md,
            MyShopSpacing.sm,
            MyShopSpacing.md,
            MyShopSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: MyShopSpacing.md),
                  decoration: BoxDecoration(
                    color: MyShopColors.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              if (_inlineError != null) ...[
                _InlineErrorBanner(
                  message: _inlineError!,
                  onDismiss: _dismissInlineError,
                ),
                const SizedBox(height: MyShopSpacing.md),
              ],

              // Client card
              _ClientHeader(
                clientName: widget.clientName,
                clientPhotoUrl: widget.clientPhotoUrl,
                clientLocation: widget.clientLocation,
                distanceKm: widget.distanceKm,
              ),
              const SizedBox(height: MyShopSpacing.md),

              // Price guardrails
              _PriceGuardrails(marketAverage: widget.marketAverage),
              const SizedBox(height: MyShopSpacing.lg),

              // Labour + ETA row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _FieldWithLabel(
                      label: 'LABOUR CHARGE',
                      child: _NumberField(
                        controller: _labour,
                        hintText: 'e.g. 175',
                        prefix: const Text(
                          '₵',
                          style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: MyShopSpacing.md),
                  Expanded(
                    child: _FieldWithLabel(
                      label: 'ARRIVAL (ETA)',
                      child: _NumberField(
                        controller: _eta,
                        hintText: 'e.g. 20',
                        prefix: const Icon(
                          Icons.access_time,
                          color: MyShopColors.textPrimary,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MyShopSpacing.lg),

              // Notes
              _FieldWithLabel(
                label: 'NOTES',
                child: _NotesField(
                  controller: _notes,
                  attachments: _attachments,
                  onFilePicked: (file) async {
                    // Copy into app docs so the file survives a cold start.
                    // Picker temp files get aggressively reaped on iOS.
                    final stored = await _persistAttachment(file);
                    if (!mounted) return;
                    setState(() => _attachments.add(stored));
                    _scheduleSave();
                  },
                ),
              ),
              const SizedBox(height: MyShopSpacing.lg),

              // Job duration
              _FieldWithLabel(
                label: 'JOB DURATION (HH:MM)',
                child: _NumberField(
                  controller: _duration,
                  hintText: 'HH:MM',
                  prefix: const Icon(
                    Icons.timer_outlined,
                    color: MyShopColors.textPrimary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: MyShopSpacing.xl),

              // Submit
              _SubmitButton(
                onTap: _handleSubmit,
                isLoading: _submitting,
              ),
              const SizedBox(height: MyShopSpacing.md),

              // Cancel — hidden during submit so the artisan can't bail on
              // an in-flight request. The sheet is also non-dismissible at
              // the navigator level (see [BidSubmissionScreen.show]).
              if (!_submitting)
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: MyShopColors.error,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.priority_high,
                            size: 12,
                            color: MyShopColors.error,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Cancel Bid Request',
                          style: MyShopTypography.body1.copyWith(
                            color: MyShopColors.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: MyShopSpacing.sm),

              // Helper text
              Text(
                'Bidding ensures you are considered for this job immediately.',
                textAlign: TextAlign.center,
                style: MyShopTypography.body2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Client header
// ─────────────────────────────────────────────────────────────────────────────

class _ClientHeader extends StatelessWidget {
  const _ClientHeader({
    required this.clientName,
    required this.clientPhotoUrl,
    required this.clientLocation,
    required this.distanceKm,
  });

  final String clientName;
  final String? clientPhotoUrl;
  final String clientLocation;
  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _ClientAvatar(photoUrl: clientPhotoUrl, size: 44),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        clientName,
                        style: MyShopTypography.h3.copyWith(fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified,
                      size: 16,
                      color: MyShopColors.info,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 14,
                      color: MyShopColors.primaryGold,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$clientLocation  •  ${distanceKm.toStringAsFixed(1)} km away',
                        style: MyShopTypography.body2.copyWith(
                          color: MyShopColors.primaryGold,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: MyShopColors.error,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'NOW',
              style: MyShopTypography.caption.copyWith(
                color: MyShopColors.textOnPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round avatar that loads `photoUrl` over the network when available and
/// falls back to a generic person icon while loading or on error.
class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.photoUrl, required this.size});

  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null || url.isEmpty) return _placeholder();
    final cacheDim = (size * 3).round();
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: cacheDim,
        memCacheHeight: cacheDim,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: MyShopColors.avatarPlaceholder,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person, color: MyShopColors.textSecondary),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Price guardrails
// ─────────────────────────────────────────────────────────────────────────────

class _PriceGuardrails extends StatelessWidget {
  const _PriceGuardrails({required this.marketAverage});

  final num marketAverage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MyShopColors.primaryGold,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              'PRICE GUARDRAILS',
              style: MyShopTypography.overline.copyWith(
                color: MyShopColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'MARKET AVG: ₵$marketAverage',
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Field primitives
// ─────────────────────────────────────────────────────────────────────────────

class _FieldWithLabel extends StatelessWidget {
  const _FieldWithLabel({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: MyShopTypography.overline.copyWith(
            color: MyShopColors.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: MyShopSpacing.sm),
        child,
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.prefix,
    this.hintText,
  });

  final TextEditingController controller;
  final Widget prefix;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          prefix,
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.text,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
              ],
              style: MyShopTypography.h2.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: MyShopTypography.h2.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  color: MyShopColors.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  const _NotesField({
    required this.controller,
    required this.attachments,
    required this.onFilePicked,
  });

  final TextEditingController controller;
  final List<File> attachments;
  final ValueChanged<File> onFilePicked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            style: MyShopTypography.body1,
            decoration: InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText:
                  'Include anything clients needs to know including materials if any...',
              hintStyle: MyShopTypography.body1.copyWith(
                color: MyShopColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: MyShopSpacing.sm),
            Wrap(
              spacing: MyShopSpacing.sm,
              runSpacing: MyShopSpacing.xs,
              children: attachments
                  .map((f) => Chip(
                        label: Text(
                          f.path.split('/').last,
                          style: MyShopTypography.body2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () {},
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: MyShopSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _IconBubble(
                icon: Icons.camera_alt_outlined,
                onTap: () async {
                  final file = await MediaPickerHelper.pickImage(context);
                  if (file != null) onFilePicked(file);
                },
              ),
              const SizedBox(width: MyShopSpacing.sm),
              _IconBubble(
                icon: Icons.attach_file,
                onTap: () async {
                  final file = await MediaPickerHelper.pickAttachment(context);
                  if (file != null) onFilePicked(file);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          shape: BoxShape.circle,
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Icon(icon, size: 16, color: MyShopColors.textSecondary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submit button
// ─────────────────────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.onTap, this.isLoading = false});

  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: isLoading
              ? MyShopColors.darkSlate.withValues(alpha: 0.7)
              : MyShopColors.darkSlate,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor:
                      AlwaysStoppedAnimation(MyShopColors.textOnDarkSlate),
                ),
              )
            : Text(
                'SUBMIT BID',
                style: MyShopTypography.button.copyWith(
                  color: MyShopColors.textOnDarkSlate,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline error banner — sits inside the modal so the artisan actually sees
// failure messages (a ScaffoldMessenger SnackBar would queue behind the
// modal barrier).
// ─────────────────────────────────────────────────────────────────────────────

class _InlineErrorBanner extends StatelessWidget {
  const _InlineErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.sm,
        MyShopSpacing.sm,
        MyShopSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.error, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            color: MyShopColors.error,
            size: 20,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.error,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                size: 18,
                color: MyShopColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
