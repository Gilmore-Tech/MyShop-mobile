import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/registration_controller.dart';
import '../widgets/artisan_business_step.dart';
import '../widgets/artisan_profile_step.dart';
import '../widgets/artisan_review_step.dart';
import '../widgets/registration_step_scaffold.dart';

/// Artisan onboarding — 3-step wizard (Profile → Business → Review).
class ArtisanRegistrationScreen extends ConsumerStatefulWidget {
  const ArtisanRegistrationScreen({super.key});

  @override
  ConsumerState<ArtisanRegistrationScreen> createState() =>
      _ArtisanRegistrationScreenState();
}

class _ArtisanRegistrationScreenState
    extends ConsumerState<ArtisanRegistrationScreen> {
  static const _steps = <MyShopStepItem>[
    MyShopStepItem(label: 'Profile', icon: Icons.person_outline),
    MyShopStepItem(label: 'Business', icon: Icons.work_outline),
    MyShopStepItem(label: 'Review', icon: Icons.fact_check_outlined),
  ];

  static const _stepTitles = <(String, String)>[
    ('Your profile', 'Tell us about yourself'),
    ('Your business', 'What you offer and where'),
    ('Almost done!', 'Review and confirm'),
  ];

  final PageController _pageController = PageController();
  int _currentStep = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _canAdvance(ArtisanRegistrationDraft d) {
    switch (_currentStep) {
      case 0:
        return d.fullName.isNotEmpty &&
            d.email.isNotEmpty &&
            d.ghanaCardNumber.isNotEmpty;
      case 1:
        return d.businessName.isNotEmpty &&
            d.tradeCategory.isNotEmpty &&
            d.serviceCategories.isNotEmpty;
      default:
        return d.isComplete;
    }
  }

  void _clearError() {
    final notifier = ref.read(artisanRegistrationProvider.notifier);
    final draft = ref.read(artisanRegistrationProvider);
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
    final draft = ref.watch(artisanRegistrationProvider);
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
            const ArtisanProfileStep(),
            const ArtisanBusinessStep(),
            ArtisanReviewStep(onEditStep: _goTo),
          ],
        ),
      ),
    );
  }
}
