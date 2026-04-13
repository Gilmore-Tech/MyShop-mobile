import 'package:flutter/material.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);

class PaymentMethodRow extends StatelessWidget {
  final VoidCallback? onChangeTap;

  const PaymentMethodRow({super.key, this.onChangeTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MtnIcon(),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'MTN Mobile Money',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
        ),
        GestureDetector(
          onTap: onChangeTap,
          child: const Text(
            'Change',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _gold,
            ),
          ),
        ),
      ],
    );
  }
}

class _MtnIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: Color(0xFFFFCC00), // MTN yellow
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'M',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: Color(0xFF161A1D),
          ),
        ),
      ),
    );
  }
}
