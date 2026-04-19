import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:api_client/api_client.dart';

import '../../../core/di/providers.dart';

// ── Provider ──────────────────────────────────────────────────────────────────
// PRD § 4.7 — In-app chat during active ride or job.
// EDD: WS /v1/chat/:bookingId  — events: message, typing, read

// Mock messages used as fallback when API is unavailable.
const _mockMessages = [
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
];

class _ChatNotifier extends StateNotifier<List<ChatMessage>> {
  _ChatNotifier(this._chatService, {this.bookingType, this.bookingId})
      : super(_mockMessages) {
    _loadFromApi();
  }

  final ChatService _chatService;
  final String? bookingType;
  final String? bookingId;

  Future<void> _loadFromApi() async {
    if (bookingType == null || bookingId == null) return;
    try {
      final items = await _chatService.getMessages(bookingType!, bookingId!);
      if (items.isNotEmpty) {
        state = items.map((json) {
          final m = json as Map<String, dynamic>;
          return ChatMessage(
            id:     (m['id'] ?? '').toString(),
            text:   m['content'] as String? ?? m['text'] as String? ?? '',
            fromMe: m['fromMe'] as bool? ?? m['isMine'] as bool? ?? false,
            time:   m['time'] as String? ?? m['createdAt'] as String? ?? '',
            status: (m['read'] == true || m['status'] == 'read')
                ? ChatMessageStatus.read
                : ChatMessageStatus.sent,
          );
        }).toList();
      }
    } catch (_) {
      // Keep mock data as fallback — already set in super()
    }
  }

  static String _formatNow() {
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final m = now.minute.toString().padLeft(2, '0');
    final period = now.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  void send(String text) {
    if (text.trim().isEmpty) return;
    final trimmed = text.trim();
    state = [
      ...state,
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: trimmed,
        fromMe: true,
        time: _formatNow(),
      ),
    ];
    // Fire API call in background — optimistic UI update above
    if (bookingType != null && bookingId != null) {
      _chatService
          .sendMessage(bookingType!, bookingId!, content: trimmed)
          .catchError((_) => <String, dynamic>{});
    }
  }

  void addAttachment(File file) {
    state = [
      ...state,
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '[Attachment: ${file.path.split('/').last}]',
        fromMe: true,
        time: _formatNow(),
      ),
    ];
  }
}

final _chatProvider = StateNotifierProvider.autoDispose<_ChatNotifier,
    List<ChatMessage>>((ref) {
  final chatService = ref.watch(chatServiceProvider);
  // TODO: Pass real bookingType and bookingId from route params once wired.
  return _ChatNotifier(chatService, bookingType: null, bookingId: null);
});

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
