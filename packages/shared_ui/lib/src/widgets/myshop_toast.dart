import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_radius.dart';
import '../theme/myshop_spacing.dart';
import '../theme/myshop_typography.dart';

/// Toast notification type — determines color and icon.
enum ToastType { success, error, warning, info }

/// Overlay-based toast that slides in from the top and auto-dismisses.
///
/// Usage:
/// ```dart
/// MyShopToast.show(context, message: 'Profile updated');
/// MyShopToast.show(context, message: 'Failed to save', type: ToastType.error);
/// ```
class MyShopToast {
  static OverlayEntry? _current;
  static Timer? _timer;

  /// Show a toast notification at the top of the screen.
  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.success,
    Duration duration = const Duration(seconds: 3),
  }) {
    dismiss();

    final overlay = Overlay.of(context);
    final controller = _ToastAnimationController();

    final entry = OverlayEntry(
      builder: (_) => _ToastOverlay(
        message: message,
        type: type,
        controller: controller,
      ),
    );

    _current = entry;
    overlay.insert(entry);

    // Trigger entrance animation after one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.show();
    });

    _timer = Timer(duration, () {
      controller.hide().then((_) {
        if (_current == entry) {
          entry.remove();
          _current = null;
        }
      });
    });
  }

  /// Dismiss the current toast immediately.
  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }
}

// ── Animation controller wrapper ──────────────────────────────────────────────

class _ToastAnimationController {
  _ToastOverlayState? _state;

  void _attach(_ToastOverlayState state) => _state = state;

  void show() => _state?._animateIn();

  Future<void> hide() async => _state?._animateOut();
}

// ── Toast overlay widget ──────────────────────────────────────────────────────

class _ToastOverlay extends StatefulWidget {
  const _ToastOverlay({
    required this.message,
    required this.type,
    required this.controller,
  });

  final String message;
  final ToastType type;
  final _ToastAnimationController controller;

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animation, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _animateIn() => _animation.forward();

  Future<void> _animateOut() async {
    if (mounted) await _animation.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final (bgColor, accentColor, icon) = _toastStyle(widget.type);

    return Positioned(
      top: topPad + MyShopSpacing.sm,
      left: MyShopSpacing.md,
      right: MyShopSpacing.md,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: MyShopToast.dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(MyShopRadius.card),
                  border: Border(
                    left: BorderSide(color: accentColor, width: 4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(icon, color: accentColor, size: 22),
                    const SizedBox(width: MyShopSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: MyShopTypography.body1.copyWith(
                          color: MyShopColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: MyShopSpacing.sm),
                    GestureDetector(
                      onTap: MyShopToast.dismiss,
                      child: const Icon(
                        Icons.close,
                        color: MyShopColors.textSecondary,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static (Color bg, Color accent, IconData icon) _toastStyle(ToastType type) {
    return switch (type) {
      ToastType.success => (
          MyShopColors.successLight,
          MyShopColors.success,
          Icons.check_circle_outline,
        ),
      ToastType.error => (
          MyShopColors.errorLight,
          MyShopColors.error,
          Icons.error_outline_rounded,
        ),
      ToastType.warning => (
          MyShopColors.warningLight,
          MyShopColors.warning,
          Icons.warning_amber_rounded,
        ),
      ToastType.info => (
          MyShopColors.infoLight,
          MyShopColors.info,
          Icons.info_outline_rounded,
        ),
    };
  }
}
