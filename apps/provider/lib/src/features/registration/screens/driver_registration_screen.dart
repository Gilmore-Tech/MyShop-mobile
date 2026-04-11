import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/registration_controller.dart';
import '../widgets/driver_profile_step.dart';
import '../widgets/driver_review_step.dart';
import '../widgets/driver_vehicle_step.dart';
import '../widgets/registration_step_scaffold.dart';

/// Driver onboarding — 3-step wizard (Profile → Vehicle → Review).
class DriverRegistrationScreen extends ConsumerStatefulWidget {
  const DriverRegistrationScreen({super.key});

  @override
  ConsumerState<DriverRegistrationScreen> createState() =>
      _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState
    extends ConsumerState<DriverRegistrationScreen> {
  static const _steps = <MyShopStepItem>[
    MyShopStepItem(label: 'Profile', icon: Icons.person_outline),
    MyShopStepItem(label: 'Vehicle', icon: Icons.directions_car_outlined),
    MyShopStepItem(label: 'Review', icon: Icons.fact_check_outlined),
  ];

  static const _stepTitles = <(String, String)>[
    ('Your profile', 'Tell us about yourself'),
    ('Vehicle details', "About the car you'll drive"),
    ('Almost done!', 'Review and confirm'),
  ];

  final PageController _pageController = PageController();
  int _currentStep = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _canAdvance(DriverRegistrationDraft d) {
    switch (_currentStep) {
      case 0:
        return d.fullName.isNotEmpty &&
            d.email.isNotEmpty &&
            d.ghanaCardNumber.isNotEmpty;
      case 1:
        return d.vehicleMake.isNotEmpty &&
            d.vehicleModel.isNotEmpty &&
            d.vehicleYear.isNotEmpty &&
            d.vehiclePlate.isNotEmpty &&
            d.vehicleColor.isNotEmpty;
      default:
        return d.isComplete;
    }
  }

  void _clearError() {
    final notifier = ref.read(driverRegistrationProvider.notifier);
    final draft = ref.read(driverRegistrationProvider);
    if (draft.error != null) {
      notifier.update(draft.copyWith(clearError: true));
    }
  }

  void _goTo(int step) {
    _clearError();
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
    );
  }

  void _goNext() => _goTo(_currentStep + 1);
  void _goBack() => _goTo(_currentStep - 1);

  void _finish() {
    _clearError();
    context.go('/signup/phone');
  }

  void _handleAppBarBack() {
    if (_currentStep == 0) {
      context.go('/signup/role');
    } else {
      _goBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(driverRegistrationProvider);
    final isLast = _currentStep == _steps.length - 1;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentStep == 0) {
          context.go('/signup/role');
        } else {
          _goBack();
        }
      },
      child: RegistrationStepScaffold(
        steps: _steps,
        currentIndex: _currentStep,
        title: _stepTitles[_currentStep].$1,
        subtitle: _stepTitles[_currentStep].$2,
        onAppBarBack: _handleAppBarBack,
        onBack: _currentStep == 0 ? null : _goBack,
        onContinue: isLast ? _finish : _goNext,
        continueLabel: isLast ? 'Create Account' : 'Continue',
        isContinueEnabled: _canAdvance(draft),
        isSubmitting: draft.isSubmitting,
        errorText: draft.error,
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            const DriverProfileStep(),
            const DriverVehicleStep(),
            DriverReviewStep(onEditStep: _goTo),
          ],
        ),
      ),
    );
  }
}
