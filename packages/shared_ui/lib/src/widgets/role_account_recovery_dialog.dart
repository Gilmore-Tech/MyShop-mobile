import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/myshop_colors.dart';

Future<void> showMyShopRoleAccountRecoveryDialog({
  required BuildContext context,
  required String phone,
  required String role,
  required String requestKey,
  required Future<void> Function() requestOtp,
  required Future<void> Function(String otp, String requestKey) verifyOtp,
  required String Function(Object error) errorMessage,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RoleAccountRecoveryDialog(
      phone: phone,
      role: role,
      requestKey: requestKey,
      requestOtp: requestOtp,
      verifyOtp: verifyOtp,
      errorMessage: errorMessage,
    ),
  );
}

enum _RecoveryStep { introduction, otp, complete }

class _RoleAccountRecoveryDialog extends StatefulWidget {
  const _RoleAccountRecoveryDialog({
    required this.phone,
    required this.role,
    required this.requestKey,
    required this.requestOtp,
    required this.verifyOtp,
    required this.errorMessage,
  });

  final String phone;
  final String role;
  final String requestKey;
  final Future<void> Function() requestOtp;
  final Future<void> Function(String otp, String requestKey) verifyOtp;
  final String Function(Object error) errorMessage;

  @override
  State<_RoleAccountRecoveryDialog> createState() =>
      _RoleAccountRecoveryDialogState();
}

class _RoleAccountRecoveryDialogState
    extends State<_RoleAccountRecoveryDialog> {
  final _otp = TextEditingController();
  _RecoveryStep _step = _RecoveryStep.introduction;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  String get _roleLabel => switch (widget.role) {
        'client' => 'client',
        'driver' => 'driver',
        'artisan' => 'artisan',
        _ => 'account',
      };

  String get _maskedPhone {
    final cleaned = widget.phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.length < 7) return 'your phone';
    return '${cleaned.substring(0, 6)}••••${cleaned.substring(cleaned.length - 3)}';
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.requestOtp();
      if (!mounted) return;
      setState(() => _step = _RecoveryStep.otp);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || _otp.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The request key was created once when this dialog opened. Reusing it
      // makes a retry safe if the first HTTP response was lost after filing.
      await widget.verifyOtp(_otp.text, widget.requestKey);
      if (!mounted) return;
      setState(() => _step = _RecoveryStep.complete);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = widget.errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          _step == _RecoveryStep.complete
              ? 'Recovery request submitted'
              : 'Recover deleted $_roleLabel role',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_step == _RecoveryStep.introduction) ...[
                const Text(
                  'Your old role is still in its 90-day retention period. '
                  'Verify the phone number that owned it to request recovery.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Only the $_roleLabel role will be considered. Your other '
                  'roles and their data remain separate and unchanged.',
                  style: const TextStyle(color: MyShopColors.textSecondary),
                ),
              ] else if (_step == _RecoveryStep.otp) ...[
                Text('Enter the 6-digit code sent to $_maskedPhone.'),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('role-recovery-otp'),
                  controller: _otp,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _verify(),
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _sendCode,
                  child: const Text('Send the same flow a new code'),
                ),
              ] else ...[
                const Icon(
                  Icons.check_circle_rounded,
                  color: MyShopColors.success,
                  size: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.role == 'client'
                      ? 'Global Operations will review this exact client role. '
                          'You will be notified after approval.'
                      : 'A regional Admin will accept the request, then every '
                          'document must be revalidated by the category '
                          'Coordinator and finally approved by the Regional '
                          'Manager. You cannot go online before that.',
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: MyShopColors.error.withAlpha(18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: MyShopColors.error),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_step != _RecoveryStep.complete)
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          if (_step == _RecoveryStep.introduction)
            FilledButton(
              key: const Key('role-recovery-send-code'),
              onPressed: _busy ? null : _sendCode,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send verification code'),
            ),
          if (_step == _RecoveryStep.otp)
            FilledButton(
              key: const Key('role-recovery-submit'),
              onPressed: _busy || _otp.text.length != 6 ? null : _verify,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit recovery request'),
            ),
          if (_step == _RecoveryStep.complete)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
        ],
      ),
    );
  }
}
