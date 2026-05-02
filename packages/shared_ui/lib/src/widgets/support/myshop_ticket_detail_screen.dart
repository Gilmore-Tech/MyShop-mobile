import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import '../myshop_chat_screen.dart' as chat_ui;
import 'myshop_support_legal_screen.dart' show SupportLegalAsync;

/// Ticket detail — header with subject + status + resolve/reopen actions,
/// and a chat-style message thread reusing [chat_ui.MyShopChatScreen].
///
/// The widget treats the ticket + messages tri-state independently: the
/// header can render with cached data while messages are still loading
/// in, and vice-versa.
class MyShopTicketDetailScreen extends StatelessWidget {
  const MyShopTicketDetailScreen({
    super.key,
    required this.ticketState,
    required this.messagesState,
    required this.onSendMessage,
    required this.onResolve,
    required this.onReopen,
    this.onFilePicked,
    this.onMessageVisible,
  });

  final SupportLegalAsync<SupportTicket> ticketState;
  final SupportLegalAsync<List<TicketMessage>> messagesState;

  /// Caller is responsible for the optimistic-insert + ack flow. The
  /// shell just hands over the typed body.
  final ValueChanged<String> onSendMessage;

  final VoidCallback onResolve;
  final VoidCallback onReopen;
  final ValueChanged<File>? onFilePicked;
  final ValueChanged<String>? onMessageVisible;

  @override
  Widget build(BuildContext context) {
    final ticket = ticketState.data;
    final messages = messagesState.data ?? const <TicketMessage>[];
    final chatMessages = messages.map(_toChatMessage).toList();

    final isInputLocked = ticket?.status.isTerminal ?? false;
    final lockedReason = isInputLocked
        ? (ticket?.status == TicketStatus.resolved
            ? 'This ticket is resolved. Reopen it to send a new reply.'
            : 'This ticket is closed. Open a new ticket if you need more help.')
        : null;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(ticket: ticket, onResolve: onResolve, onReopen: onReopen),
            if (ticketState.hasError && !ticketState.hasData)
              _HeaderErrorBanner(error: ticketState.error!),
            Expanded(
              child: chat_ui.MyShopChatScreen(
                peerName: 'Support',
                peerStatus: ticket == null ? '' : _peerStatusFor(ticket.status),
                messages: chatMessages,
                onSend: onSendMessage,
                onFilePicked: onFilePicked,
                onMessageVisible: onMessageVisible,
                isInputLocked: isInputLocked,
                lockedReason: lockedReason,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Adapter — TicketMessage → the chat widget's local ChatMessage.
  /// `senderRole == user` flips `fromMe`; agent + system render as the
  /// other side. System notes get a leading `🛈` to set them apart from
  /// agent replies.
  static chat_ui.ChatMessage _toChatMessage(TicketMessage m) {
    final body = m.isSystemNote ? 'ℹ︎ ${m.body}' : m.body;
    return chat_ui.ChatMessage(
      id: m.id,
      text: body,
      time: _formatTime(m.createdAt),
      fromMe: m.isFromUser,
      // We don't get per-message ack state from the REST API yet; treat
      // server-returned messages as `sent`. Optimistic inserts written by
      // the caller can use `pending` and swap on ack.
      status: chat_ui.ChatMessageStatus.sent,
    );
  }

  static String _peerStatusFor(TicketStatus status) {
    switch (status) {
      case TicketStatus.open:
        return 'Open';
      case TicketStatus.inProgress:
        return 'Agent is working on this';
      case TicketStatus.waitingUser:
        return 'Waiting for your reply';
      case TicketStatus.resolved:
        return 'Resolved';
      case TicketStatus.closed:
        return 'Closed';
    }
  }

  static String _formatTime(DateTime when) {
    final h = when.hour.toString().padLeft(2, '0');
    final m = when.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.ticket,
    required this.onResolve,
    required this.onReopen,
  });

  final SupportTicket? ticket;
  final VoidCallback onResolve;
  final VoidCallback onReopen;

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
            icon: const Icon(
              Icons.arrow_back,
              color: MyShopColors.textPrimary,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket?.subject ?? 'Ticket',
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ticket != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _StatusDot(status: ticket!.status),
                      const SizedBox(width: 6),
                      Text(
                        _statusLabel(ticket!.status),
                        style: MyShopTypography.body2.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.sm),
                      Text(
                        '#${ticket!.id.split('-').first}',
                        style: MyShopTypography.body2,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (ticket != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'resolve') onResolve();
                if (v == 'reopen') onReopen();
              },
              itemBuilder: (_) => [
                if (ticket!.isOpen)
                  const PopupMenuItem(
                    value: 'resolve',
                    child: Text('Mark as resolved'),
                  ),
                if (ticket!.status == TicketStatus.resolved)
                  const PopupMenuItem(
                    value: 'reopen',
                    child: Text('Reopen ticket'),
                  ),
              ],
              icon: const Icon(
                Icons.more_vert,
                color: MyShopColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  static String _statusLabel(TicketStatus s) {
    switch (s) {
      case TicketStatus.open:
        return 'Open';
      case TicketStatus.inProgress:
        return 'In progress';
      case TicketStatus.waitingUser:
        return 'Waiting for you';
      case TicketStatus.resolved:
        return 'Resolved';
      case TicketStatus.closed:
        return 'Closed';
    }
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TicketStatus.open => MyShopColors.info,
      TicketStatus.inProgress => MyShopColors.warning,
      TicketStatus.waitingUser => MyShopColors.primaryGold,
      TicketStatus.resolved => MyShopColors.success,
      TicketStatus.closed => MyShopColors.textHint,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _HeaderErrorBanner extends StatelessWidget {
  const _HeaderErrorBanner({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.sm,
      ),
      color: MyShopColors.errorLight,
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            size: 16,
            color: MyShopColors.error,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              "Couldn't load ticket details. Showing cached info.",
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
