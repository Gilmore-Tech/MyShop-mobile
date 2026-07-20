/// Referral deep-link plumbing.
///
/// Catches `myshop://refer?code=XXXX` links (cold-start + while running),
/// parses out the referral code, and parks it in [pendingReferralCodeProvider]
/// so the sign-up screen can explain that the code was not applied while the
/// programme is paused. The code is one-shot and is cleared on submit so it
/// cannot leak into a later, unrelated registration.
///
/// Accepted shapes (host OR first path segment may be `refer`/`referral`):
///   myshop://refer?code=AMA10
///   myshop://referral?ref=AMA10
///   myshop://refer/AMA10
///   myshop://open?referralCode=AMA10
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds a referral code captured from a deep link for the paused-programme
/// notice. It is never submitted to registration in this release.
///
/// Top-level (not autoDispose) so the value survives across the splash →
/// onboarding → phone → sign-up navigation that happens between the OS
/// delivering the link and the user reaching the registration form.
final pendingReferralCodeProvider = StateProvider<String?>((_) => null);

/// Query keys we accept for the code, in priority order.
const _codeKeys = ['code', 'ref', 'referralcode', 'referral'];

/// Hosts / leading path segments that mark a referral link.
const _referralSegments = {'refer', 'referral', 'invite'};

/// Parse a referral code out of a deep-link [uri], or null if it isn't a
/// referral link / carries no code. Codes are trimmed and upper-cased so a
/// link's casing can't desync from the displayed code; empty/oversized
/// values are rejected.
String? parseReferralCode(Uri uri) {
  if (uri.scheme.toLowerCase() != 'myshop') return null;

  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments;
  final firstSeg = segments.isNotEmpty ? segments.first.toLowerCase() : '';
  final isReferralLink =
      _referralSegments.contains(host) || _referralSegments.contains(firstSeg);
  if (!isReferralLink) return null;

  // Prefer an explicit query param.
  final lowerParams = <String, String>{
    for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value,
  };
  for (final key in _codeKeys) {
    final value = lowerParams[key];
    final cleaned = _clean(value);
    if (cleaned != null) return cleaned;
  }

  // Fallback: trailing path segment, e.g. myshop://refer/AMA10.
  if (_referralSegments.contains(host) && segments.isNotEmpty) {
    return _clean(segments.last);
  }
  if (_referralSegments.contains(firstSeg) && segments.length >= 2) {
    return _clean(segments[1]);
  }
  return null;
}

String? _clean(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim().toUpperCase();
  // Referral codes are short alphanumerics; guard against junk / overlong
  // input so we never prefill the form with garbage from a crafted link.
  if (trimmed.isEmpty || trimmed.length > 32) return null;
  if (!RegExp(r'^[A-Z0-9_-]+$').hasMatch(trimmed)) return null;
  return trimmed;
}

/// Created via [AppLinks] so it can be overridden in tests.
final appLinksProvider = Provider<AppLinks>((_) => AppLinks());

/// Listens for referral deep links — the initial link that cold-started the
/// app and any links delivered while it's already running — and stashes the
/// parsed code in [pendingReferralCodeProvider].
///
/// Watched once at app start (see main.dart). `Provider<void>` keeps the
/// stream subscription alive for the container's lifetime.
final referralDeepLinkBridgeProvider = Provider<void>((ref) {
  AppLinks appLinks;
  try {
    appLinks = ref.read(appLinksProvider);
  } catch (e) {
    // Platform without the plugin (e.g. some test/desktop runs) — skip.
    debugPrint('[ReferralDeepLink] AppLinks unavailable: $e');
    return;
  }

  void capture(Uri? uri, {required String source}) {
    if (uri == null) return;
    final code = parseReferralCode(uri);
    if (code == null) return;
    debugPrint('[ReferralDeepLink] captured "$code" from $source ($uri)');
    ref.read(pendingReferralCodeProvider.notifier).state = code;
  }

  // Cold-start: the link that launched the app (no-op if launched normally).
  unawaited(() async {
    try {
      capture(await appLinks.getInitialLink(), source: 'initial');
    } catch (e) {
      debugPrint('[ReferralDeepLink] getInitialLink failed: $e');
    }
  }());

  // Warm: links delivered while the app is already running.
  final sub = appLinks.uriLinkStream.listen(
    (uri) => capture(uri, source: 'stream'),
    onError: (Object e) => debugPrint('[ReferralDeepLink] stream error: $e'),
  );
  ref.onDispose(sub.cancel);
});
