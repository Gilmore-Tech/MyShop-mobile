import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../features/profile/providers/verification_provider.dart';
import '../providers/provider_status_provider.dart';

/// Small status dot rendered under the provider's avatar across the app
/// (artisan home header, driver home header, account-settings identity
/// card). Reads [providerStatusProvider] + [profileCompletionProvider] so
/// every surface stays in sync.
///
/// Colour key:
///   • **Green** — provider is online and available for work
///   • **Orange** — on an active ride/job (status `busy`)
///   • **Red** — profile is incomplete or unverified, so the provider
///     can't go online yet
///   • **Grey** — offline (idle but allowed to go online)
///
/// `Busy` wins over `red` so an in-progress job always reads as in-progress.
class ProviderStatusDot extends ConsumerWidget {
  const ProviderStatusDot({
    super.key,
    this.size = 11,
    this.borderColor = MyShopColors.surfaceWhite,
    this.borderWidth = 1.5,
  });

  /// Diameter of the dot.
  final double size;

  /// Ring colour around the dot — typically the surface the dot sits on
  /// (white when it overlays a profile circle on a white app bar).
  final Color borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(providerStatusProvider);
    final completion = ref.watch(profileCompletionProvider);
    final canGoOnline = completion.isComplete;

    final color = _colorFor(status: status, canGoOnline: canGoOnline);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
    );
  }

  static Color _colorFor({
    required DriverStatus status,
    required bool canGoOnline,
  }) {
    // Busy always wins — even if the profile slipped out of "complete"
    // mid-job, we should still show the user as in-progress.
    if (status.isBusy) return MyShopColors.busy;
    if (!canGoOnline) return MyShopColors.error;
    if (status.isOnline) return MyShopColors.online;
    return MyShopColors.offline;
  }
}
