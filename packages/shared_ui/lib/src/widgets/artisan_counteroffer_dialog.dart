import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_spacing.dart';

enum ArtisanWorkDurationUnit { hours, days }

const int maxArtisanWorkDurationHours = 23;
const int maxArtisanWorkDurationDays = 15;

int artisanWorkDurationMinutes({
  required int quantity,
  required ArtisanWorkDurationUnit unit,
}) {
  return switch (unit) {
    ArtisanWorkDurationUnit.hours => quantity * 60,
    ArtisanWorkDurationUnit.days => quantity * 24 * 60,
  };
}

({ArtisanWorkDurationUnit unit, int quantity})
    artisanWorkDurationSelectionFromMinutes(int minutes) {
  if (minutes >= 24 * 60) {
    return (
      unit: ArtisanWorkDurationUnit.days,
      quantity:
          (minutes / (24 * 60)).ceil().clamp(1, maxArtisanWorkDurationDays),
    );
  }
  return (
    unit: ArtisanWorkDurationUnit.hours,
    quantity: (minutes / 60).ceil().clamp(1, maxArtisanWorkDurationHours),
  );
}

String formatArtisanWorkDuration(int minutes) {
  if (minutes <= 0) return 'Not specified';
  final days = minutes ~/ (24 * 60);
  final hours = (minutes % (24 * 60)) ~/ 60;
  final remainingMinutes = minutes % 60;
  return [
    if (days > 0) '$days ${days == 1 ? 'day' : 'days'}',
    if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
    if (remainingMinutes > 0)
      '$remainingMinutes ${remainingMinutes == 1 ? 'minute' : 'minutes'}',
  ].join(' ');
}

class ArtisanCounterofferProposal {
  const ArtisanCounterofferProposal({
    required this.amountPesewas,
    required this.durationMinutes,
    required this.message,
  });

  final int amountPesewas;
  final int durationMinutes;
  final String message;
}

Future<ArtisanCounterofferProposal?> showArtisanCounterofferDialog(
  BuildContext context, {
  required int initialAmountPesewas,
  required int initialDurationMinutes,
  String? initialMessage,
  String title = 'Send a counteroffer',
}) {
  return showDialog<ArtisanCounterofferProposal>(
    context: context,
    builder: (_) => _ArtisanCounterofferDialog(
      title: title,
      initialAmountPesewas: initialAmountPesewas,
      initialDurationMinutes: initialDurationMinutes,
      initialMessage: initialMessage,
    ),
  );
}

class _ArtisanCounterofferDialog extends StatefulWidget {
  const _ArtisanCounterofferDialog({
    required this.title,
    required this.initialAmountPesewas,
    required this.initialDurationMinutes,
    required this.initialMessage,
  });

  final String title;
  final int initialAmountPesewas;
  final int initialDurationMinutes;
  final String? initialMessage;

  @override
  State<_ArtisanCounterofferDialog> createState() =>
      _ArtisanCounterofferDialogState();
}

class _ArtisanCounterofferDialogState
    extends State<_ArtisanCounterofferDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _message;
  late ArtisanWorkDurationUnit _durationUnit;
  late int _durationQuantity;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: (widget.initialAmountPesewas / 100).toStringAsFixed(2),
    );
    _message = TextEditingController(text: widget.initialMessage ?? '');
    final selection = artisanWorkDurationSelectionFromMinutes(
      widget.initialDurationMinutes,
    );
    _durationUnit = selection.unit;
    _durationQuantity = selection.quantity;
  }

  @override
  void dispose() {
    _amount.dispose();
    _message.dispose();
    super.dispose();
  }

  int get _maximumQuantity => switch (_durationUnit) {
        ArtisanWorkDurationUnit.hours => maxArtisanWorkDurationHours,
        ArtisanWorkDurationUnit.days => maxArtisanWorkDurationDays,
      };

  void _setDurationUnit(ArtisanWorkDurationUnit unit) {
    if (unit == _durationUnit) return;
    setState(() {
      _durationUnit = unit;
      _durationQuantity = 1;
      _error = null;
    });
  }

  void _submit() {
    final amountGhs = double.tryParse(_amount.text.trim());
    if (amountGhs == null || !amountGhs.isFinite || amountGhs <= 0) {
      setState(() => _error = 'Enter a valid proposed total.');
      return;
    }
    Navigator.of(context).pop(
      ArtisanCounterofferProposal(
        amountPesewas: (amountGhs * 100).round(),
        durationMinutes: artisanWorkDurationMinutes(
          quantity: _durationQuantity,
          unit: _durationUnit,
        ),
        message: _message.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'The existing bid deadline still applies. Sending a counteroffer does not add more time.',
            ),
            const SizedBox(height: MyShopSpacing.md),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'New proposed total (GHS)',
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              'How long will the job take?',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: MyShopSpacing.sm),
            SegmentedButton<ArtisanWorkDurationUnit>(
              segments: const [
                ButtonSegment(
                  value: ArtisanWorkDurationUnit.hours,
                  label: Text('Hours'),
                  icon: Icon(Icons.schedule_outlined),
                ),
                ButtonSegment(
                  value: ArtisanWorkDurationUnit.days,
                  label: Text('Days'),
                  icon: Icon(Icons.calendar_today_outlined),
                ),
              ],
              selected: {_durationUnit},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  _setDurationUnit(selection.single),
            ),
            const SizedBox(height: MyShopSpacing.sm),
            DropdownButtonFormField<int>(
              key: ValueKey(_durationUnit),
              initialValue: _durationQuantity,
              decoration: InputDecoration(
                labelText: _durationUnit == ArtisanWorkDurationUnit.hours
                    ? 'Number of hours'
                    : 'Number of days',
              ),
              items: [
                for (var quantity = 1; quantity <= _maximumQuantity; quantity++)
                  DropdownMenuItem(
                    value: quantity,
                    child: Text(
                      '$quantity ${_durationUnit == ArtisanWorkDurationUnit.hours ? (quantity == 1 ? 'hour' : 'hours') : (quantity == 1 ? 'day' : 'days')}',
                    ),
                  ),
              ],
              onChanged: (quantity) {
                if (quantity == null) return;
                setState(() {
                  _durationQuantity = quantity;
                  _error = null;
                });
              },
            ),
            const SizedBox(height: MyShopSpacing.md),
            TextField(
              controller: _message,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Message (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: MyShopSpacing.xs),
              Text(
                _error!,
                style: const TextStyle(color: MyShopColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Send counteroffer'),
        ),
      ],
    );
  }
}
