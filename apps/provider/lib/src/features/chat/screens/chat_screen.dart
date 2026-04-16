import 'dart:io';

import 'package:flutter/material.dart';
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
  late final List<ChatMessage> _messages;

  @override
  void initState() {
    super.initState();
    _messages = [
      const ChatMessage(
        id: '1',
        text: "Hi! I've accepted your job. On my way now.",
        time: '10:42 AM',
        fromMe: true,
        status: ChatMessageStatus.read,
      ),
      const ChatMessage(
        id: '2',
        text: 'Great, thank you! How long until you arrive?',
        time: '10:43 AM',
        fromMe: false,
      ),
      const ChatMessage(
        id: '3',
        text:
            'Roughly 15 minutes. Bringing my full plumbing kit and a spare U-bend in case.',
        time: '10:43 AM',
        fromMe: true,
        status: ChatMessageStatus.read,
      ),
      const ChatMessage(
        id: '4',
        text: 'Perfect. The water is everywhere — please come quickly!',
        time: '10:44 AM',
        fromMe: false,
      ),
      const ChatMessage(
        id: '5',
        text: "Don't worry, I'll be there shortly.",
        time: '10:45 AM',
        fromMe: true,
        status: ChatMessageStatus.delivered,
      ),
    ];
  }

  void _handleSend(String text) {
    setState(() {
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        time: 'Now',
        fromMe: true,
      ));
    });
  }

  void _handleFilePicked(File file) {
    setState(() {
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '[Attachment: ${file.path.split('/').last}]',
        time: 'Now',
        fromMe: true,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return MyShopChatScreen(
      peerName: widget.clientName,
      peerStatus: widget.clientStatus,
      messages: _messages,
      onSend: _handleSend,
      onFilePicked: _handleFilePicked,
      onPhoneCall: () {},
      onMoreMenu: () {},
      contextBanner: _JobBanner(title: widget.jobTitle),
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
