import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_typography.dart';

/// 6-box OTP pin input. Calls [onCompleted] when all boxes are filled
/// and [onChanged] on every keystroke.
///
/// Each box is seeded with an invisible zero-width space ([_seed]). That
/// guarantees a backspace always produces an `onChanged` — even on an
/// otherwise-empty box — so delete works consistently across platforms.
/// Android soft keyboards do NOT emit a hardware backspace `KeyEvent` for an
/// empty field, so relying on key events (the previous approach) left digits
/// stuck once a box emptied. Driving everything through `onChanged` avoids
/// that entirely.
class MyShopOtpInput extends StatefulWidget {
  const MyShopOtpInput({
    super.key,
    this.length = 6,
    this.onChanged,
    this.onCompleted,
    this.hasError = false,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool hasError;
  final bool autofocus;

  @override
  State<MyShopOtpInput> createState() => _MyShopOtpInputState();
}

class _MyShopOtpInputState extends State<MyShopOtpInput> {
  /// Zero-width space kept in every box so backspace always fires `onChanged`.
  static const _seed = '\u200B';

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.length,
      (_) => TextEditingController(text: _seed)
        ..selection = const TextSelection.collapsed(offset: _seed.length),
    );
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  /// The entered digits with the invisible seed stripped from each box.
  String get _value =>
      _controllers.map((c) => c.text.replaceAll(_seed, '')).join();

  /// Reset a box to `seed + digit` (digit may be empty to clear it), keeping
  /// the caret after the digit so the next backspace targets it first.
  void _setBox(int i, String digit) {
    final text = '$_seed$digit';
    _controllers[i].value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _emit() {
    final v = _value;
    widget.onChanged?.call(v);
    if (v.length == widget.length) {
      widget.onCompleted?.call(v);
    }
  }

  void _handleChange(int index, String raw) {
    // The seed itself was deleted → backspace on an already-empty box.
    // Re-seed here, then step back and clear the previous box.
    if (raw.isEmpty) {
      _setBox(index, '');
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
        _setBox(index - 1, '');
      }
      _emit();
      return;
    }

    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    // A digit was deleted from a filled box (only the seed remains) or a
    // non-digit was entered → leave this box empty and stay put.
    if (digits.isEmpty) {
      _setBox(index, '');
      _emit();
      return;
    }

    // A full-length code was pasted or autofilled → spread across all boxes.
    if (digits.length >= widget.length) {
      for (var i = 0; i < widget.length; i++) {
        _setBox(i, digits[i]);
      }
      _focusNodes[widget.length - 1].requestFocus();
      _emit();
      return;
    }

    // Normal single-digit entry: keep the most recent digit, advance focus.
    _setBox(index, digits[digits.length - 1]);
    if (index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
    }
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(widget.length, (i) {
        return SizedBox(
          width: 48,
          height: 56,
          child: TextField(
            controller: _controllers[i],
            focusNode: _focusNodes[i],
            autofocus: widget.autofocus && i == 0,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: MyShopTypography.h2,
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: MyShopColors.surfaceWhite,
              contentPadding: EdgeInsets.zero,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: widget.hasError
                      ? MyShopColors.error
                      : MyShopColors.divider,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: widget.hasError
                      ? MyShopColors.error
                      : MyShopColors.primaryGold,
                  width: 1.5,
                ),
              ),
            ),
            onChanged: (v) => _handleChange(i, v),
          ),
        );
      }),
    );
  }
}
