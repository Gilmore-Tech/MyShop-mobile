import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_typography.dart';

/// 6-box OTP pin input. Calls [onCompleted] when all boxes are filled
/// and [onChanged] on every keystroke.
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
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers =
        List.generate(widget.length, (_) => TextEditingController());
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

  String get _value => _controllers.map((c) => c.text).join();

  void _handleChange(int index, String raw) {
    if (raw.length > 1) {
      // paste
      final chars = raw.replaceAll(RegExp(r'[^0-9]'), '');
      for (var i = 0; i < widget.length; i++) {
        _controllers[i].text = i < chars.length ? chars[i] : '';
      }
      final next = chars.length >= widget.length ? widget.length - 1 : chars.length;
      _focusNodes[next].requestFocus();
    } else if (raw.isNotEmpty) {
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }
    final v = _value;
    widget.onChanged?.call(v);
    if (v.length == widget.length && !v.contains('')) {
      widget.onCompleted?.call(v);
    }
  }

  void _handleKey(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      widget.onChanged?.call(_value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(widget.length, (i) {
        return SizedBox(
          width: 48,
          height: 56,
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (e) => _handleKey(i, e),
            child: TextField(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              autofocus: widget.autofocus && i == 0,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
          ),
        );
      }),
    );
  }
}
