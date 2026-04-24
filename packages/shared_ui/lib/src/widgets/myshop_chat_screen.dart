import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/myshop_colors.dart';
import '../theme/myshop_spacing.dart';
import '../theme/myshop_typography.dart';
import '../utils/media_picker_helper.dart';

// ── Public models ─────────────────────────────────────────────────────────────

enum ChatMessageStatus { sent, delivered, read }

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
  });

  final String peerName;
  final String peerStatus;
  final List<ChatMessage> messages;
  final ValueChanged<String> onSend;
  final ValueChanged<File>? onFilePicked;
  final VoidCallback? onPhoneCall;
  final VoidCallback? onMoreMenu;
  final Widget? contextBanner;

  @override
  State<MyShopChatScreen> createState() => _MyShopChatScreenState();
}

class _MyShopChatScreenState extends State<MyShopChatScreen> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _composer.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: MyShopSpacing.md,
                ),
                itemCount: widget.messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const _DaySeparator(label: 'Today');
                  }
                  return _MessageBubble(message: widget.messages[index - 1]);
                },
              ),
            ),
            _Composer(
              controller: _composer,
              onSend: _send,
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
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isMine = message.fromMe;

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
                        Icon(
                          message.status == ChatMessageStatus.read
                              ? Icons.done_all
                              : message.status == ChatMessageStatus.delivered
                                  ? Icons.done_all
                                  : Icons.check,
                          size: 12,
                          color: message.status == ChatMessageStatus.read
                              ? MyShopColors.info
                              : MyShopColors.textSecondary,
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
    required this.onSend,
    this.onFilePicked,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<File>? onFilePicked;

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
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
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
