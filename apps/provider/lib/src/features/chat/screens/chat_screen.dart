import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../artisan_home/providers/active_job_provider.dart';

/// In-app chat with the client during an active ride/job.
///
/// PRD Reference: PRD 4.7 — masked phone numbers, real-time messaging,
/// quick reply chips, attachments, presence indicator.
class ProviderChatScreen extends ConsumerStatefulWidget {
  const ProviderChatScreen({
    super.key,
    this.clientName,
    this.clientStatus,
    this.jobTitle,
  });

  /// Optional overrides — when null the header is sourced from the active
  /// job. Callers that don't have a job context (e.g. the messages list)
  /// can still pass values explicitly.
  final String? clientName;
  final String? clientStatus;
  final String? jobTitle;

  @override
  ConsumerState<ProviderChatScreen> createState() =>
      _ProviderChatScreenState();
}

class _ProviderChatScreenState extends ConsumerState<ProviderChatScreen> {
  final List<ChatMessage> _messages = <ChatMessage>[];

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
    final activeJob = ref.watch(activeJobProvider).job;
    final peerName =
        widget.clientName ?? activeJob?.clientName ?? 'Client';
    final peerStatus = widget.clientStatus ??
        (activeJob?.addressText != null && activeJob!.addressText!.isNotEmpty
            ? 'On a job · ${activeJob.addressText}'
            : 'In conversation');
    final jobTitle = widget.jobTitle ??
        (activeJob?.categoryName != null &&
                activeJob!.categoryName!.isNotEmpty
            ? '${activeJob.categoryName} request'
            : 'Active job');

    return MyShopChatScreen(
      peerName: peerName,
      peerStatus: peerStatus,
      messages: _messages,
      onSend: _handleSend,
      onFilePicked: _handleFilePicked,
      onPhoneCall: () {},
      onMoreMenu: () {},
      contextBanner: _JobBanner(title: jobTitle),
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
