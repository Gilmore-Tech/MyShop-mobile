import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/registration_controller.dart';
import 'registration_step_scaffold.dart';

/// Step 2 of driver registration — vehicle details.
class DriverVehicleStep extends ConsumerStatefulWidget {
  const DriverVehicleStep({super.key});

  @override
  ConsumerState<DriverVehicleStep> createState() => _DriverVehicleStepState();
}

class _DriverVehicleStepState extends ConsumerState<DriverVehicleStep>
    with AutomaticKeepAliveClientMixin {
  late final TextEditingController _makeCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _plateCtrl;
  late final TextEditingController _colorCtrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(driverRegistrationProvider);
    _makeCtrl = TextEditingController(text: draft.vehicleMake);
    _modelCtrl = TextEditingController(text: draft.vehicleModel);
    _yearCtrl = TextEditingController(text: draft.vehicleYear);
    _plateCtrl = TextEditingController(text: draft.vehiclePlate);
    _colorCtrl = TextEditingController(text: draft.vehicleColor);
  }

  @override
  void dispose() {
    _makeCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _plateCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  void _apply(
    DriverRegistrationDraft Function(DriverRegistrationDraft) update,
  ) {
    final notifier = ref.read(driverRegistrationProvider.notifier);
    notifier.update(update(ref.read(driverRegistrationProvider)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RegistrationStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyShopTextField(
            label: 'Make',
            hint: 'Toyota',
            controller: _makeCtrl,
            onChanged: (v) => _apply((d) => d.copyWith(vehicleMake: v)),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Model',
            hint: 'Corolla',
            controller: _modelCtrl,
            onChanged: (v) => _apply((d) => d.copyWith(vehicleModel: v)),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Year',
            hint: '2018',
            keyboardType: TextInputType.number,
            controller: _yearCtrl,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            onChanged: (v) => _apply((d) => d.copyWith(vehicleYear: v)),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'License plate',
            hint: 'GR 1234-20',
            controller: _plateCtrl,
            inputFormatters: [
              TextInputFormatter.withFunction((oldV, newV) => newV.copyWith(
                    text: newV.text.toUpperCase(),
                  )),
            ],
            onChanged: (v) =>
                _apply((d) => d.copyWith(vehiclePlate: v.toUpperCase())),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Colour',
            hint: 'White',
            controller: _colorCtrl,
            onChanged: (v) => _apply((d) => d.copyWith(vehicleColor: v)),
          ),
        ],
      ),
    );
  }
}
