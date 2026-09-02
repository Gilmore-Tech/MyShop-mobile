import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../providers/registration_controller.dart';

class LegalAcceptanceChecklist extends ConsumerWidget {
  const LegalAcceptanceChecklist({super.key, required this.role});

  final ProviderType role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(registrationLegalDocumentsProvider(role));
    final showErrors = ref.watch(showRegistrationErrorsProvider);
    return documents.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Terms and Privacy could not be loaded. Registration cannot continue yet.',
            style: MyShopTypography.caption.copyWith(color: MyShopColors.error),
          ),
          TextButton(
            onPressed: () =>
                ref.invalidate(registrationLegalDocumentsProvider(role)),
            child: const Text('Retry'),
          ),
        ],
      ),
      data: (required) {
        final terms = _bySlug(required.documents, LegalSlugs.terms);
        final privacy = _bySlug(required.documents, LegalSlugs.privacy);
        final complete = required.documents.length == 2 &&
            terms != null &&
            privacy != null &&
            terms.documentId.isNotEmpty &&
            privacy.documentId.isNotEmpty;
        if (!complete) {
          return Text(
            'The current legal documents are incomplete. Please retry later.',
            style: MyShopTypography.caption.copyWith(color: MyShopColors.error),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(
              context: context,
              ref: ref,
              value: ref.watch(termsAcceptedProvider(role)),
              label: 'I accept the Terms of Service v${terms.version}',
              slug: terms.slug,
              onChanged: (value) =>
                  ref.read(termsAcceptedProvider(role).notifier).state = value,
            ),
            _row(
              context: context,
              ref: ref,
              value: ref.watch(privacyAcceptedProvider(role)),
              label: 'I acknowledge the Privacy Notice v${privacy.version}',
              slug: privacy.slug,
              onChanged: (value) => ref
                  .read(privacyAcceptedProvider(role).notifier)
                  .state = value,
            ),
            if (showErrors && !ref.watch(policyAcceptedProvider(role))) ...[
              const SizedBox(height: MyShopSpacing.xs),
              Text(
                'Accept both current documents to continue.',
                style: MyShopTypography.caption
                    .copyWith(color: MyShopColors.error),
              ),
            ],
          ],
        );
      },
    );
  }

  LegalDocument? _bySlug(List<LegalDocument> documents, String slug) {
    for (final document in documents) {
      if (document.slug == slug) return document;
    }
    return null;
  }

  Widget _row({
    required BuildContext context,
    required WidgetRef ref,
    required bool value,
    required String label,
    required String slug,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: (next) => onChanged(next ?? false),
          activeColor: MyShopColors.primaryGold,
        ),
        Expanded(
          child: TextButton(
            onPressed: () => context.push('/legal/$slug'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            child: Text(
              label,
              style: MyShopTypography.caption.copyWith(
                color: MyShopColors.primaryGoldDark,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
