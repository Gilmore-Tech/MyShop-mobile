import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/registration_controller.dart';
import 'registration_step_scaffold.dart';

/// Step 1 of driver registration — personal details.
class DriverProfileStep extends ConsumerStatefulWidget {
  const DriverProfileStep({super.key});

  @override
  ConsumerState<DriverProfileStep> createState() => _DriverProfileStepState();
}

class _DriverProfileStepState extends ConsumerState<DriverProfileStep>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _ghanaCardCtrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(driverRegistrationProvider);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final notifier = ref.read(driverRegistrationProvider.notifier);

    return RegistrationStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyShopTextField(
            label: 'Full name',
            hint: 'Enter your full name',
            controller: _nameCtrl,
            onChanged: (v) => notifier.update(
                ref.read(driverRegistrationProvider).copyWith(fullName: v)),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Email',
            hint: 'name@example.com',
            keyboardType: TextInputType.emailAddress,
            controller: _emailCtrl,
            onChanged: (v) => notifier.update(
                ref.read(driverRegistrationProvider).copyWith(email: v)),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Ghana Card number',
            hint: 'GHA-XXXXXXXXX-X',
            controller: _ghanaCardCtrl,
            onChanged: (v) => notifier.update(
              ref.read(driverRegistrationProvider).copyWith(ghanaCardNumber: v),
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'We use this to verify your identity with Smile Identity before you can accept rides.',
            style: MyShopTypography.caption,
          ),
        ],
      ),
    );
  }
}
