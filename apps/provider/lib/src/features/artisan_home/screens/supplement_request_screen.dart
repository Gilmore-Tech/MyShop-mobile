import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../providers/active_job_provider.dart';

/// PRD 5.3, 4.5.3 — Artisan: request a material-cost supplement on top
/// of the agreed bid.
///
/// Backend constraints (validated on the route):
///   * One supplement per job — second POST returns 409.
///   * Allowed after the job is in flight, before artisan_marked_complete.
///   * `reason` is mandatory and surfaced to the client verbatim.
///
/// Reads the active job from `activeJobProvider` (the same slot the
/// active-job screen drives). Pushed from the active-job overflow menu;
/// no extra args needed.
class SupplementRequestScreen extends ConsumerStatefulWidget {
  const SupplementRequestScreen({super.key});

  @override
  ConsumerState<SupplementRequestScreen> createState() =>
      _SupplementRequestScreenState();
}

class _SupplementRequestScreenState
    extends ConsumerState<SupplementRequestScreen> {
  final _amountCtl = TextEditingController();
  final _reasonCtl = TextEditingController();
  String? _errorMessage;
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtl.dispose();
    _reasonCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountText = _amountCtl.text.trim();
    final reason = _reasonCtl.text.trim();
    final cedis = double.tryParse(amountText);
    if (cedis == null || cedis <= 0) {
      setState(() => _errorMessage =
          'Enter the extra amount in cedis (e.g. 25 for GHS 25.00).');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _errorMessage = 'Tell the client why you need the extra.');
      return;
    }
    if (reason.length > 1000) {
      setState(
          () => _errorMessage = 'Reason is too long (max 1000 characters).');
      return;
    }
    final jobId = ref.read(activeJobProvider).job?.id;
    if (jobId == null) {
      setState(() =>
          _errorMessage = 'No active job — go back to the job and retry.');
      return;
    }
    setState(() {
      _errorMessage = null;
      _submitting = true;
    });
    try {
      await ref.read(jobServiceProvider).requestSupplement(
            jobId,
            amountPesewas: (cedis * 100).round(),
            reason: reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supplement request sent. Waiting on the client.'),
        ),
      );
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = 'Could not send the request. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceGrey,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        title: const Text(
          'Request supplement',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontWeight: FontWeight.w800,
          ),
        ),
        foregroundColor: MyShopColors.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(MyShopSpacing.md),
          children: [
            Container(
              padding: const EdgeInsets.all(MyShopSpacing.md),
              decoration: BoxDecoration(
                color: MyShopColors.primaryGoldLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline,
                    color: MyShopColors.primaryGoldDark),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'One supplement per job. Be specific so the client can decide quickly.',
                    style: TextStyle(
                      fontSize: 13,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: MyShopSpacing.md),
            TextField(
              controller: _amountCtl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Extra amount (GHS)',
                hintText: '25.00',
                prefixText: 'GHS  ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
            TextField(
              controller: _reasonCtl,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Why is this needed?',
                hintText:
                    'e.g. Wiring behind the wall is damaged and needs replacement — not visible from the original survey.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: MyShopSpacing.sm),
              Text(
                _errorMessage!,
                style: const TextStyle(color: MyShopColors.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: MyShopSpacing.lg),
            MyShopPrimaryButton(
              label: _submitting ? 'SENDING…' : 'SEND REQUEST',
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
