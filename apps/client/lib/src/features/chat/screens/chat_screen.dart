import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' as models;
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/chat_controller_provider.dart';

/// PRD § 4.7 — In-app chat during an active ride or job.
///
/// Thin Consumer over [ChatController]. Reads the per-app
/// `chatControllerProvider`, opens a channel on mount, listens to the
/// three controller streams, and feeds [MyShopChatScreen] a UI-friendly
/// projection. Deliberately mute about layout — the heavy lifting (read
/// ticks, locked banner, retry tap, "(N) new ↓" pill) lives in the shell.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    this.bookingType,
    this.bookingId,
    this.peerName = 'Chat',
    this.peerStatus = '',
    this.contextBanner,
  });

  /// Booking surface this chat is attached to. Phase 5 will route the
  /// active-ride / active-job screens with these set; Phase 4 just
  /// supports the wiring shape so passing them through extras compiles.
  final models.ChatBookingType? bookingType;
  final String? bookingId;

  /// Header copy. Phase 5 sources these from the active-booking provider
  /// (e.g. driver name + ride status).
  final String peerName;
  final String peerStatus;

  /// Optional banner under the header (e.g. "Phone numbers are masked"
  /// notice or the active-job context badge in the provider app).
  final Widget? contextBanner;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  ChatController? _controller;
  StreamSubscription<List<models.ChatMessage>>? _messagesSub;
  StreamSubscription<models.ChatChannel?>? _channelSub;
  StreamSubscription<Set<String>>? _failedSub;
  StreamSubscription<bool>? _peerTypingSub;

  List<models.ChatMessage> _messages = const [];
  models.ChatChannel? _channel;
  Set<String> _failedIds = const {};
  bool _peerTyping = false;

  @override
  void dispose() {
    // Cancel our local stream subs but keep the channel itself open so
    // background message arrivals (and the entry-point unread badge)
    // survive the user navigating away from /chat. The orchestrator
    // closes the channel automatically on `chat:channel:closed`, on
    // booking change (next openChannel call), or on logout (dispose).
    _detach();
    super.dispose();
  }

  void _attach(ChatController controller) {
    if (identical(_controller, controller)) return;
    _detach();
    _controller = controller;

    _messages = controller.currentMessages;
    _channel = controller.currentChannel;

    _messagesSub = controller.messagesStream.listen((m) {
      if (!mounted) return;
      setState(() => _messages = m);
    });
    _channelSub = controller.channelStream.listen((c) {
      if (!mounted) return;
      setState(() => _channel = c);
    });
    _failedSub = controller.failedIdsStream.listen((ids) {
      if (!mounted) return;
      setState(() => _failedIds = ids);
    });
    _peerTypingSub = controller.peerTypingStream.listen((typing) {
      if (!mounted) return;
      setState(() => _peerTyping = typing);
    });

    final type = widget.bookingType;
    final id = widget.bookingId;
    if (type != null && id != null) {
      // Defer to the next microtask so we don't kick off network IO
      // synchronously inside build (Riverpod will rebuild us right after).
      scheduleMicrotask(() {
        if (!mounted) return;
        controller.openChannel(type, id);
      });
    }
  }

  void _detach() {
    _messagesSub?.cancel();
    _channelSub?.cancel();
    _failedSub?.cancel();
    _peerTypingSub?.cancel();
    _messagesSub = null;
    _channelSub = null;
    _failedSub = null;
    _peerTypingSub = null;
    _controller = null;
  }

  // ── Mappers ──────────────────────────────────────────────────────────────

  /// Maps the typed orchestrator message to the shell's UI model. The
  /// status enum collapses three pieces of state — id-shape, failed-set
  /// membership, and `readAt` — into one renderable value.
  /// Per-render set of ids we've already logged a routing decision for.
  /// Cleared each build (function-local set) — the goal is one log per
  /// id per visible render, not one per rebuild.
  ChatMessage _toUi(
    models.ChatMessage m,
    String selfId,
    Set<String> debugSeen,
  ) {
    // Both ids must be non-empty before they can match — otherwise an
    // empty-vs-empty comparison would route every bubble to the right.
    // Also treat `tmp_…` ids as "mine" by construction; the orchestrator
    // assigns those locally on send before the server-id swap.
    final isMine = m.id.startsWith('tmp_') ||
        (selfId.isNotEmpty && m.senderId.isNotEmpty && m.senderId == selfId);
    if (kDebugMode && debugSeen.add(m.id)) {
      debugPrint(
        '[CHAT-UI] id=${m.id} senderId="${m.senderId}" '
        'selfId="$selfId" → isMine=$isMine',
      );
    }
    final ChatMessageStatus status;
    if (!isMine) {
      status = m.isRead ? ChatMessageStatus.read : ChatMessageStatus.sent;
    } else if (_failedIds.contains(m.id)) {
      status = ChatMessageStatus.failed;
    } else if (m.id.startsWith('tmp_')) {
      status = ChatMessageStatus.pending;
    } else if (m.isRead) {
      status = ChatMessageStatus.read;
    } else {
      status = ChatMessageStatus.sent;
    }
    return ChatMessage(
      id: m.id,
      text: m.message,
      time: _formatTime(m.createdAt),
      fromMe: isMine,
      status: status,
    );
  }

  static String _formatTime(DateTime at) {
    final local = at.toLocal();
    final hour24 = local.hour;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour24 < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final controllerAsync = ref.watch(chatControllerProvider);

    return controllerAsync.when(
      loading: () => const _ChatLoading(),
      error: (_, __) => const _ChatError(),
      data: (controller) {
        if (controller == null) {
          return const _ChatNotSignedIn();
        }
        _attach(controller);

        final selfId = controller.selfUserId;
        final debugSeen = <String>{};
        final uiMessages =
            _messages.map((m) => _toUi(m, selfId, debugSeen)).toList();
        final isClosed = _channel?.isClosed == true;

        // Debug-only routing diagnostic — when bubbles render on the
        // wrong side we want the actual values visible in the running
        // simulator, not just stuck in the log buffer. Strips out of
        // release builds via kDebugMode.
        final lastIncoming = _messages.lastWhere(
          (m) => !m.id.startsWith('tmp_'),
          orElse: () => _messages.isNotEmpty
              ? _messages.last
              : models.ChatMessage(
                  id: '',
                  senderId: '',
                  message: '',
                  createdAt: DateTime.now().toUtc(),
                ),
        );
        final composedBanner = kDebugMode
            ? _ChatDebugBanner(
                selfId: selfId,
                lastSenderId: lastIncoming.senderId,
                lastMessageId: lastIncoming.id,
                inner: widget.contextBanner,
              )
            : widget.contextBanner;

        return MyShopChatScreen(
          peerName: widget.peerName,
          peerStatus: isClosed ? 'Chat closed' : widget.peerStatus,
          messages: uiMessages,
          contextBanner: composedBanner,
          isInputLocked: isClosed,
          lockedReason: isClosed
              ? 'This chat is closed because the booking ended.'
              : null,
          onSend: (text) => controller.send(text),
          onRetry: (tempId) => controller.retry(tempId),
          onMessageVisible: (id) => controller.markRead(id),
          onTypingChanged: controller.notifyTyping,
          isPeerTyping: _peerTyping,
          peerTypingLabel: '${widget.peerName} is typing…',
          onPhoneCall: () {},
        );
      },
    );
  }
}

class _ChatLoading extends StatelessWidget {
  const _ChatLoading();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: MyShopColors.primaryGold),
        ),
      );
}

class _ChatError extends StatelessWidget {
  const _ChatError();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(MyShopSpacing.lg),
            child: Text(
              "Couldn't load chat. Please try again.",
              textAlign: TextAlign.center,
              style: MyShopTypography.body1
                  .copyWith(color: MyShopColors.textSecondary),
            ),
          ),
        ),
      );
}

class _ChatNotSignedIn extends StatelessWidget {
  const _ChatNotSignedIn();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(MyShopSpacing.lg),
            child: Text(
              'Sign in to chat with your driver or artisan.',
              textAlign: TextAlign.center,
              style: MyShopTypography.body1
                  .copyWith(color: MyShopColors.textSecondary),
            ),
          ),
        ),
      );
}

/// Debug-only diagnostic strip rendered above the existing context
/// banner. Surfaces the values the bubble's `isMine` check relies on so
/// a routing-bug investigation doesn't require digging through the
/// debug console. Stripped out of release builds via `kDebugMode`.
class _ChatDebugBanner extends StatelessWidget {
  const _ChatDebugBanner({
    required this.selfId,
    required this.lastSenderId,
    required this.lastMessageId,
    this.inner,
  });

  final String selfId;
  final String lastSenderId;
  final String lastMessageId;
  final Widget? inner;

  String _short(String s) => s.length <= 8 ? s : '${s.substring(0, 8)}…';

  @override
  Widget build(BuildContext context) {
    final hasMessage = lastMessageId.isNotEmpty;
    final wouldBeMine =
        selfId.isNotEmpty && lastSenderId.isNotEmpty && selfId == lastSenderId;
    final summary = !hasMessage
        ? 'no messages yet'
        : 'last → ${wouldBeMine ? "MINE (right)" : "PEER (left)"}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          color: MyShopColors.warning.withValues(alpha: 0.18),
          padding: const EdgeInsets.symmetric(
            horizontal: MyShopSpacing.md,
            vertical: 6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DEBUG · self=${_short(selfId)} | '
                'lastSender=${_short(lastSenderId)} · $summary',
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        if (inner != null) inner!,
      ],
    );
  }
}
