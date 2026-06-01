import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Section header (uppercase Raleway w900) followed by a list of children
/// separated by faint dividers — used to group rows in Account Settings.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: MyShopSpacing.sm),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textSecondary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1)
            const Padding(
              padding: EdgeInsets.only(left: 56),
              child: Divider(
                  height: 1, thickness: 0.5, color: MyShopColors.divider),
            ),
        ],
      ],
    );
  }
}
