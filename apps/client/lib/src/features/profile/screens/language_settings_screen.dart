import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_preferences_provider.dart';

// ── Display enum ──────────────────────────────────────────────────────────────
// Ties UI rendering (flag, description) to the language codes the rest of
// the app already uses (`en_US`, `tw` — see [kSupportedLanguages] in
// app_preferences_provider.dart). Selection state and persistence live in
// `appPreferencesProvider`, which calls PUT /users/me with the backend
// languagePref ('en' / 'tw').

enum AppLanguage { english, twi }

extension AppLanguageX on AppLanguage {
  String get code => switch (this) {
        AppLanguage.english => 'en_US',
        AppLanguage.twi     => 'tw',
      };

  static AppLanguage fromCode(String code) =>
      code == 'tw' ? AppLanguage.twi : AppLanguage.english;

  String get nativeName => switch (this) {
        AppLanguage.english => 'English',
        AppLanguage.twi     => 'Twi (Akan)',
      };

  String get flag => switch (this) {
        AppLanguage.english => '🇬🇧',
        AppLanguage.twi     => '🇬🇭',
      };

  String get description => switch (this) {
        AppLanguage.english =>
          'Standard language for all menus and notifications.',
        AppLanguage.twi =>
          'Akan dialect spoken across Ashanti Region. Full parity with English at launch.',
      };
}

// ── Screen ─────────────────────────────────────────────────────────────────────
// CLAUDE.md § 5 — Bilingual support: English + Twi at launch.
// Selection persists via `appPreferencesProvider.savePreferences()` which
// PUTs `languagePref` to /users/me.

class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size  = MediaQuery.sizeOf(context);
    final w     = size.width;
    final h     = size.height;
    final prefs = ref.watch(appPreferencesProvider);
    final selected = AppLanguageX.fromCode(prefs.languageCode);

    // Surface backend errors as a snackbar — saves are fire-and-forget on
    // tap, so the user otherwise wouldn't know if the PUT failed.
    ref.listen<AppPreferencesState>(appPreferencesProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        MyShopToast.show(
          context,
          message: next.errorMessage!,
          type: ToastType.error,
        );
      }
      if (next.isSaved && prev?.isSaved == false) {
        MyShopToast.show(context, message: 'Language updated');
      }
    });

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Language',
            style: TextStyle(
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: Padding(
        padding: EdgeInsets.all(w * 0.05),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose your language',
                style: TextStyle(
                  color:      MyShopColors.textPrimary,
                  fontSize:   w * 0.040,
                  fontWeight: FontWeight.w700,
                )),
            SizedBox(height: h * 0.008),
            Text('App content and notifications will appear in your chosen language.',
                style: TextStyle(
                    color:    MyShopColors.textSecondary,
                    fontSize: w * 0.033,
                    height:   1.5)),
            SizedBox(height: h * 0.028),
            ...AppLanguage.values.map((lang) => Padding(
                  padding: EdgeInsets.only(bottom: h * 0.014),
                  child: _LanguageTile(
                    language:   lang,
                    isSelected: selected == lang,
                    onTap: prefs.isSaving || selected == lang
                        ? null
                        : () {
                            // Optimistic UI: switch the selection immediately,
                            // then kick off the PUT in the background. The
                            // ref.listen above surfaces success/error toasts.
                            final notifier =
                                ref.read(appPreferencesProvider.notifier);
                            notifier.setLanguage(lang.code);
                            notifier.savePreferences();
                          },
                    w: w, h: h,
                  ),
                )),
            SizedBox(height: h * 0.028),
            _ComingSoonNote(w: w),
          ],
        ),
      ),
    );
  }
}

// ── Language tile ──────────────────────────────────────────────────────────────

class _LanguageTile extends StatelessWidget {
  final AppLanguage   language;
  final bool          isSelected;
  final VoidCallback? onTap;
  final double        w, h;

  const _LanguageTile({
    required this.language,
    required this.isSelected,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(w * 0.04),
        decoration: BoxDecoration(
          color:        isSelected ? MyShopColors.primaryGold.withAlpha(12) : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? MyShopColors.primaryGold : MyShopColors.divider,
              width: isSelected ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color:      Colors.black.withAlpha(6),
                blurRadius: 6,
                offset:     const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Text(language.flag,
                style: TextStyle(fontSize: w * 0.056)),
            SizedBox(width: w * 0.036),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(language.nativeName,
                          style: TextStyle(
                            color:      MyShopColors.textPrimary,
                            fontSize:   w * 0.040,
                            fontWeight: FontWeight.w700,
                          )),
                      if (language == AppLanguage.twi) ...[
                        SizedBox(width: w * 0.016),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: w * 0.018, vertical: 2),
                          decoration: BoxDecoration(
                            color:        MyShopColors.primaryGoldLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Beta',
                              style: TextStyle(
                                color:      MyShopColors.primaryGold,
                                fontSize:   w * 0.024,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(language.description,
                      style: TextStyle(
                          color:    MyShopColors.textSecondary,
                          fontSize: w * 0.030,
                          height:   1.4)),
                ],
              ),
            ),
            SizedBox(width: w * 0.020),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width:  w * 0.058,
              height: w * 0.058,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? MyShopColors.primaryGold : Colors.transparent,
                border: Border.all(
                    color: isSelected ? MyShopColors.primaryGold : MyShopColors.divider,
                    width: 1.5),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Coming soon note ───────────────────────────────────────────────────────────

class _ComingSoonNote extends StatelessWidget {
  final double w;
  const _ComingSoonNote({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        MyShopColors.successLight,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: MyShopColors.success.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.translate_rounded, color: MyShopColors.success, size: 20),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Text(
              'More languages — Ga, Ewe, and Hausa — are planned for a '
              'future update. Reach out via Support if you\'d like to help translate.',
              style: TextStyle(
                  color:    MyShopColors.success,
                  fontSize: w * 0.032,
                  height:   1.5),
            ),
          ),
        ],
      ),
    );
  }
}
