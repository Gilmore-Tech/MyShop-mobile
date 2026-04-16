import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

// ── Provider ──────────────────────────────────────────────────────────────────
// PRD § 4.7 — In-app chat during active ride or job.
// EDD: WS /v1/chat/:bookingId  — events: message, typing, read

class _ChatNotifier extends StateNotifier<List<ChatMessage>> {
  _ChatNotifier()
      : super(const [
          ChatMessage(
            id: '1',
            text: "Hello! I'm on my way.",
            fromMe: false,
            time: '09:14 AM',
          ),
          ChatMessage(
            id: '2',
            text: "Great, I'm at the main gate.",
            fromMe: true,
            time: '09:15 AM',
            status: ChatMessageStatus.read,
          ),
          ChatMessage(
            id: '3',
            text: 'Okay, about 5 minutes.',
            fromMe: false,
            time: '09:15 AM',
          ),
        ]);

  void send(String text) {
    if (text.trim().isEmpty) return;
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final m = now.minute.toString().padLeft(2, '0');
    final period = now.period == DayPeriod.am ? 'AM' : 'PM';
    state = [
      ...state,
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text.trim(),
        fromMe: true,
        time: '$h:$m $period',
      ),
    ];
    // TODO: WS send { type: "message", text }
  }

  void addAttachment(File file) {
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final m = now.minute.toString().padLeft(2, '0');
    final period = now.period == DayPeriod.am ? 'AM' : 'PM';
    state = [
      ...state,
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '[Attachment: ${file.path.split('/').last}]',
        fromMe: true,
        time: '$h:$m $period',
      ),
    ];
  }
}

final _chatProvider = StateNotifierProvider.autoDispose<_ChatNotifier,
    List<ChatMessage>>((_) => _ChatNotifier());

// ── Screen ────────────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(_chatProvider);

    return MyShopChatScreen(
      peerName: 'Kwame Asante',
      peerStatus: 'Online',
      messages: messages,
      onSend: (text) => ref.read(_chatProvider.notifier).send(text),
      onFilePicked: (file) =>
          ref.read(_chatProvider.notifier).addAttachment(file),
      onPhoneCall: () {},
      contextBanner: Container(
        color: MyShopColors.surfaceGrey,
        padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md,
          vertical: MyShopSpacing.sm,
        ),
        child: const Row(
          children: [
            Icon(Icons.security_rounded,
                color: MyShopColors.textSecondary, size: 14),
            SizedBox(width: MyShopSpacing.sm),
            Expanded(
              child: Text(
                'Phone numbers are masked. Use this chat to communicate.',
                style: MyShopTypography.body2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
