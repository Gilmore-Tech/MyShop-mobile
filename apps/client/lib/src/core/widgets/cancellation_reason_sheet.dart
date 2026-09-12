import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

Future<String?> showCancellationReasonSheet(
  BuildContext context, {
  required String title,
  required String helperText,
  required List<String> reasons,
  required String keepLabel,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MyShopColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CancellationReasonSheet(
      title: title,
      helperText: helperText,
      reasons: reasons,
      keepLabel: keepLabel,
    ),
  );
}

class _CancellationReasonSheet extends StatefulWidget {
  const _CancellationReasonSheet({
    required this.title,
    required this.helperText,
    required this.reasons,
    required this.keepLabel,
  });

  final String title;
  final String helperText;
  final List<String> reasons;
  final String keepLabel;

  @override
  State<_CancellationReasonSheet> createState() =>
      _CancellationReasonSheetState();
}

class _CancellationReasonSheetState extends State<_CancellationReasonSheet> {
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  void _submitOther() {
    final reason = _otherController.text.trim();
    if (reason.isEmpty) return;
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          MyShopSpacing.md,
          8,
          MyShopSpacing.md,
          MediaQuery.viewInsetsOf(context).bottom + MyShopSpacing.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: MyShopSpacing.md),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: MyShopColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.helperText,
                style: const TextStyle(
                  fontSize: 12,
                  color: MyShopColors.textSecondary,
                ),
              ),
              const SizedBox(height: MyShopSpacing.sm),
              for (final reason in widget.reasons)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(reason),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pop(reason),
                ),
              const Divider(),
              TextField(
                controller: _otherController,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Another reason',
                  hintText: 'Tell us briefly what happened',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitOther(),
              ),
              const SizedBox(height: MyShopSpacing.sm),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _otherController,
                builder: (_, value, __) => FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : _submitOther,
                  style: FilledButton.styleFrom(
                    backgroundColor: MyShopColors.error,
                  ),
                  child: const Text('Submit reason'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.keepLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
