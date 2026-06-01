import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart' show ChatBookingType;
import 'package:shared_ui/shared_ui.dart';

import '../providers/chat_controller_provider.dart';

/// Entry-point button that opens the in-app chat for an active booking.
///
/// Consumers (the active-ride sheet, the active-job screen, etc.) build
/// this widget knowing only the `(bookingType, bookingId)` and a peer
/// label. The button:
///
///   1. Auto-opens the channel on the [ChatController] when first mounted
///      (idempotent — same booking re-opens cheaply).
///   2. Subscribes to `unreadCountStream` and renders a small red badge
///      when there are unread other-side messages.
///   3. On tap, pushes `/chat` with the booking + peer info as `extra`.
///
/// Visually it's an `ElevatedButton.icon` styled to match the existing
/// "Chat with X" affordance in the ride tracking sheet so we keep a
/// single look across surfaces.
class ChatEntryButton extends ConsumerStatefulWidget {
  const ChatEntryButton({
    super.key,
    required this.bookingType,
    required this.bookingId,
    required this.label,
    required this.peerName,
    this.peerStatus = '',
    this.background = MyShopColors.darkSlate,
    this.foreground = Colors.white,
  });

  final ChatBookingType bookingType;

  /// Active booking id. The button is a no-op when this is empty —
  /// callers should hide the button entirely in that case.
  final String bookingId;

  /// Button label, e.g. `"Message rider"`.
  final String label;

  /// Header copy for the chat screen.
  final String peerName;
  final String peerStatus;

  final Color background;
  final Color foreground;

  @override
  ConsumerState<ChatEntryButton> createState() => _ChatEntryButtonState();
}

class _ChatEntryButtonState extends ConsumerState<ChatEntryButton> {
  StreamSubscription<int>? _unreadSub;
  int _unread = 0;
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureOpenedAndSubscribed();
  }

  @override
  void didUpdateWidget(covariant ChatEntryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bookingChanged = oldWidget.bookingId != widget.bookingId ||
        oldWidget.bookingType != widget.bookingType;
    if (bookingChanged) {
      _opened = false;
      _ensureOpenedAndSubscribed();
    }
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  void _ensureOpenedAndSubscribed() {
    if (widget.bookingId.isEmpty) return;
    final controller = ref.read(chatControllerProvider).valueOrNull;
    if (controller == null) return;
    if (_opened) return;
    _opened = true;

    scheduleMicrotask(() {
      if (!mounted) return;
      controller.openChannel(widget.bookingType, widget.bookingId);
    });

    _unreadSub?.cancel();
    _unreadSub = controller.unreadCountStream.listen((n) {
      if (!mounted) return;
      setState(() => _unread = n);
    });
  }

  void _onTap() {
    if (widget.bookingId.isEmpty) return;
    context.push(
      '/chat',
      extra: <String, Object?>{
        'bookingType': widget.bookingType,
        'bookingId': widget.bookingId,
        'peerName': widget.peerName,
        'peerStatus': widget.peerStatus,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatControllerProvider);
    _ensureOpenedAndSubscribed();

    return SizedBox(
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ElevatedButton.icon(
            onPressed: widget.bookingId.isEmpty ? null : _onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.background,
              foregroundColor: widget.foreground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.chat_bubble_rounded, size: 18),
            label: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_unread > 0)
            Positioned(
              right: -4,
              top: -4,
              child: _UnreadBadge(count: _unread),
            ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MyShopColors.error,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MyShopColors.surfaceWhite, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Raleway',
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: MyShopColors.textOnPrimary,
          height: 1,
        ),
      ),
    );
  }
}
