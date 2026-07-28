import 'package:flutter/material.dart';

enum MyShopServiceNoticeKind { offline, timeout, unavailable }

/// Keeps the current route mounted while presenting an outage notice.
///
/// Active-work screens get a compact notice at the top, stacked after any
/// existing location/provider notices. Other screens get a modal barrier.
/// Because the compact notice never occupies the bottom edge, ride/job
/// lifecycle controls remain visible and hit-testable.
class MyShopServiceNoticeOverlay extends StatelessWidget {
  const MyShopServiceNoticeOverlay({
    super.key,
    required this.child,
    required this.kind,
    required this.hasActiveWork,
    required this.onRetry,
    this.topNotices = const [],
  });

  final Widget child;
  final MyShopServiceNoticeKind? kind;
  final bool hasActiveWork;
  final VoidCallback onRetry;
  final List<Widget> topNotices;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        KeyedSubtree(
          key: const Key('service-notice-current-route'),
          child: child,
        ),
        if (topNotices.isNotEmpty || (kind != null && hasActiveWork))
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...topNotices,
                if (kind != null && hasActiveWork)
                  MyShopServiceNoticeBanner(kind: kind!, onRetry: onRetry),
              ],
            ),
          ),
        if (kind != null && !hasActiveWork)
          Positioned.fill(
            child: MyShopServiceNoticeBanner(
              kind: kind!,
              blocking: true,
              onRetry: onRetry,
            ),
          ),
      ],
    );
  }
}

/// Non-blocking, retryable service notice rendered above the current route.
///
/// Unlike navigation to an error page, this preserves the mounted page,
/// navigator stack and in-progress form state. The compact card also leaves
/// active ride/job controls usable while connectivity recovers.
class MyShopServiceNoticeBanner extends StatelessWidget {
  const MyShopServiceNoticeBanner({
    super.key,
    required this.kind,
    required this.onRetry,
    this.blocking = false,
  });

  final MyShopServiceNoticeKind kind;
  final VoidCallback onRetry;
  final bool blocking;

  @override
  Widget build(BuildContext context) {
    if (blocking) {
      return Stack(
        children: [
          const ModalBarrier(
            key: Key('service-connectivity-modal-barrier'),
            dismissible: false,
            color: Colors.black45,
          ),
          SafeArea(
            minimum: const EdgeInsets.all(20),
            child: Center(child: _buildCard(context)),
          ),
        ],
      );
    }

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Align(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        heightFactor: 1,
        child: _buildCard(context),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const Key('service-connectivity-notice'),
      color: colors.inverseSurface,
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                switch (kind) {
                  MyShopServiceNoticeKind.offline => Icons.wifi_off_rounded,
                  MyShopServiceNoticeKind.timeout => Icons.schedule_rounded,
                  MyShopServiceNoticeKind.unavailable =>
                    Icons.cloud_off_rounded,
                },
                color: colors.onInverseSurface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (kind) {
                        MyShopServiceNoticeKind.offline =>
                          'No internet connection',
                        MyShopServiceNoticeKind.timeout =>
                          'Connection timed out',
                        MyShopServiceNoticeKind.unavailable =>
                          'Service temporarily unavailable',
                      },
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.onInverseSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kind == MyShopServiceNoticeKind.offline
                          ? 'Your current screen is unchanged. Reconnect, then retry.'
                          : 'Your current screen is unchanged. Please retry in a moment.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onInverseSurface,
                          ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('service-connectivity-retry'),
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: colors.inversePrimary,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
