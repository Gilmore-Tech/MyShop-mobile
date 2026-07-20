import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/registration_controller.dart';
import 'registration_step_scaffold.dart';

/// Step 1 of artisan registration — personal details.
class ArtisanProfileStep extends ConsumerStatefulWidget {
  const ArtisanProfileStep({super.key});

  @override
  ConsumerState<ArtisanProfileStep> createState() => _ArtisanProfileStepState();
}

class _ArtisanProfileStepState extends ConsumerState<ArtisanProfileStep>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _ghanaCardCtrl;

  bool _nameTouched = false;
  bool _emailTouched = false;
  bool _ghanaCardTouched = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(artisanRegistrationProvider);
    _nameCtrl = TextEditingController(text: draft.fullName);
    _emailCtrl = TextEditingController(text: draft.email);
    _ghanaCardCtrl = TextEditingController(text: draft.ghanaCardNumber);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _ghanaCardCtrl.dispose();
    super.dispose();
  }

  void _apply(
    ArtisanRegistrationDraft Function(ArtisanRegistrationDraft) update,
  ) {
    final notifier = ref.read(artisanRegistrationProvider.notifier);
    notifier.update(update(ref.read(artisanRegistrationProvider)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final showAll = ref.watch(showRegistrationErrorsProvider);

    return RegistrationStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyShopTextField(
            label: 'Full name',
            hint: 'Enter your full name',
            controller: _nameCtrl,
            errorText: (_nameTouched || showAll)
                ? Validators.fullName(_nameCtrl.text)
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(fullName: v));
              if (_nameTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _nameTouched = true),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Email',
            hint: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            controller: _emailCtrl,
            errorText: (_emailTouched || showAll)
                ? Validators.email(_emailCtrl.text)
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(email: v));
              if (_emailTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _emailTouched = true),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Ghana Card number',
            hint: 'GHA-XXXXXXXXX-X',
            controller: _ghanaCardCtrl,
            textCapitalization: TextCapitalization.characters,
            errorText: (_ghanaCardTouched || showAll)
                ? Validators.ghanaCard(_ghanaCardCtrl.text)
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(ghanaCardNumber: v));
              if (_ghanaCardTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _ghanaCardTouched = true),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'MyShop manually reviews your identity documents before a Regional Manager approves you to go online.',
            style: MyShopTypography.caption,
          ),
        ],
      ),
    );
  }
}
