import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/support_providers.dart';

class LegalDocumentRouteScreen extends ConsumerWidget {
  const LegalDocumentRouteScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(legalDocumentProvider(slug));

    return MyShopLegalDocumentScreen(
      slug: slug,
      state: docAsync.when(
        data: SupportLegalAsync<LegalDocument>.data,
        loading: SupportLegalAsync<LegalDocument>.loading,
        error: (e, _) => SupportLegalAsync<LegalDocument>.error(e),
      ),
      onRefresh: () async {
        ref.invalidate(legalDocumentProvider(slug));
        await ref.read(legalDocumentProvider(slug).future);
      },
    );
  }
}
