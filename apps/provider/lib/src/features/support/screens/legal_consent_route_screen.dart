import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';
import '../providers/support_providers.dart';

MyShopLegalSubmissionIssue classifyLegalConsentSubmissionIssue(Object error) {
  if (error is NetworkException) {
    return switch (error.kind) {
      NetworkFailureKind.offline => MyShopLegalSubmissionIssue.offline,
      NetworkFailureKind.timeout => MyShopLegalSubmissionIssue.timeout,
      NetworkFailureKind.unavailable => MyShopLegalSubmissionIssue.unavailable,
    };
  }
  if (error is ApiException && error.statusCode == 422) {
    return MyShopLegalSubmissionIssue.invalidSelection;
  }
  return MyShopLegalSubmissionIssue.unavailable;
}

MyShopLegalSubmissionIssue? legalConsentSubmissionIssueForSession({
  required RoleSessionIdentity owner,
  required RoleSessionIdentity? currentIdentity,
  required Object error,
}) {
  if (currentIdentity != owner) return null;
  return classifyLegalConsentSubmissionIssue(error);
}

MyShopLegalSubmissionIssue? legalConsentConfirmationIssueForSession({
  required RoleSessionIdentity owner,
  required RoleSessionIdentity? currentIdentity,
  required ScopedLegalConsentStatus? refreshed,
}) {
  if (currentIdentity != owner) return null;
  if (refreshed == null ||
      !refreshed.belongsTo(owner) ||
      refreshed.status.requiresConsent) {
    return MyShopLegalSubmissionIssue.confirmationPending;
  }
  return null;
}

ScopedLegalConsentStatus? visibleLegalConsentStatusForSession({
  required RoleSessionIdentity? currentIdentity,
  required ScopedLegalConsentStatus? live,
  required ScopedLegalConsentStatus? retained,
}) {
  if (currentIdentity == null) return null;
  if (live?.belongsTo(currentIdentity) == true) return live;
  if (retained?.belongsTo(currentIdentity) == true) return retained;
  return null;
}

class LegalConsentRouteScreen extends ConsumerStatefulWidget {
  const LegalConsentRouteScreen({super.key});

  @override
  ConsumerState<LegalConsentRouteScreen> createState() =>
      _LegalConsentRouteScreenState();
}

class _LegalConsentRouteScreenState
    extends ConsumerState<LegalConsentRouteScreen> {
  bool _submitting = false;
  MyShopLegalSubmissionIssue? _submissionIssue;
  RoleSessionIdentity? _submissionIssueOwner;
  ScopedLegalConsentStatus? _retainedStatus;

  @override
  Widget build(BuildContext context) {
    final scopedStatus = ref.watch(legalConsentStatusProvider);
    final currentIdentity =
        ref.watch(providerRoleSessionIdentityProvider).valueOrNull;
    final visibleStatus = visibleLegalConsentStatusForSession(
      currentIdentity: currentIdentity,
      live: scopedStatus.valueOrNull,
      retained: _retainedStatus,
    );
    return MyShopLegalConsentScreen(
      status: visibleStatus?.status,
      loading: scopedStatus.isLoading,
      submitting: _submitting,
      error: scopedStatus.error,
      submissionIssue:
          _submissionIssueOwner == currentIdentity ? _submissionIssue : null,
      onRetry: _retry,
      onOpenDocument: (document) => context.push('/legal/${document.slug}'),
      onAccept: _accept,
      onSupport: () => context.push('/account/support'),
      onLogout: () => ref.read(authControllerProvider.notifier).logout(),
    );
  }

  Future<void> _accept(List<LegalAcceptanceSelection> acceptances) async {
    final owner = _currentIdentity();
    if (owner == null) return;
    _retainLoadedStatus(owner);
    setState(() {
      _submitting = true;
      _submissionIssue = null;
      _submissionIssueOwner = null;
    });
    try {
      await ref.read(legalServiceProvider).acceptCurrent(acceptances);
      if (_currentIdentity() != owner) return;
      ref.invalidate(legalConsentStatusProvider);
      final refreshed = await ref.read(legalConsentStatusProvider.future);
      final issue = legalConsentConfirmationIssueForSession(
        owner: owner,
        currentIdentity: _currentIdentity(),
        refreshed: refreshed,
      );
      if (_currentIdentity() != owner) return;
      if (issue != null) {
        if (mounted) {
          setState(() {
            _submissionIssue = issue;
            _submissionIssueOwner = owner;
          });
        }
        return;
      }
      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted) {
        final issue = legalConsentSubmissionIssueForSession(
          owner: owner,
          currentIdentity: _currentIdentity(),
          error: error,
        );
        if (issue != null && _currentIdentity() == owner) {
          setState(() {
            _submissionIssue = issue;
            _submissionIssueOwner = owner;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _retry() async {
    final owner = _currentIdentity();
    if (owner != null) _retainLoadedStatus(owner);
    setState(() {
      _submissionIssue = null;
      _submissionIssueOwner = null;
    });
    try {
      ref.invalidate(legalConsentStatusProvider);
      await ref.read(legalConsentStatusProvider.future);
    } catch (error) {
      if (mounted && owner != null) {
        final issue = legalConsentSubmissionIssueForSession(
          owner: owner,
          currentIdentity: _currentIdentity(),
          error: error,
        );
        if (issue != null && _currentIdentity() == owner) {
          setState(() {
            _submissionIssue = issue;
            _submissionIssueOwner = owner;
          });
        }
      }
    }
  }

  RoleSessionIdentity? _currentIdentity() =>
      ref.read(providerRoleSessionIdentityProvider).valueOrNull;

  void _retainLoadedStatus(RoleSessionIdentity owner) {
    final loaded = ref.read(legalConsentStatusProvider).valueOrNull;
    if (loaded?.belongsTo(owner) == true) _retainedStatus = loaded;
  }
}
