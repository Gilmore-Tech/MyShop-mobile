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

  bool _makeTouched = false;
  bool _modelTouched = false;
  bool _yearTouched = false;
  bool _plateTouched = false;
  bool _colorTouched = false;

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
    final showAll = ref.watch(showRegistrationErrorsProvider);

    return RegistrationStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyShopTextField(
            label: 'Make',
            hint: 'Toyota',
            controller: _makeCtrl,
            errorText: (_makeTouched || showAll)
                ? Validators.required(_makeCtrl.text, 'Make')
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(vehicleMake: v));
              if (_makeTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _makeTouched = true),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Model',
            hint: 'Corolla',
            controller: _modelCtrl,
            errorText: (_modelTouched || showAll)
                ? Validators.required(_modelCtrl.text, 'Model')
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(vehicleModel: v));
              if (_modelTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _modelTouched = true),
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
            errorText: (_yearTouched || showAll)
                ? Validators.vehicleYear(_yearCtrl.text)
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(vehicleYear: v));
              if (_yearTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _yearTouched = true),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'License plate',
            hint: 'GR 1234-20',
            controller: _plateCtrl,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              TextInputFormatter.withFunction((oldV, newV) => newV.copyWith(
                    text: newV.text.toUpperCase(),
                  )),
            ],
            errorText: (_plateTouched || showAll)
                ? Validators.licensePlate(_plateCtrl.text)
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(vehiclePlate: v.toUpperCase()));
              if (_plateTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _plateTouched = true),
          ),
          const SizedBox(height: MyShopSpacing.md),
          MyShopTextField(
            label: 'Colour',
            hint: 'White',
            controller: _colorCtrl,
            errorText: (_colorTouched || showAll)
                ? Validators.required(_colorCtrl.text, 'Colour')
                : null,
            onChanged: (v) {
              _apply((d) => d.copyWith(vehicleColor: v));
              if (_colorTouched || showAll) setState(() {});
            },
            onSubmitted: (_) => setState(() => _colorTouched = true),
          ),
        ],
      ),
    );
  }
}
