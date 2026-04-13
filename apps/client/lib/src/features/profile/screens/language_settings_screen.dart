import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bg            = Color(0xFFF6F7F8);
const _surfaceWhite  = Color(0xFFFFFFFF);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _success       = Color(0xFF27AE60);
const _successLight  = Color(0xFFE8F8EE);
const _divider       = Color(0xFFE8EAEC);

// ── Provider ───────────────────────────────────────────────────────────────────

enum AppLanguage { english, twi }

extension AppLanguageX on AppLanguage {
  String get nativeName => switch (this) {
        AppLanguage.english => 'English',
        AppLanguage.twi     => 'Twi (Akan)',
      };

  String get localName => switch (this) {
        AppLanguage.english => 'English',
        AppLanguage.twi     => 'Twi',
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

final _languageProvider =
    StateProvider.autoDispose<AppLanguage>((_) => AppLanguage.english);

// ── Screen ─────────────────────────────────────────────────────────────────────
// CLAUDE.md § 5 — Bilingual support: English + Twi at launch.
// Switching applies to all UI strings and push notification content.

class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size     = MediaQuery.sizeOf(context);
    final w        = size.width;
    final h        = size.height;
    final selected = ref.watch(_languageProvider);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Language',
            style: TextStyle(
                color:      _textPrimary,
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
                  color:      _textPrimary,
                  fontSize:   w * 0.040,
                  fontWeight: FontWeight.w700,
                )),
            SizedBox(height: h * 0.008),
            Text('App content and notifications will appear in your chosen language.',
                style: TextStyle(
                    color:    _textSecondary,
                    fontSize: w * 0.033,
                    height:   1.5)),
            SizedBox(height: h * 0.028),
            ...AppLanguage.values.map((lang) => Padding(
                  padding: EdgeInsets.only(bottom: h * 0.014),
                  child: _LanguageTile(
                    language:   lang,
                    isSelected: selected == lang,
                    onTap: () {
                      ref.read(_languageProvider.notifier).state = lang;
                      // TODO: persist to SharedPreferences + update Localizations
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
  final AppLanguage  language;
  final bool         isSelected;
  final VoidCallback onTap;
  final double       w, h;

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
          color:        isSelected ? _gold.withAlpha(12) : _surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? _gold : _divider,
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
                            color:      _textPrimary,
                            fontSize:   w * 0.040,
                            fontWeight: FontWeight.w700,
                          )),
                      if (language == AppLanguage.twi) ...[
                        SizedBox(width: w * 0.016),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: w * 0.018, vertical: 2),
                          decoration: BoxDecoration(
                            color:        const Color(0xFFFFF8EC),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Beta',
                              style: TextStyle(
                                color:      _gold,
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
                          color:    _textSecondary,
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
                color: isSelected ? _gold : Colors.transparent,
                border: Border.all(
                    color: isSelected ? _gold : _divider,
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
        color:        _successLight,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _success.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.translate_rounded, color: _success, size: 20),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Text(
              'More languages — Ga, Ewe, and Hausa — are planned for a '
              'future update. Reach out via Support if you\'d like to help translate.',
              style: TextStyle(
                  color:    _success,
                  fontSize: w * 0.032,
                  height:   1.5),
            ),
          ),
        ],
      ),
    );
  }
}
