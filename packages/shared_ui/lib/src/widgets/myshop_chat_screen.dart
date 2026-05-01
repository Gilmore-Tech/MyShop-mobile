import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_spacing.dart';
import '../theme/myshop_typography.dart';
import '../utils/media_picker_helper.dart';

// ── Public models ─────────────────────────────────────────────────────────────

/// Delivery state of an outgoing message — drives the tick rendered next
/// to the timestamp under our own bubbles.
///
///   - [pending]: optimistic, not yet acked by the server (clock icon)
///   - [sent]: server stored it; recipient hasn't read yet (single check)
///   - [delivered]: legacy alias for [sent] — kept for back-compat with
///     callers that still set it; rendered identically.
///   - [read]: recipient read it (double check, gold accent)
///   - [failed]: socket + REST both failed; tap to retry (warning icon)
enum ChatMessageStatus { pending, sent, delivered, read, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.time,
    required this.fromMe,
    this.status = ChatMessageStatus.sent,
  });

  final String id;
  final String text;
  final String time;
  final bool fromMe;
  final ChatMessageStatus status;
}

// ── Shared chat screen ────────────────────────────────────────────────────────

class MyShopChatScreen extends StatefulWidget {
  const MyShopChatScreen({
    super.key,
    required this.peerName,
    required this.peerStatus,
    required this.messages,
    required this.onSend,
    this.onFilePicked,
    this.onPhoneCall,
    this.onMoreMenu,
    this.contextBanner,
    this.onRetry,
    this.isInputLocked = false,
    this.lockedReason,
    this.onMessageVisible,
    this.isPeerTyping = false,
    this.peerTypingLabel,
    this.onTypingChanged,
  });

  final String peerName;
  final String peerStatus;
  final List<ChatMessage> messages;
  final ValueChanged<String> onSend;
  final ValueChanged<File>? onFilePicked;
  final VoidCallback? onPhoneCall;
  final VoidCallback? onMoreMenu;
  final Widget? contextBanner;

  /// Tapped when the user retries a failed bubble — caller fires the
  /// orchestrator's `retry(tempId)`. Disabled (no callback wired) when
  /// null, in which case failed bubbles still render with the warning
  /// icon but don't react to taps.
  final ValueChanged<String>? onRetry;

  /// True when the channel is closed and sends are disallowed. The
  /// composer flips to a read-only banner and the send button is
  /// disabled.
  final bool isInputLocked;

  /// Banner copy shown in place of the composer when [isInputLocked].
  /// Defaults to "This chat is closed because the booking ended."
  final String? lockedReason;

  /// Fired when an incoming (other-side) message becomes visible — the
  /// caller uses this to mark-read. We keep the policy outside the shell
  /// (the orchestrator already dedupes already-read ids).
  final ValueChanged<String>? onMessageVisible;

  /// Renders the "typing…" pill above the composer when true. The
  /// orchestrator's debounce + auto-clear timers are the source of
  /// truth — the shell trusts this flag.
  final bool isPeerTyping;

  /// Optional override for the peer label shown in the typing pill.
  /// Defaults to "Typing…".
  final String? peerTypingLabel;

  /// Caller wires this to the composer's typing signals. The shell calls
  /// `true` on every keystroke that produces non-empty content, and
  /// `false` on send / clear / focus loss. The orchestrator does the
  /// debouncing — shell stays dumb.
  final ValueChanged<bool>? onTypingChanged;

  @override
  State<MyShopChatScreen> createState() => _MyShopChatScreenState();
}

class _MyShopChatScreenState extends State<MyShopChatScreen> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  final _scrollController = ScrollController();

  /// True when the list is scrolled within `_kBottomThreshold` px of the
  /// most recent message. Drives auto-scroll-on-new-message vs. the
  /// "1 new message ↓" pill.
  bool _isNearBottom = true;

  /// Number of unseen incoming messages while the user is scrolled away
  /// from the bottom. Reset to 0 the moment they jump back.
  int _unseenIncoming = 0;

  /// Already-flagged-visible ids — prevents `onMessageVisible` from
  /// firing repeatedly for the same message while it stays on screen.
  final Set<String> _seenVisibleIds = {};

  /// 64 logical pixels — chosen so a single bubble height (~48–56) plus
  /// a small buffer counts as "still at the bottom" through a relayout.
  static const _kBottomThreshold = 64.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _composerFocus.addListener(_onComposerFocusChange);
    // After the very first paint, mark every other-side message visible
    // so a freshly-opened chat doesn't show "(N) new" for messages the
    // user is already looking at.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _flagAllVisibleAsSeen();
    });
  }

  @override
  void didUpdateWidget(covariant MyShopChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final grew = widget.messages.length > oldWidget.messages.length;
    if (!grew) return;
    if (_isNearBottom) {
      // Auto-stick to bottom when the user is already there — common
      // case during an active conversation.
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      _flagAllVisibleAsSeen();
      return;
    }
    // The user is scrolled up — count any new other-side messages so the
    // pill says "(N) new ↓".
    final addedFromOther = widget.messages
        .skip(oldWidget.messages.length)
        .where((m) => !m.fromMe)
        .length;
    if (addedFromOther > 0) {
      setState(() => _unseenIncoming += addedFromOther);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _composerFocus.removeListener(_onComposerFocusChange);
    _composer.dispose();
    _composerFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// On focus loss, tell the orchestrator we're no longer typing. The
  /// orchestrator's idle timer will eventually do this anyway, but
  /// firing here makes the indicator hide immediately on the peer's
  /// side (e.g. user taps elsewhere mid-keystroke).
  void _onComposerFocusChange() {
    if (!_composerFocus.hasFocus) {
      widget.onTypingChanged?.call(false);
    }
  }

  void _onComposerChanged(String value) {
    // Empty field counts as "stopped typing" — the orchestrator emits
    // `false` immediately, which hides the peer's indicator faster than
    // waiting for the idle timer.
    widget.onTypingChanged?.call(value.trim().isNotEmpty);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final nearBottom = _scrollController.offset <=
        _scrollController.position.minScrollExtent + _kBottomThreshold;
    if (nearBottom != _isNearBottom) {
      setState(() {
        _isNearBottom = nearBottom;
        if (nearBottom) {
          _unseenIncoming = 0;
          _flagAllVisibleAsSeen();
        }
      });
    }
  }

  void _flagAllVisibleAsSeen() {
    final cb = widget.onMessageVisible;
    if (cb == null) return;
    for (final m in widget.messages) {
      if (m.fromMe) continue;
      if (!_seenVisibleIds.add(m.id)) continue;
      cb(m.id);
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    // ListView is reverse:true — newest bubble is at offset 0.
    if (animate) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(0);
    }
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    // Hitting send means we're done typing. Fire `false` BEFORE the
    // optimistic-append + scroll so the peer's indicator clears in
    // tandem with our message landing.
    widget.onTypingChanged?.call(false);
    widget.onSend(text);
    _composer.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    // The list renders newest-first via reverse:true so the auto-scroll-on-
    // new-message and keyboard-pushing-content interactions stay simple
    // (offset 0 always = newest). Items are reversed once at build time so
    // the consumer still passes them in chronological order.
    final reversed = widget.messages.reversed.toList(growable: false);
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              peerName: widget.peerName,
              peerStatus: widget.peerStatus,
              onPhoneCall: widget.onPhoneCall,
              onMoreMenu: widget.onMoreMenu,
            ),
            if (widget.contextBanner != null) widget.contextBanner!,
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: MyShopSpacing.md,
                      vertical: MyShopSpacing.md,
                    ),
                    itemCount: reversed.length + 1,
                    itemBuilder: (context, index) {
                      if (index == reversed.length) {
                        return const _DaySeparator(label: 'Today');
                      }
                      return _MessageBubble(
                        message: reversed[index],
                        onRetry: widget.onRetry,
                      );
                    },
                  ),
                  if (_unseenIncoming > 0 && !_isNearBottom)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _NewMessagePill(
                          count: _unseenIncoming,
                          onTap: () {
                            setState(() => _unseenIncoming = 0);
                            _scrollToBottom();
                            _flagAllVisibleAsSeen();
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.isPeerTyping && !widget.isInputLocked)
              _TypingPill(label: widget.peerTypingLabel ?? 'Typing…'),
            if (widget.isInputLocked)
              _LockedBanner(reason: widget.lockedReason)
            else
              _Composer(
                controller: _composer,
                focusNode: _composerFocus,
                onSend: _send,
                onChanged: _onComposerChanged,
                onFilePicked: widget.onFilePicked,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.peerName,
    required this.peerStatus,
    this.onPhoneCall,
    this.onMoreMenu,
  });

  final String peerName;
  final String peerStatus;
  final VoidCallback? onPhoneCall;
  final VoidCallback? onMoreMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.sm,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: MyShopColors.avatarPlaceholder,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person,
                  color: MyShopColors.textSecondary,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: MyShopColors.online,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: MyShopColors.surfaceWhite,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peerName,
                  style: MyShopTypography.h1.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  peerStatus,
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onPhoneCall != null)
            IconButton(
              icon: const Icon(Icons.phone_outlined,
                  color: MyShopColors.primaryGold,),
              onPressed: onPhoneCall,
            ),
          if (onMoreMenu != null)
            IconButton(
              icon: const Icon(Icons.more_vert,
                  color: MyShopColors.textSecondary,),
              onPressed: onMoreMenu,
            ),
        ],
      ),
    );
  }
}

// ── Day separator ─────────────────────────────────────────────────────────────

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MyShopSpacing.md),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: MyShopTypography.caption.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.onRetry});

  final ChatMessage message;
  final ValueChanged<String>? onRetry;

  @override
  Widget build(BuildContext context) {
    final isMine = message.fromMe;
    final isFailed = message.status == ChatMessageStatus.failed;

    return Padding(
      padding: const EdgeInsets.only(bottom: MyShopSpacing.sm),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.74,
            ),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMine
                        ? MyShopColors.primaryGold
                        : MyShopColors.surfaceWhite,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMine ? 16 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 16),
                    ),
                    border: isMine
                        ? null
                        : Border.all(color: MyShopColors.divider),
                  ),
                  child: Text(
                    message.text,
                    style: MyShopTypography.body1.copyWith(
                      color: isMine
                          ? MyShopColors.textOnPrimary
                          : MyShopColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.time,
                        style: MyShopTypography.caption.copyWith(
                          color: MyShopColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 4),
                        _StatusTick(status: message.status),
                      ],
                      if (isMine && isFailed && onRetry != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => onRetry!(message.id),
                          behavior: HitTestBehavior.opaque,
                          child: Text(
                            'Retry',
                            style: MyShopTypography.caption.copyWith(
                              color: MyShopColors.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Composer ───────────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.onFilePicked,
    this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final ValueChanged<File>? onFilePicked;

  /// Fired on every keystroke. The state class hooks this to emit the
  /// typing signal upstream (orchestrator does the debouncing).
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MediaQuery.of(context).viewInsets.bottom + MyShopSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onFilePicked != null)
            _ComposerIconButton(
              icon: Icons.attach_file,
              onTap: () async {
                final file = await MediaPickerHelper.pickAttachment(context);
                if (file != null) onFilePicked!(file);
              },
            ),
          if (onFilePicked != null) const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, maxHeight: 120),
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: MyShopColors.offWhite,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: MyShopColors.divider),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      onChanged: onChanged,
                      style: MyShopTypography.body1,
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        hintStyle: MyShopTypography.body1.copyWith(
                          color: MyShopColors.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (onFilePicked != null) ...[
                    const SizedBox(width: MyShopSpacing.sm),
                    _ComposerIconButton(
                      icon: Icons.camera_alt_outlined,
                      onTap: () async {
                        final file = await MediaPickerHelper.pickFromCamera();
                        if (file != null) onFilePicked!(file);
                      },
                      inline: true,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: MyShopColors.primaryGold,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send,
                size: 20,
                color: MyShopColors.textOnPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.icon,
    required this.onTap,
    this.inline = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: inline ? 28 : 36,
        height: inline ? 28 : 36,
        decoration: BoxDecoration(
          color: inline ? Colors.transparent : MyShopColors.offWhite,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: inline ? 18 : 20,
          color: MyShopColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Status tick ────────────────────────────────────────────────────────────────

/// Tiny icon under our own bubbles indicating delivery progress.
class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status});

  final ChatMessageStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ChatMessageStatus.pending:
        return const Icon(
          Icons.schedule,
          size: 12,
          color: MyShopColors.textSecondary,
        );
      case ChatMessageStatus.failed:
        return const Icon(
          Icons.error_outline,
          size: 12,
          color: MyShopColors.error,
        );
      case ChatMessageStatus.read:
        return const Icon(
          Icons.done_all,
          size: 12,
          color: MyShopColors.info,
        );
      case ChatMessageStatus.delivered:
      case ChatMessageStatus.sent:
        return const Icon(
          Icons.check,
          size: 12,
          color: MyShopColors.textSecondary,
        );
    }
  }
}

// ── "(N) new ↓" pill ───────────────────────────────────────────────────────────

class _NewMessagePill extends StatelessWidget {
  const _NewMessagePill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 new message' : '$count new messages';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: MyShopColors.primaryGold,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: MyShopColors.primaryGold.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: MyShopColors.textOnPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_downward_rounded,
                size: 14,
                color: MyShopColors.textOnPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Locked banner (shown in place of the composer) ────────────────────────────

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MediaQuery.of(context).viewInsets.bottom + MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 18,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason ?? 'This chat is closed because the booking ended.',
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Typing pill ────────────────────────────────────────────────────────────────

/// Slim "typing…" affordance above the composer. Three pulsing dots so
/// the user notices it without it dominating the screen.
class _TypingPill extends StatefulWidget {
  const _TypingPill({required this.label});

  final String label;

  @override
  State<_TypingPill> createState() => _TypingPillState();
}

class _TypingPillState extends State<_TypingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        4,
        MyShopSpacing.md,
        6,
      ),
      color: MyShopColors.offWhite,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AnimatedDots(controller: _ctrl),
          const SizedBox(width: 8),
          Text(
            widget.label,
            style: MyShopTypography.caption.copyWith(
              color: MyShopColors.textSecondary,
              fontStyle: FontStyle.italic,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedDots extends StatelessWidget {
  const _AnimatedDots({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Three dots, each phase-shifted by a third of the cycle.
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (controller.value + i / 3) % 1.0;
            // Triangle wave 0..1..0 over the cycle so each dot pulses
            // in and out smoothly.
            final pulse = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            final opacity = 0.3 + 0.7 * pulse;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: MyShopColors.textSecondary
                      .withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
