import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../providers/regions_provider.dart';
import '../providers/registration_controller.dart';
import '../widgets/artisan_business_step.dart';
import '../widgets/artisan_profile_step.dart';
import '../widgets/artisan_review_step.dart';
import '../widgets/region_step.dart';
import '../widgets/registration_step_scaffold.dart';

/// Artisan onboarding — 4-step wizard
/// (Profile → Business → Region → Review).
class ArtisanRegistrationScreen extends ConsumerStatefulWidget {
  const ArtisanRegistrationScreen({
    super.key,
    this.initialStep = 0,
  });

  final int initialStep;

  @override
  ConsumerState<ArtisanRegistrationScreen> createState() =>
      _ArtisanRegistrationScreenState();
}

class _ArtisanRegistrationScreenState
    extends ConsumerState<ArtisanRegistrationScreen> {
  static const _steps = <MyShopStepItem>[
    MyShopStepItem(label: 'Profile', icon: Icons.person_outline),
    MyShopStepItem(label: 'Business', icon: Icons.work_outline),
    MyShopStepItem(label: 'Region', icon: Icons.location_on_outlined),
    MyShopStepItem(label: 'Review', icon: Icons.fact_check_outlined),
  ];

  static const _stepTitles = <(String, String)>[
    ('Your profile', 'Tell us about yourself'),
    ('Your business', 'What you offer and where'),
    ('Your region', 'Where you operate'),
    ('Almost done!', 'Review and confirm'),
  ];

  late final PageController _pageController;
  late int _currentStep;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep.clamp(0, _steps.length - 1);
    _pageController = PageController(initialPage: _currentStep);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _canAdvance(ArtisanRegistrationDraft d) {
    switch (_currentStep) {
      case 0:
        return Validators.fullName(d.fullName) == null &&
            validateRegistrationEmail(d.email) == null &&
            validateOptionalReferralCode(d.referralCode) == null;
      case 1:
        return d.businessName.isNotEmpty && d.serviceCategories.isNotEmpty;
      case 2:
        // Region is a pre-selected confirmation in the pilot. Only block
        // when the user genuinely has more than one region to choose from
        // and hasn't picked one; a single (auto-selected) or unavailable
        // list never blocks (backend defaults to the pilot region).
        final regions = ref.read(regionsProvider).valueOrNull;
        if (regions != null && regions.length > 1) {
          return d.regionId.isNotEmpty;
        }
        return true;
      default:
        return d.isComplete;
    }
  }

  void _goTo(int step) {
    // Reset error visibility when moving to a new step.
    ref.read(showRegistrationErrorsProvider.notifier).state = false;
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
    );
  }

  void _goNext() => _goTo(_currentStep + 1);
  void _goBack() => _goTo(_currentStep - 1);

  void _handleContinue() {
    final draft = ref.read(artisanRegistrationProvider);
    if (_canAdvance(draft)) {
      _goNext();
    } else {
      // Reveal all validation errors on the current step.
      ref.read(showRegistrationErrorsProvider.notifier).state = true;
    }
  }

  void _finish() {
    final draft = ref.read(artisanRegistrationProvider);
    final policyAccepted = ref.read(
      policyAcceptedProvider(ProviderType.artisan),
    );
    if (_canAdvance(draft) && policyAccepted) {
      ref.read(showRegistrationErrorsProvider.notifier).state = false;
      context.go('/signup/phone');
    } else {
      ref.read(showRegistrationErrorsProvider.notifier).state = true;
    }
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
    final policyAccepted = ref.watch(
      policyAcceptedProvider(ProviderType.artisan),
    );
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
        onContinue: isLast ? _finish : _handleContinue,
        continueLabel: isLast ? 'Create Account' : 'Continue',
        isContinueEnabled:
            isLast ? _canAdvance(draft) && policyAccepted : _canAdvance(draft),
        isSubmitting: false,
        errorText: null,
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            const ArtisanProfileStep(),
            const ArtisanBusinessStep(),
            const ArtisanRegionStep(),
            ArtisanReviewStep(onEditStep: _goTo),
          ],
        ),
      ),
    );
  }
}
