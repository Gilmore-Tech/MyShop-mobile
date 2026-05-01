import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' as models;
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/chat_controller_provider.dart';
import '../../artisan_home/providers/active_job_provider.dart';

/// In-app chat with the client during an active ride or job.
///
/// PRD § 4.7. Thin Consumer over [ChatController]; layout/visuals come
/// from [MyShopChatScreen]. The provider-app variant keeps a job-context
/// banner sourced from [activeJobProvider] when the caller doesn't pass
/// explicit overrides.
class ProviderChatScreen extends ConsumerStatefulWidget {
  const ProviderChatScreen({
    super.key,
    this.bookingType,
    this.bookingId,
    this.clientName,
    this.clientStatus,
    this.jobTitle,
  });

  /// Booking surface this chat is attached to. Phase 5 will route the
  /// active-ride / active-job screens with these set; Phase 4 supports
  /// the wiring shape so passing them through extras compiles.
  final models.ChatBookingType? bookingType;
  final String? bookingId;

  /// Optional overrides. When null, the header derives from the active
  /// job (artisan path) — drivers will pass these explicitly in Phase 5.
  final String? clientName;
  final String? clientStatus;
  final String? jobTitle;

  @override
  ConsumerState<ProviderChatScreen> createState() =>
      _ProviderChatScreenState();
}

class _ProviderChatScreenState extends ConsumerState<ProviderChatScreen> {
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

  ChatMessage _toUi(
    models.ChatMessage m,
    String selfId,
    Set<String> debugSeen,
  ) {
    // Both ids must be non-empty before they can match — otherwise an
    // empty-vs-empty comparison would route every bubble to the right.
    // `tmp_…` ids are always our own messages by construction.
    final isMine = m.id.startsWith('tmp_') ||
        (selfId.isNotEmpty &&
            m.senderId.isNotEmpty &&
            m.senderId == selfId);
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
        if (controller == null) return const _ChatNotSignedIn();
        _attach(controller);

        final activeJob = ref.watch(activeJobProvider).job;
        final peerName =
            widget.clientName ?? activeJob?.clientName ?? 'Client';
        final fallbackStatus =
            activeJob?.addressText != null && activeJob!.addressText!.isNotEmpty
                ? 'On a job · ${activeJob.addressText}'
                : 'In conversation';
        final isClosed = _channel?.isClosed == true;
        final peerStatus = isClosed
            ? 'Chat closed'
            : (widget.clientStatus ?? fallbackStatus);
        final jobTitle = widget.jobTitle ??
            (activeJob?.categoryName != null &&
                    activeJob!.categoryName!.isNotEmpty
                ? '${activeJob.categoryName} request'
                : 'Active job');

        final selfId = controller.selfUserId;
        final debugSeen = <String>{};
        final uiMessages =
            _messages.map((m) => _toUi(m, selfId, debugSeen)).toList();

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
                inner: _JobBanner(title: jobTitle),
              )
            : _JobBanner(title: jobTitle);

        return MyShopChatScreen(
          peerName: peerName,
          peerStatus: peerStatus,
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
          peerTypingLabel: '$peerName is typing…',
          onPhoneCall: () {},
          onMoreMenu: () {},
        );
      },
    );
  }
}

// ── Job context banner (provider-specific) ────────────────────────────────────

class _JobBanner extends StatelessWidget {
  const _JobBanner({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.sm,
      ),
      color: MyShopColors.primaryGoldLight,
      child: Row(
        children: [
          const Icon(
            Icons.work_outline,
            size: 16,
            color: MyShopColors.primaryGold,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
              'Sign in to chat with the client.',
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

  String _short(String s) =>
      s.length <= 8 ? s : '${s.substring(0, 8)}…';

  @override
  Widget build(BuildContext context) {
    final hasMessage = lastMessageId.isNotEmpty;
    final wouldBeMine = selfId.isNotEmpty &&
        lastSenderId.isNotEmpty &&
        selfId == lastSenderId;
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
          child: Text(
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
        ),
        if (inner != null) inner!,
      ],
    );
  }
}
