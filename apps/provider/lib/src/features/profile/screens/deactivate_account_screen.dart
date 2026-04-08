import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Deactivate Account confirmation flow.
///
/// Figma: node 313:27644
class DeactivateAccountScreen extends StatefulWidget {
  const DeactivateAccountScreen({super.key});

  @override
  State<DeactivateAccountScreen> createState() =>
      _DeactivateAccountScreenState();
}

class _DeactivateAccountScreenState extends State<DeactivateAccountScreen> {
  String? _selectedReason;
  bool _confirmed = false;

  static const _reasons = [
    'Taking a break',
    'Switching to another platform',
    'Earnings too low',
    'Too many cancellations',
    'Privacy concerns',
    'Other',
  ];

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
        title: const Text('Deactivate Account',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          // Warning banner
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.errorLight,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: MyShopColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 22, color: MyShopColors.error),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('We\'re sorry to see you go',
                            style: TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: MyShopColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(
                            'Deactivation is reversible within 24 hours. After that your data is retained for 90 days before being permanently deleted.',
                            style: MyShopTypography.body2
                                .copyWith(fontSize: 11, height: 1.4)),
                      ])),
                ]),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          const Text('TELL US WHY',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.0)),
          const SizedBox(height: MyShopSpacing.sm),

          for (final reason in _reasons) ...[
            _ReasonRow(
              label: reason,
              isSelected: _selectedReason == reason,
              onTap: () => setState(() => _selectedReason = reason),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: MyShopSpacing.lg),

          // Confirm checkbox
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _confirmed,
                onChanged: (v) => setState(() => _confirmed = v ?? false),
                activeColor: MyShopColors.error,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _confirmed = !_confirmed),
                  child: Text(
                    'I understand that my outstanding clawback balance must be settled before deactivation can complete.',
                    style: MyShopTypography.body2
                        .copyWith(fontSize: 12, height: 1.4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),

          ElevatedButton.icon(
            onPressed: (_selectedReason != null && _confirmed) ? () {} : null,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Continue Deactivation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyShopColors.error,
              foregroundColor: MyShopColors.textOnPrimary,
              disabledBackgroundColor: MyShopColors.disabled,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyShopColors.textPrimary,
              side: const BorderSide(color: MyShopColors.divider),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
            child: const Text('Keep My Account'),
          ),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: MyShopSpacing.md, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? MyShopColors.primaryGoldLight
              : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected
                  ? MyShopColors.primaryGold
                  : MyShopColors.divider,
              width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: isSelected
                  ? MyShopColors.primaryGold
                  : MyShopColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
