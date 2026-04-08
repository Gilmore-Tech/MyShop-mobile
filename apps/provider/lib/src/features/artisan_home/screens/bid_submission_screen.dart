import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../widgets/bid_confirmation_modal.dart';
import '../widgets/bid_status_banner.dart';

/// Submit bid bottom sheet — shown over the Request Details screen.
///
/// PRD Reference: PRD 5.3 — bid submission with category-minimum validation,
/// optional message to client.
class BidSubmissionScreen extends StatefulWidget {
  const BidSubmissionScreen({
    super.key,
    this.clientName = 'Ama Serwaa',
    this.clientLocation = 'Adum, Kumasi',
    this.distanceKm = 1.2,
    this.marketAverage = 180,
  });

  final String clientName;
  final String clientLocation;
  final double distanceKm;
  final num marketAverage;

  /// Pushes the sheet as a draggable, full-rounded modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    String clientName = 'Ama Serwaa',
    String clientLocation = 'Adum, Kumasi',
    double distanceKm = 1.2,
    num marketAverage = 180,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => BidSubmissionScreen(
        clientName: clientName,
        clientLocation: clientLocation,
        distanceKm: distanceKm,
        marketAverage: marketAverage,
      ),
    );
  }

  @override
  State<BidSubmissionScreen> createState() => _BidSubmissionScreenState();
}

class _BidSubmissionScreenState extends State<BidSubmissionScreen> {
  late final TextEditingController _labour;
  late final TextEditingController _eta;
  late final TextEditingController _notes;
  late final TextEditingController _duration;

  @override
  void initState() {
    super.initState();
    _labour = TextEditingController(text: '175');
    _eta = TextEditingController(text: '20');
    _notes = TextEditingController();
    _duration = TextEditingController(text: '02:00');
  }

  @override
  void dispose() {
    _labour.dispose();
    _eta.dispose();
    _notes.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final navigator = Navigator.of(context);
    final rootContext = navigator.context;
    // Close the sheet first.
    navigator.pop();
    // Show the confirmation modal on the underlying screen.
    await BidConfirmationModal.show(
      rootContext,
      clientFirstName: widget.clientName.split(' ').first,
      bidAmount: num.tryParse(_labour.text) ?? 0,
      arrivalEta: 'Within ${_eta.text} mins',
    );
    // Replace request details with the pending state.
    if (rootContext.mounted) {
      rootContext.pushReplacement('/job-request', extra: BidStatus.accepted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Container(
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

            // Client card
            _ClientHeader(
              clientName: widget.clientName,
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
              child: _NotesField(controller: _notes),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // Job duration
            _FieldWithLabel(
              label: 'JOB DURATION (HH:MM)',
              child: _NumberField(
                controller: _duration,
                prefix: const Icon(
                  Icons.timer_outlined,
                  color: MyShopColors.textPrimary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: MyShopSpacing.xl),

            // Submit
            _SubmitButton(onTap: _handleSubmit),
            const SizedBox(height: MyShopSpacing.md),

            // Cancel
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Client header
// ─────────────────────────────────────────────────────────────────────────────

class _ClientHeader extends StatelessWidget {
  const _ClientHeader({
    required this.clientName,
    required this.clientLocation,
    required this.distanceKm,
  });

  final String clientName;
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
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: MyShopColors.avatarPlaceholder,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: MyShopColors.textSecondary),
          ),
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
  const _NumberField({required this.controller, required this.prefix});

  final TextEditingController controller;
  final Widget prefix;

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
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  const _NotesField({required this.controller});

  final TextEditingController controller;

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
          const SizedBox(height: MyShopSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _IconBubble(icon: Icons.camera_alt_outlined, onTap: () {}),
              const SizedBox(width: MyShopSpacing.sm),
              _IconBubble(icon: Icons.attach_file, onTap: () {}),
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
  const _SubmitButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: MyShopColors.darkSlate,
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
        child: Text(
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
