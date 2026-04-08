import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Documents & Verification screen — biometric check + document list + uploads.
///
/// Figma: nodes 298:22273 / 302:22520
class DocumentsVerificationScreen extends StatelessWidget {
  const DocumentsVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Documents & Verification',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          // Verification progress
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Verification Progress',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
                Text('65% Complete',
                    style: MyShopTypography.body2.copyWith(
                        color: MyShopColors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(
                  value: 0.65,
                  minHeight: 8,
                  backgroundColor: MyShopColors.divider,
                  valueColor:
                      AlwaysStoppedAnimation(MyShopColors.primaryGold),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                  'Complete your identity verification and upload all professional documents to start receiving high-value jobs.',
                  style: MyShopTypography.body2.copyWith(fontSize: 11)),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // Identity verification
          Row(children: [
            const Text('Identity Verification',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary)),
            const Spacer(),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: MyShopColors.primaryGoldLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.shield_outlined,
                  size: 14, color: MyShopColors.primaryGold),
            ),
          ]),
          const SizedBox(height: MyShopSpacing.sm),
          _BiometricCard(),
          const SizedBox(height: MyShopSpacing.lg),

          // Required documents
          Row(children: [
            const Text('Required Documents',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary)),
            const Spacer(),
            Text('3 Documents',
                style: MyShopTypography.body2.copyWith(fontSize: 11)),
          ]),
          const SizedBox(height: MyShopSpacing.sm),
          _DocItem(
            icon: Icons.shield_outlined,
            title: 'Ghana Card (National ID)',
            description: 'Front & Back scanned copy',
            status: 'Verified',
            statusColor: MyShopColors.success,
            expiry: 'Expiry: Mar 12, 2030',
            actionLabel: 'View',
          ),
          const SizedBox(height: 8),
          _DocItem(
            icon: Icons.description_outlined,
            title: "Driver's License",
            description: 'Artisan certification proof',
            status: 'In Review',
            statusColor: MyShopColors.warning,
            expiry: '',
            actionLabel: 'Details',
          ),
          const SizedBox(height: 8),
          _DocItem(
            icon: Icons.lock_outline,
            title: 'Ghana Police Clearance',
            description: 'Criminal background check',
            status: 'Expired',
            statusColor: MyShopColors.error,
            expiry: 'Expiry: Jan 05, 2024',
            actionLabel: 'Renew',
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // Upload other proofs
          const Text('Upload Other Proofs',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary)),
          const SizedBox(height: MyShopSpacing.sm),
          DottedUploadBox(),
          const SizedBox(height: MyShopSpacing.md),
          Center(
            child: Text(
              'All documents are stored securely using industry-standard\nencryption. By submitting, you agree to our Data Privacy Policy.',
              textAlign: TextAlign.center,
              style: MyShopTypography.caption.copyWith(fontSize: 10),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Contact Support',
                  style: MyShopTypography.body2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textPrimary)),
              const Text('  |  ',
                  style: TextStyle(color: MyShopColors.textSecondary)),
              Text('Report Issue',
                  style: MyShopTypography.body2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textPrimary)),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.darkSlate,
              foregroundColor: MyShopColors.textOnPrimary,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            child: const Text('Submit for Final Review'),
          ),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }
}

class _BiometricCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
          color: MyShopColors.primaryGoldLight,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: MyShopColors.primaryGold.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: MyShopColors.primaryGold,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.face_outlined,
                size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Smile ID Biometric Check',
                  style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary)),
              SizedBox(height: 2),
              Text(
                  'Live facial recognition to match your face with your National ID records.',
                  style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 11,
                      color: MyShopColors.textSecondary)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: MyShopColors.warning,
                shape: BoxShape.circle,
              )),
          const SizedBox(width: 6),
          Text('Status:',
              style: MyShopTypography.body2.copyWith(fontSize: 11)),
          const SizedBox(width: 4),
          Text('Awaiting Selfie',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.warning)),
        ]),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.open_in_new, size: 14),
          label: const Text('Continue Biometric Scan'),
          style: ElevatedButton.styleFrom(
            backgroundColor: MyShopColors.darkSlate,
            foregroundColor: MyShopColors.textOnPrimary,
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 13,
                fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

class _DocItem extends StatelessWidget {
  const _DocItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.statusColor,
    required this.expiry,
    required this.actionLabel,
  });
  final IconData icon;
  final String title;
  final String description;
  final String status;
  final Color statusColor;
  final String expiry;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: MyShopColors.darkSlate)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
                Text(description,
                    style: MyShopTypography.caption.copyWith(fontSize: 10)),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Icon(_statusIcon(), size: 11, color: statusColor),
              const SizedBox(width: 4),
              Text(status,
                  style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: statusColor)),
            ]),
          ),
        ]),
        if (expiry.isNotEmpty || actionLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (expiry.isNotEmpty)
              Text(expiry,
                  style: MyShopTypography.caption.copyWith(fontSize: 10)),
            const Spacer(),
            Row(children: [
              Icon(_actionIcon(), size: 12, color: MyShopColors.textSecondary),
              const SizedBox(width: 4),
              Text(actionLabel,
                  style: MyShopTypography.body2.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary)),
            ]),
          ]),
        ],
      ]),
    );
  }

  IconData _statusIcon() {
    if (status == 'Verified') return Icons.check_circle;
    if (status == 'Expired') return Icons.error_outline;
    return Icons.access_time;
  }

  IconData _actionIcon() {
    if (actionLabel == 'View') return Icons.visibility_outlined;
    if (actionLabel == 'Renew') return Icons.refresh;
    return Icons.info_outline;
  }
}

class DottedUploadBox extends StatelessWidget {
  const DottedUploadBox({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.lg),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: MyShopColors.divider, style: BorderStyle.solid, width: 1.5),
      ),
      child: Column(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: MyShopColors.surfaceWhite,
            shape: BoxShape.circle,
            border: Border.all(color: MyShopColors.divider),
          ),
          child:
              const Icon(Icons.upload, size: 20, color: MyShopColors.textSecondary),
        ),
        const SizedBox(height: 12),
        const Text('Add new document',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
        const SizedBox(height: 4),
        Text('JPG, PNG or PDF formats supported.\nMaximum size 5MB.',
            textAlign: TextAlign.center,
            style: MyShopTypography.caption.copyWith(fontSize: 10)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Select File'),
          style: OutlinedButton.styleFrom(
            foregroundColor: MyShopColors.textPrimary,
            side: const BorderSide(color: MyShopColors.divider),
            backgroundColor: MyShopColors.surfaceWhite,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            textStyle: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}
