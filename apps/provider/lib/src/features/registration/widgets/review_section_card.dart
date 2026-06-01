import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// One label/value row rendered inside a [ReviewSectionCard].
class ReviewRow {
  const ReviewRow({required this.label, required this.value});

  final String label;
  final String value;
}

/// Card shown on the registration review step. Displays a section title
/// with icon, an "Edit" button, and a list of label/value rows.
class ReviewSectionCard extends StatelessWidget {
  const ReviewSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.rows,
    required this.onEdit,
  });

  final IconData icon;
  final String title;
  final List<ReviewRow> rows;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      padding: const EdgeInsets.all(MyShopSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: MyShopColors.primaryGoldLight,
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(icon, size: 18, color: MyShopColors.primaryGoldDark),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Text(title, style: MyShopTypography.h3),
              ),
              TextButton.icon(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: MyShopColors.primaryGoldDark,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(
                  'Edit',
                  style: MyShopTypography.button.copyWith(
                    color: MyShopColors.primaryGoldDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          const Divider(height: 1, color: MyShopColors.divider),
          const SizedBox(height: MyShopSpacing.sm),
          for (var i = 0; i < rows.length; i++) ...[
            _RowView(row: rows[i]),
            if (i < rows.length - 1) const SizedBox(height: MyShopSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _RowView extends StatelessWidget {
  const _RowView({required this.row});

  final ReviewRow row;

  @override
  Widget build(BuildContext context) {
    final value = row.value.trim().isEmpty ? '—' : row.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            row.label,
            style: MyShopTypography.body2,
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
