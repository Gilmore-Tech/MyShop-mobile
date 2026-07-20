import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../../auth/providers/auth_controller.dart';
import '../providers/support_providers.dart';

class LegalConsentRouteScreen extends ConsumerStatefulWidget {
  const LegalConsentRouteScreen({super.key});

  @override
  ConsumerState<LegalConsentRouteScreen> createState() =>
      _LegalConsentRouteScreenState();
}

class _LegalConsentRouteScreenState
    extends ConsumerState<LegalConsentRouteScreen> {
  bool _submitting = false;
  Object? _submitError;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(legalConsentStatusProvider);
    return MyShopLegalConsentScreen(
      status: status.valueOrNull,
      loading: status.isLoading,
      submitting: _submitting,
      error: _submitError ?? status.error,
      onRetry: () async {
        setState(() => _submitError = null);
        ref.invalidate(legalConsentStatusProvider);
        await ref.read(legalConsentStatusProvider.future);
      },
      onOpenDocument: (document) =>
          context.push(AppRoutes.legalDocumentPath(document.slug)),
      onAccept: _accept,
      onSupport: () => context.push(AppRoutes.profileSupport),
      onLogout: () => ref.read(clientAuthControllerProvider.notifier).logout(),
    );
  }

  Future<void> _accept(List<LegalAcceptanceSelection> acceptances) async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(legalServiceProvider).acceptCurrent(acceptances);
      ref.invalidate(legalConsentStatusProvider);
      await ref.read(legalConsentStatusProvider.future);
      if (mounted) context.go(AppRoutes.home);
    } catch (error) {
      if (mounted) setState(() => _submitError = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
