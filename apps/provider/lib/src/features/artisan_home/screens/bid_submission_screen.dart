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
import '../../../core/services/incoming_request_overlay_presenter.dart';
import '../../../core/services/local_notification_service.dart';
import '../../artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../artisan_jobs/providers/submitted_bids_provider.dart';
import '../providers/bid_drafts_provider.dart';
import '../widgets/bid_confirmation_modal.dart';
import '../widgets/bid_status_banner.dart';

/// A successful quote submission only opens active work when the server
/// explicitly confirms it. `admin_assigned` by itself still means the client
/// must accept the directed quote.
bool submittedBidResponseIsConfirmed(Map<String, dynamic> response) {
  final bidStatus = response['status'] ?? response['bidStatus'];
  if (bidStatus == 'accepted') return true;
  final rawJob = response['job'];
  final nestedJobStatus =
      rawJob is Map<String, dynamic> ? rawJob['status'] : null;
  final jobStatus = response['jobStatus'] ?? nestedJobStatus;
  return jobStatus == 'confirmed';
}

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
    this.editingBidId,
    this.initialAmountPesewas,
    this.initialEtaMinutes,
    this.initialDurationMinutes,
    this.initialNotes,
  });

  final Job job;
  final double distanceKm;
  final num marketAverage;

  /// When non-null, the sheet operates in **edit** mode: submit becomes a
  /// `PATCH /jobs/:jobId/bids/:bidId` against the existing bid instead of a
  /// fresh `POST /jobs/:jobId/bids`. Initial form values are taken from the
  /// `initial*` props rather than a local draft.
  final String? editingBidId;
  final int? initialAmountPesewas;
  final int? initialEtaMinutes;
  final int? initialDurationMinutes;
  final String? initialNotes;

  bool get isEditing => editingBidId != null;

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
    String? editingBidId,
    int? initialAmountPesewas,
    int? initialEtaMinutes,
    int? initialDurationMinutes,
    String? initialNotes,
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
        editingBidId: editingBidId,
        initialAmountPesewas: initialAmountPesewas,
        initialEtaMinutes: initialEtaMinutes,
        initialDurationMinutes: initialDurationMinutes,
        initialNotes: initialNotes,
      ),
    );
  }

  @override
  ConsumerState<BidSubmissionScreen> createState() =>
      _BidSubmissionScreenState();
}

class _BidSubmissionScreenState extends ConsumerState<BidSubmissionScreen> {
  // BR-61: bid files have no server-side upload/provenance consumer yet. Keep
  // the notes field available but do not create or restore local attachment
  // copies until that end-to-end contract is implemented and approved.
  static const _bidAttachmentsEnabled = false;

  late final TextEditingController _labour;
  late final TextEditingController _eta;
  late final TextEditingController _notes;
  int _durationMinutes = 0;
  final List<File> _attachments = [];
  bool _submitting = false;

  /// Captured in [initState] so the dispose-time draft flush can persist
  /// without touching `ref` — `ref.read` throws once the element transitions
  /// to defunct, which happens before `State.dispose()` is invoked.
  late final BidDraftsNotifier _draftsNotifier;

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

    _draftsNotifier = ref.read(bidDraftsProvider.notifier);
    final draft = ref.read(bidDraftsProvider)[widget.job.id];
    _clientRequestId = draft?.clientRequestId;

    // In edit mode the live bid is the source of truth — local drafts (which
    // may belong to an aborted earlier session) must not override it. In
    // create mode the existing draft-resume behaviour applies.
    final useEdit = widget.isEditing;
    _labour = TextEditingController(
      text: useEdit
          ? _labourInitialFromPesewas(widget.initialAmountPesewas)
          : _labourInitial(draft),
    );
    _eta = TextEditingController(
      text: useEdit
          ? _etaInitialFromMinutes(widget.initialEtaMinutes)
          : _etaInitial(draft),
    );
    _durationMinutes = useEdit
        ? (widget.initialDurationMinutes ?? 0)
        : (draft?.durationMinutes ?? 0);
    _notes = TextEditingController(
      text: useEdit ? (widget.initialNotes ?? '') : (draft?.notes ?? ''),
    );
    if (_bidAttachmentsEnabled && draft != null) {
      for (final path in draft.attachmentPaths) {
        final f = File(path);
        if (f.existsSync()) _attachments.add(f);
      }
    }

    for (final c in [_labour, _eta, _notes]) {
      c.addListener(_scheduleSave);
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _errorTimer?.cancel();
    // Final flush — preserve the last keystroke if the artisan dismissed
    // (e.g. via the Cancel button) without explicitly submitting.
    //
    // The snapshot is built NOW (controllers are about to be disposed) but
    // the notifier mutation is deferred to a fresh Future tick: assigning
    // `notifier.state = ...` synchronously here would notify listeners
    // mid-unmount, which Riverpod's `_debugCanModifyProviders` blocks
    // ("Tried to modify a provider while the widget tree was building").
    if (_isDirty) {
      final draft = _buildDraftSnapshot();
      final notifier = _draftsNotifier;
      final jobId = widget.job.id;
      Future<void>(() {
        if (draft.hasContent) {
          notifier.upsert(draft);
        } else {
          notifier.remove(jobId);
        }
      });
    }
    for (final c in [_labour, _eta, _notes]) {
      c.removeListener(_scheduleSave);
    }
    _labour.dispose();
    _eta.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Pesewas → display GHS. `175` for `17500`. Returns empty when there's
  /// nothing to restore — controllers start blank.
  static String _labourInitial(BidDraft? draft) =>
      _labourInitialFromPesewas(draft?.labourPesewas);

  static String _etaInitial(BidDraft? draft) =>
      _etaInitialFromMinutes(draft?.etaMinutes);

  static String _labourInitialFromPesewas(int? pesewas) {
    final p = pesewas ?? 0;
    return p > 0 ? (p ~/ 100).toString() : '';
  }

  static String _etaInitialFromMinutes(int? minutes) {
    final m = minutes ?? 0;
    return m > 0 ? '$m' : '';
  }

  /// Formats a duration as "Xh Ym" / "Xh" / "Ym" for the field label.
  /// Returns the empty string when nothing is set so the hint text shows.
  static String _formatDuration(int minutes) {
    if (minutes <= 0) return '';
    final hh = minutes ~/ 60;
    final mm = minutes % 60;
    if (hh == 0) return '${mm}m';
    if (mm == 0) return '${hh}h';
    return '${hh}h ${mm}m';
  }

  void _scheduleSave() {
    _isDirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _writeDraft);
  }

  /// Read the controllers + attachment list and build a [BidDraft] for the
  /// current form state. Pure read — no provider mutations — so it's safe
  /// to call from `dispose()` while the controllers are still alive.
  BidDraft _buildDraftSnapshot() {
    final ghs = num.tryParse(_labour.text.trim()) ?? 0;
    final etaMinutes = int.tryParse(_eta.text.trim()) ?? 0;
    final durationMinutes = _durationMinutes;
    final notes = _notes.text.trim();

    return BidDraft(
      jobId: widget.job.id,
      savedAt: DateTime.now(),
      clientRequestId: _clientRequestId,
      labourPesewas: ghs > 0 ? (ghs * 100).round() : 0,
      etaMinutes: etaMinutes,
      durationMinutes: durationMinutes,
      notes: notes.isEmpty ? null : notes,
      attachmentPaths: _attachments.map((f) => f.path).toList(growable: false),
    );
  }

  Future<void> _writeDraft() async {
    final draft = _buildDraftSnapshot();
    if (!draft.hasContent) {
      // Empty form — drop any prior draft for this job so the resume banner
      // doesn't keep advertising a draft with nothing in it.
      await _draftsNotifier.remove(widget.job.id);
      return;
    }
    await _draftsNotifier.upsert(draft);
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

  /// Extract the server-authored deadline from the bid response. Directed
  /// quotes use the client's acceptance deadline; normal bids keep using the
  /// bid expiry.
  DateTime? _expiresFromResponse(Map<String, dynamic>? response) {
    if (response == null) return null;
    final assignment = response['assignment'];
    final acceptDeadline = assignment is Map<String, dynamic>
        ? assignment['acceptDeadlineAt']
        : null;
    final raw =
        acceptDeadline ?? response['expiresAt'] ?? response['bidExpiresAt'];
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// Turn the structured backend error into a human-friendly explanation.
  /// Unknown server prose is never shown.
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
      case 'PROVIDER_CANCELLATION_BLOCK':
        return 'New job requests are temporarily unavailable because your provider account reached the cancellation limit. Contact support if you need help.';
      default:
        return userSafeApiErrorMessage(
          e,
          fallback: "Couldn't submit the bid. Please try again.",
          conflictMessage:
              'This job changed before the bid was submitted. Refresh and try again.',
        );
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

  Future<void> _handleSubmit() async {
    if (_submitting) return;

    final ghs = num.tryParse(_labour.text.trim()) ?? 0;
    final etaMinutes = int.tryParse(_eta.text.trim()) ?? 0;
    final durationMinutes = _durationMinutes;

    if (ghs <= 0 || etaMinutes <= 0 || durationMinutes <= 0) {
      _notifyError('Fill in labour, ETA, and duration first.');
      return;
    }
    // Caps: labour 10k GHS, ETA 120 min. Higher numbers are almost always
    // typos — clients can still post follow-up jobs for genuinely larger
    // work without the artisan locking themselves into a four-digit bid.
    if (ghs > 10000) {
      _notifyError('Labour amount cannot exceed GHS 10,000.');
      return;
    }
    if (etaMinutes > 120) {
      _notifyError('ETA cannot exceed 120 minutes (2 hours).');
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
      if (widget.isEditing) {
        bidResponse = await ref.read(jobServiceProvider).editBid(
              widget.job.id,
              widget.editingBidId!,
              amountPesewas: amountPesewas,
              etaMinutes: etaMinutes,
              durationMinutes: durationMinutes,
              notes: trimmedNotes,
            );
      } else {
        bidResponse = await ref.read(jobServiceProvider).submitBid(
              widget.job.id,
              amountPesewas: amountPesewas,
              etaMinutes: etaMinutes,
              durationMinutes: durationMinutes,
              notes: trimmedNotes,
              clientRequestId: _clientRequestId,
            );
      }
    } on ApiException catch (e) {
      failureMessage = _friendlyBidError(e);
    } catch (e) {
      // ignore: avoid_print
      print('[BidSubmissionScreen] unexpected submit error: $e');
      failureMessage = widget.isEditing
          ? 'Failed to update bid. Please try again.'
          : 'Failed to submit bid. Please try again.';
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
    await clearIncomingRequestAlert(
      type: NotificationPayload.typeJobRequest,
      requestId: widget.job.id,
      reason: 'bid_submitted',
    );

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

    // A directed assignment remains pre-work after the quote is submitted.
    // Only an explicit accepted/confirmed response may enter active work.
    final wasConfirmed = submittedBidResponseIsConfirmed(bidResponse);

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final rootContext = navigator.context;
    navigator.pop();

    // Edit mode: artisan was already on the request screen below this sheet
    // — just dismiss. The silentReload above will push fresh `myBid` data
    // into the banner. No confirmation modal, no nav.
    if (widget.isEditing) return;

    if (!rootContext.mounted) return;
    await BidConfirmationModal.show(
      rootContext,
      clientFirstName: widget.clientName.split(' ').first,
      bidAmount: ghs,
      arrivalEta: 'Within $etaMinutes mins',
    );
    if (!rootContext.mounted) return;

    if (wasConfirmed) {
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
                        maxDigits: 3,
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
                  attachmentsEnabled: _bidAttachmentsEnabled,
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

              // Job duration — wheel-picker prevents free-form HH:MM input,
              // bounded to 0h–8h in 5-minute steps.
              _FieldWithLabel(
                label: 'JOB DURATION',
                child: _DurationPickerField(
                  minutes: _durationMinutes,
                  onChanged: (m) {
                    setState(() => _durationMinutes = m);
                    _scheduleSave();
                  },
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
    this.maxDigits = 5,
  });

  final TextEditingController controller;
  final Widget prefix;
  final String? hintText;

  /// Hard cap on input length — labour is bounded at 10k GHS (5 digits),
  /// ETA at 120 minutes (3 digits). Prevents the artisan from accidentally
  /// pasting a phone number into the labour field.
  final int maxDigits;

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
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(maxDigits),
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

/// Read-only duration field. Tapping opens a bottom-sheet with two wheel
/// pickers (hours 0–8, minutes 0/5/…/55). Wheels eliminate free-form HH:MM
/// typos and put the legal range in front of the artisan, so a 30-minute
/// quote can't be entered as "30:00" by mistake.
class _DurationPickerField extends StatelessWidget {
  const _DurationPickerField({
    required this.minutes,
    required this.onChanged,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

  static const _maxHours = 8;
  static const _minuteStep = 5;

  String get _display => _BidSubmissionScreenState._formatDuration(minutes);

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: MyShopColors.surfaceWhite,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _DurationPickerSheet(
        initialMinutes: minutes,
        maxHours: _maxHours,
        minuteStep: _minuteStep,
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = minutes > 0;
    return GestureDetector(
      onTap: () => _open(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.offWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.timer_outlined,
              color: MyShopColors.textPrimary,
              size: 22,
            ),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
              child: Text(
                hasValue ? _display : 'Tap to set',
                style: MyShopTypography.h2.copyWith(
                  fontWeight: hasValue ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 22,
                  color: hasValue
                      ? MyShopColors.textPrimary
                      : MyShopColors.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              color: MyShopColors.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationPickerSheet extends StatefulWidget {
  const _DurationPickerSheet({
    required this.initialMinutes,
    required this.maxHours,
    required this.minuteStep,
  });

  final int initialMinutes;
  final int maxHours;
  final int minuteStep;

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  late int _hours;
  late int _minuteIndex;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minuteCtrl;

  List<int> get _minuteValues => List.generate(
        60 ~/ widget.minuteStep,
        (i) => i * widget.minuteStep,
      );

  @override
  void initState() {
    super.initState();
    final init = widget.initialMinutes.clamp(0, widget.maxHours * 60);
    _hours = (init ~/ 60).clamp(0, widget.maxHours);
    final remainder = init % 60;
    _minuteIndex = _minuteValues
        .indexOf((remainder ~/ widget.minuteStep) * widget.minuteStep);
    if (_minuteIndex < 0) _minuteIndex = 0;
    _hourCtrl = FixedExtentScrollController(initialItem: _hours);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minuteIndex);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  int get _selectedMinutes => _hours * 60 + _minuteValues[_minuteIndex];

  @override
  Widget build(BuildContext context) {
    final canConfirm = _selectedMinutes > 0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MyShopSpacing.md,
          MyShopSpacing.md,
          MyShopSpacing.md,
          MyShopSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: MyShopColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              'Job duration',
              style: MyShopTypography.h2.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Hours and minutes you expect to work. '
              'Range: 5 minutes to ${widget.maxHours} hours.',
              style: MyShopTypography.body2,
            ),
            const SizedBox(height: MyShopSpacing.md),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    child: _WheelColumn(
                      controller: _hourCtrl,
                      itemCount: widget.maxHours + 1,
                      label: 'h',
                      formatter: (i) => i.toString(),
                      onChanged: (i) => setState(() => _hours = i),
                    ),
                  ),
                  Expanded(
                    child: _WheelColumn(
                      controller: _minuteCtrl,
                      itemCount: _minuteValues.length,
                      label: 'm',
                      formatter: (i) =>
                          _minuteValues[i].toString().padLeft(2, '0'),
                      onChanged: (i) => setState(() => _minuteIndex = i),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
            ElevatedButton(
              onPressed: canConfirm
                  ? () => Navigator.of(context).pop(_selectedMinutes)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                foregroundColor: MyShopColors.textOnPrimary,
                disabledBackgroundColor: MyShopColors.disabled,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                canConfirm
                    ? 'Set ${_BidSubmissionScreenState._formatDuration(_selectedMinutes)}'
                    : 'Pick at least 5 minutes',
                style: MyShopTypography.button.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelColumn extends StatelessWidget {
  const _WheelColumn({
    required this.controller,
    required this.itemCount,
    required this.label,
    required this.formatter,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int itemCount;
  final String label;
  final String Function(int) formatter;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: controller,
      physics: const FixedExtentScrollPhysics(),
      itemExtent: 44,
      perspective: 0.003,
      diameterRatio: 1.4,
      onSelectedItemChanged: onChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: itemCount,
        builder: (context, index) {
          return Center(
            child: Text(
              '${formatter(index)}$label',
              style: MyShopTypography.h2.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: MyShopColors.textPrimary,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  const _NotesField({
    required this.controller,
    required this.attachments,
    required this.attachmentsEnabled,
    required this.onFilePicked,
  });

  final TextEditingController controller;
  final List<File> attachments;
  final bool attachmentsEnabled;
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
          if (attachmentsEnabled && attachments.isNotEmpty) ...[
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
          if (attachmentsEnabled)
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
                    final file =
                        await MediaPickerHelper.pickAttachment(context);
                    if (file != null) onFilePicked(file);
                  },
                ),
              ],
            )
          else
            Text(
              'Photo and file attachments are temporarily unavailable. Your notes will still be sent.',
              style: MyShopTypography.caption.copyWith(
                color: MyShopColors.textSecondary,
              ),
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
