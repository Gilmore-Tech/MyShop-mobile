import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

/// In-app chat with the client during an active ride/job.
///
/// PRD Reference: PRD 4.7 — masked phone numbers, real-time messaging,
/// quick reply chips, attachments, presence indicator.
class ProviderChatScreen extends StatefulWidget {
  const ProviderChatScreen({
    super.key,
    this.clientName = 'Ama Serwaa',
    this.clientStatus = 'Online · Adum, Kumasi',
    this.jobTitle = 'Emergency: Burst Main Pipe in Kitchen',
  });

  final String clientName;
  final String clientStatus;
  final String jobTitle;

  @override
  State<ProviderChatScreen> createState() => _ProviderChatScreenState();
}

class _ProviderChatScreenState extends State<ProviderChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final List<_ChatMessage> _messages;

  @override
  void initState() {
    super.initState();
    _messages = [
      _ChatMessage(
        text: "Hi! I've accepted your job. On my way now.",
        time: '10:42 AM',
        fromMe: true,
        status: _MessageStatus.read,
      ),
      _ChatMessage(
        text: 'Great, thank you! How long until you arrive?',
        time: '10:43 AM',
        fromMe: false,
      ),
      _ChatMessage(
        text:
            'Roughly 15 minutes. Bringing my full plumbing kit and a spare U-bend in case.',
        time: '10:43 AM',
        fromMe: true,
        status: _MessageStatus.read,
      ),
      _ChatMessage(
        text: 'Perfect. The water is everywhere — please come quickly!',
        time: '10:44 AM',
        fromMe: false,
      ),
      _ChatMessage(
        text: "Don't worry, I'll be there shortly.",
        time: '10:45 AM',
        fromMe: true,
        status: _MessageStatus.delivered,
      ),
    ];
  }

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFilePicked(File file) {
    setState(() {
      _messages.add(
        _ChatMessage(
          text: '[Attachment: ${file.path.split('/').last}]',
          time: 'Now',
          fromMe: true,
          status: _MessageStatus.sent,
        ),
      );
    });
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(
        _ChatMessage(
          text: text,
          time: 'Now',
          fromMe: true,
          status: _MessageStatus.sent,
        ),
      );
      _composer.clear();
    });
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
              clientName: widget.clientName,
              clientStatus: widget.clientStatus,
            ),
            _JobBanner(title: widget.jobTitle),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: MyShopSpacing.md,
                ),
                itemCount: _messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const _DaySeparator(label: 'Today');
                  }
                  return _MessageBubble(message: _messages[index - 1]);
                },
              ),
            ),
            _Composer(
              controller: _composer,
              onSend: _send,
              onFilePicked: _handleFilePicked,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.clientName, required this.clientStatus});

  final String clientName;
  final String clientStatus;

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
            onPressed: () => context.pop(),
          ),
          // Avatar with online dot
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
                  clientName,
                  style: MyShopTypography.h1.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  clientStatus,
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_outlined,
                color: MyShopColors.primaryGold),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert,
                color: MyShopColors.textSecondary),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Job context banner
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Day separator
// ─────────────────────────────────────────────────────────────────────────────

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MyShopSpacing.md),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Message bubble
// ─────────────────────────────────────────────────────────────────────────────

enum _MessageStatus { sent, delivered, read }

class _ChatMessage {
  _ChatMessage({
    required this.text,
    required this.time,
    required this.fromMe,
    this.status = _MessageStatus.sent,
  });

  final String text;
  final String time;
  final bool fromMe;
  final _MessageStatus status;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

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
                          message.status == _MessageStatus.read
                              ? Icons.done_all
                              : message.status == _MessageStatus.delivered
                                  ? Icons.done_all
                                  : Icons.check,
                          size: 12,
                          color: message.status == _MessageStatus.read
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

// ─────────────────────────────────────────────────────────────────────────────
// Composer
// ─────────────────────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onFilePicked,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<File> onFilePicked;

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
          _ComposerIconButton(
            icon: Icons.attach_file,
            onTap: () async {
              final file = await MediaPickerHelper.pickAttachment(context);
              if (file != null) onFilePicked(file);
            },
          ),
          const SizedBox(width: MyShopSpacing.sm),
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
                  const SizedBox(width: MyShopSpacing.sm),
                  _ComposerIconButton(
                    icon: Icons.camera_alt_outlined,
                    onTap: () async {
                      final file = await MediaPickerHelper.pickFromCamera();
                      if (file != null) onFilePicked(file);
                    },
                    inline: true,
                  ),
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
