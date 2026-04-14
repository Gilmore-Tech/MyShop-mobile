import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bg            = Color(0xFFF6F7F8);
const _surfaceWhite  = Color(0xFFFFFFFF);
const _surfaceGrey   = Color(0xFFF3F5F6);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _danger        = Color(0xFFEB5757);
const _dangerLight   = Color(0xFFFDE8E8);
const _divider       = Color(0xFFE8EAEC);

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.8 — Client disputes a completed artisan job.
// Admin reviews the job record and both parties' accounts.
// EDD: POST /v1/jobs/:id/dispute  { reason, details }

class JobDisputeScreen extends ConsumerStatefulWidget {
  const JobDisputeScreen({super.key});

  @override
  ConsumerState<JobDisputeScreen> createState() => _JobDisputeScreenState();
}

class _JobDisputeScreenState extends ConsumerState<JobDisputeScreen> {
  final _detailsController = TextEditingController();
  String? _selectedReason;
  bool    _isSubmitting = false;
  bool    _submitted    = false;

  static const _reasons = [
    'Work quality was poor or incomplete',
    'Materials billed were not used',
    'Artisan was unprofessional or abusive',
    'Job was not completed as agreed',
    'Supplement was charged without approval',
    'Other',
  ];

  bool get _canSubmit =>
      _selectedReason != null &&
      (_selectedReason != 'Other' ||
          _detailsController.text.trim().length >= 10);

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    // TODO: POST /v1/jobs/:id/dispute { reason, details }
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _submitted    = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;
    final bot  = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Dispute Job',
            style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: _submitted
          ? _SuccessBody(w: w, h: h, onDone: () => context.pop())
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(w * 0.05),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoBanner(w: w, h: h),
                        SizedBox(height: h * 0.028),
                        _SectionTitle(text: 'What\'s the issue?', w: w),
                        SizedBox(height: h * 0.016),
                        ..._reasons.map((r) => _ReasonTile(
                              reason:     r,
                              isSelected: _selectedReason == r,
                              onTap: () =>
                                  setState(() => _selectedReason = r),
                              w: w,
                              h: h,
                            )),
                        SizedBox(height: h * 0.024),
                        _SectionTitle(
                            text: 'Additional details'
                                '${_selectedReason == 'Other' ? ' (required)' : ' (optional)'}',
                            w: w),
                        SizedBox(height: h * 0.012),
                        _DetailsField(
                            controller: _detailsController,
                            onChanged:  (_) => setState(() {}),
                            w: w,
                            h: h),
                        SizedBox(height: h * 0.016),
                        _PolicyNote(w: w),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      w * 0.05, 0, w * 0.05, bot + h * 0.028),
                  child: _SubmitButton(
                    enabled: _canSubmit,
                    loading: _isSubmitting,
                    onTap:   _submit,
                    w: w, h: h,
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Info banner ────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final double w, h;
  const _InfoBanner({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        _dangerLight,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _danger.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _danger, size: 20),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Disputes must be raised within 24 hours of job completion.',
                    style: TextStyle(
                      color:      _danger,
                      fontSize:   w * 0.034,
                      fontWeight: FontWeight.w600,
                    )),
                const SizedBox(height: 4),
                Text(
                  'Our team reviews the job record and artisan\'s account. '
                  'We will respond within 48 hours.',
                  style: TextStyle(
                      color:    _danger.withAlpha(180),
                      fontSize: w * 0.030,
                      height:   1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reason tile ────────────────────────────────────────────────────────────────

class _ReasonTile extends StatelessWidget {
  final String     reason;
  final bool       isSelected;
  final VoidCallback onTap;
  final double     w, h;

  const _ReasonTile({
    required this.reason,
    required this.isSelected,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin:  EdgeInsets.only(bottom: h * 0.010),
        padding: EdgeInsets.symmetric(
            horizontal: w * 0.04, vertical: h * 0.018),
        decoration: BoxDecoration(
          color:        isSelected ? _gold.withAlpha(16) : _surfaceWhite,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(
              color: isSelected ? _gold : _divider,
              width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width:  w * 0.052,
              height: w * 0.052,
              decoration: BoxDecoration(
                shape:  BoxShape.circle,
                color:  isSelected ? _gold : _surfaceGrey,
                border: Border.all(
                    color: isSelected ? _gold : _divider),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                  : null,
            ),
            SizedBox(width: w * 0.032),
            Expanded(
              child: Text(reason,
                  style: TextStyle(
                    color:      _textPrimary,
                    fontSize:   w * 0.036,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Details field ──────────────────────────────────────────────────────────────

class _DetailsField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>  onChanged;
  final double                w, h;

  const _DetailsField({
    required this.controller,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: TextField(
        controller: controller,
        onChanged:  onChanged,
        maxLines:   5,
        minLines:   4,
        style: TextStyle(color: _textPrimary, fontSize: w * 0.036),
        decoration: InputDecoration(
          hintText: 'Describe the issue in detail…',
          hintStyle: TextStyle(
              color:    _textSecondary.withAlpha(120),
              fontSize: w * 0.034),
          contentPadding: EdgeInsets.all(w * 0.04),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final double w;
  const _SectionTitle({required this.text, required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          color:      _textPrimary,
          fontSize:   w * 0.038,
          fontWeight: FontWeight.w700,
        ));
  }
}

class _PolicyNote extends StatelessWidget {
  final double w;
  const _PolicyNote({required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(
      'If the dispute is upheld, your escrow payment will be fully or '
      'partially refunded within 3 business days.',
      style: TextStyle(
          color:    _textSecondary,
          fontSize: w * 0.030,
          height:   1.6),
    );
  }
}

// ── Submit button ──────────────────────────────────────────────────────────────

class _SubmitButton extends StatelessWidget {
  final bool         enabled;
  final bool         loading;
  final VoidCallback onTap;
  final double       w, h;

  const _SubmitButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity:  enabled ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: SizedBox(
        width:  double.infinity,
        height: h * 0.066,
        child: Material(
          color:        _danger,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap:        enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: loading
                  ? SizedBox(
                      width:  w * 0.052,
                      height: w * 0.052,
                      child: const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text('Submit Dispute',
                      style: TextStyle(
                        color:      Colors.white,
                        fontSize:   w * 0.042,
                        fontWeight: FontWeight.w700,
                      )),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Success state ──────────────────────────────────────────────────────────────

class _SuccessBody extends StatelessWidget {
  final double       w, h;
  final VoidCallback onDone;
  const _SuccessBody(
      {required this.w, required this.h, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(w * 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width:  w * 0.22,
            height: w * 0.22,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F8EE), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: Color(0xFF27AE60), size: 56),
          ),
          SizedBox(height: h * 0.032),
          Text('Dispute submitted',
              style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.056,
                fontWeight: FontWeight.w800,
              )),
          SizedBox(height: h * 0.012),
          Text(
            'Our team will review the job and respond within 48 hours. '
            'You\'ll be notified via the app.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color:    _textSecondary,
                fontSize: w * 0.036,
                height:   1.6),
          ),
          SizedBox(height: h * 0.048),
          SizedBox(
            width:  double.infinity,
            height: h * 0.066,
            child: ElevatedButton(
              onPressed: onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Back to Activity',
                  style: TextStyle(
                      fontSize:   w * 0.042,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
