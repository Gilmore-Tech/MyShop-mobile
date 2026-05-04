import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../../earnings/providers/ratings_provider.dart';

/// Artisan-facing rating sheet shown after a job settles. Mirrors the
/// driver's `RatePassengerSheet` — same `POST /v1/ratings` endpoint, same
/// blind 24-hour reveal — just framed for jobs (`bookingType: 'artisan_job'`)
/// and copy that reads from the artisan's POV.
Future<void> showRateClientSheet(
  BuildContext context, {
  required String jobId,
  required String clientFirstName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (_) => RateClientSheet(
      jobId: jobId,
      clientFirstName: clientFirstName,
    ),
  );
}

class RateClientSheet extends ConsumerStatefulWidget {
  const RateClientSheet({
    super.key,
    required this.jobId,
    required this.clientFirstName,
  });

  final String jobId;
  final String clientFirstName;

  @override
  ConsumerState<RateClientSheet> createState() => _RateClientSheetState();
}

class _RateClientSheetState extends ConsumerState<RateClientSheet> {
  final _commentController = TextEditingController();
  int _stars = 0;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _stars > 0 && !_isSubmitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final response =
          await ref.read(ratingServiceProvider).submitRating(
                bookingType: 'artisan_job',
                bookingId: widget.jobId,
                stars: _stars,
                comment: _commentController.text.trim().isEmpty
                    ? null
                    : _commentController.text.trim(),
              );
      // Mutual reveal triggered ⇒ the client's rating about us just became
      // counted in our public average. Invalidate the summary so the
      // earnings/home rating tile refetches with the new value instead of
      // staying stale until the next cold launch.
      if (response['revealed'] == true) {
        ref.invalidate(providerRatingsProvider);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for rating your client.')),
      );
    } on ApiException catch (e) {
      developer.log(
        'submitRating failed: ${e.errorCode} — ${e.message}',
        name: 'RateClient',
        level: 900,
      );
      if (!mounted) return;
      setState(() => _errorMessage = _friendlyError(e));
    } catch (e) {
      developer.log('submitRating crashed: $e',
          name: 'RateClient', level: 1000);
      if (!mounted) return;
      setState(() =>
          _errorMessage = "Couldn't submit the rating. Please try again.");
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _friendlyError(ApiException e) {
    switch (e.errorCode) {
      case 'ALREADY_RATED':
        return "You've already rated this client.";
      case 'RATING_WINDOW_CLOSED':
        return 'The rating window for this job has closed.';
      case 'BOOKING_NOT_COMPLETED':
        return 'Wait until the job is fully completed before rating.';
      default:
        return e.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: MyShopColors.divider,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Rate ${widget.clientFirstName}',
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Your rating is hidden until the client rates you back '
                'or 24 hours pass — they never see who said what.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: MyShopColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final starIndex = i + 1;
                final filled = starIndex <= _stars;
                return GestureDetector(
                  onTap: () => setState(() => _stars = starIndex),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 36,
                      color: MyShopColors.primaryGold,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            const Text(
              'Add a note (optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: MyShopColors.divider),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _commentController,
                minLines: 3,
                maxLines: null,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: 'How was the job with ${widget.clientFirstName}?',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: MyShopColors.disabled,
                  ),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  fontSize: 12,
                  color: MyShopColors.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyShopColors.darkSlate,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: MyShopColors.surfaceGrey,
                  disabledForegroundColor: MyShopColors.disabled,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Rating',
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed:
                    _isSubmitting ? null : () => Navigator.of(context).pop(),
                child: const Text(
                  'No thanks, just close',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: MyShopColors.textSecondary,
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
