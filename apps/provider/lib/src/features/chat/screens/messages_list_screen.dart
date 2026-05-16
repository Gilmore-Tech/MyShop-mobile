import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

/// Conversations list — entry point for the artisan Messages tab.
///
/// PRD Reference: PRD 4.7 — in-app messaging hub.
/// Lives inside the shell so the bottom nav remains visible. Tapping a row
/// pushes the full chat screen at `/chat`.
class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  final TextEditingController _search = TextEditingController();
  _Filter _filter = _Filter.all;

  static const _conversations = <_Conversation>[
    _Conversation(
      name: 'Ama Serwaa',
      lastMessage: 'Perfect. The water is everywhere — please come quickly!',
      timestamp: '10:44 AM',
      unreadCount: 2,
      isOnline: true,
      jobContext: 'Emergency: Burst Pipe',
    ),
    _Conversation(
      name: 'Kofi Mensah',
      lastMessage: "I've left the gate open for you.",
      timestamp: '09:12 AM',
      unreadCount: 0,
      isOnline: true,
      jobContext: 'Electrical Wiring',
    ),
    _Conversation(
      name: 'John Doe',
      lastMessage: 'Thanks again for the great service!',
      timestamp: 'Yesterday',
      unreadCount: 0,
      isOnline: false,
    ),
    _Conversation(
      name: 'Adwoa Boateng',
      lastMessage: 'Can you confirm your ETA for tomorrow?',
      timestamp: 'Yesterday',
      unreadCount: 1,
      isOnline: false,
      jobContext: 'AC Servicing',
    ),
    _Conversation(
      name: 'Ekow Taylor',
      lastMessage: 'You: Bringing my full kit.',
      timestamp: 'Mon',
      unreadCount: 0,
      isOnline: false,
    ),
    _Conversation(
      name: 'Akosua Mensah',
      lastMessage: 'Great, see you then!',
      timestamp: 'Sun',
      unreadCount: 0,
      isOnline: false,
    ),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Conversation> get _filtered {
    final q = _search.text.trim().toLowerCase();
    Iterable<_Conversation> list = _conversations;
    if (_filter == _Filter.unread) {
      list = list.where((c) => c.unreadCount > 0);
    } else if (_filter == _Filter.active) {
      list = list.where((c) => c.jobContext != null);
    }
    if (q.isNotEmpty) {
      list = list.where(
        (c) =>
            c.name.toLowerCase().contains(q) ||
            c.lastMessage.toLowerCase().contains(q),
      );
    }
    return list.toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(),
            _SearchField(
              controller: _search,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: MyShopSpacing.sm),
            _FilterChips(
              value: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
            const SizedBox(height: MyShopSpacing.sm),
            Expanded(
              child: results.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Padding(
                        padding: EdgeInsets.only(left: 76),
                        child: Divider(
                          height: 1,
                          color: MyShopColors.divider,
                        ),
                      ),
                      itemBuilder: (context, i) {
                        return _ConversationTile(
                          conversation: results[i],
                          onTap: () => context.push('/chat'),
                        );
                      },
                    ),
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
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.sm,
      ),
      child: Text(
        'Messages',
        style: MyShopTypography.h1.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search field
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.offWhite,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search,
              size: 18,
              color: MyShopColors.textSecondary,
            ),
            const SizedBox(width: MyShopSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: MyShopTypography.body1,
                decoration: InputDecoration(
                  hintText: 'Search messages…',
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
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────

enum _Filter { all, unread, active }

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.value, required this.onChanged});

  final _Filter value;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      child: Row(
        children: [
          _chip('All', _Filter.all),
          const SizedBox(width: MyShopSpacing.sm),
          _chip('Unread', _Filter.unread),
          const SizedBox(width: MyShopSpacing.sm),
          _chip('Active jobs', _Filter.active),
        ],
      ),
    );
  }

  Widget _chip(String label, _Filter f) {
    final selected = value == f;
    return GestureDetector(
      onTap: () => onChanged(f),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? MyShopColors.primaryGold : MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? MyShopColors.primaryGold : MyShopColors.divider,
          ),
        ),
        child: Text(
          label,
          style: MyShopTypography.body2.copyWith(
            color: selected
                ? MyShopColors.textPrimary
                : MyShopColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversation tile
// ─────────────────────────────────────────────────────────────────────────────

class _Conversation {
  const _Conversation({
    required this.name,
    required this.lastMessage,
    required this.timestamp,
    required this.unreadCount,
    required this.isOnline,
    this.jobContext,
  });

  final String name;
  final String lastMessage;
  final String timestamp;
  final int unreadCount;
  final bool isOnline;
  final String? jobContext;
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final _Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md,
          vertical: MyShopSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar with optional online dot
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: MyShopColors.avatarPlaceholder,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    color: MyShopColors.textSecondary,
                  ),
                ),
                if (conversation.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: MyShopColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: MyShopColors.surfaceWhite,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: MyShopSpacing.md),

            // Name + last message + optional job context
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.name,
                          style: MyShopTypography.h3.copyWith(
                            fontSize: 16,
                            fontWeight:
                                hasUnread ? FontWeight.w800 : FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.sm),
                      Text(
                        conversation.timestamp,
                        style: MyShopTypography.caption.copyWith(
                          color: hasUnread
                              ? MyShopColors.primaryGold
                              : MyShopColors.textSecondary,
                          fontWeight:
                              hasUnread ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessage,
                          style: MyShopTypography.body2.copyWith(
                            color: hasUnread
                                ? MyShopColors.textPrimary
                                : MyShopColors.textSecondary,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: MyShopSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          constraints: const BoxConstraints(minWidth: 20),
                          decoration: const BoxDecoration(
                            color: MyShopColors.primaryGold,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${conversation.unreadCount}',
                            textAlign: TextAlign.center,
                            style: MyShopTypography.caption.copyWith(
                              color: MyShopColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (conversation.jobContext != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.work_outline,
                          size: 12,
                          color: MyShopColors.primaryGold,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            conversation.jobContext!,
                            style: MyShopTypography.caption.copyWith(
                              color: MyShopColors.primaryGold,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MyShopSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 32,
                color: MyShopColors.textSecondary,
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              'No messages yet',
              style: MyShopTypography.h3.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: MyShopSpacing.sm),
            Text(
              'When clients message you about a job, the conversation will appear here.',
              textAlign: TextAlign.center,
              style: MyShopTypography.body2.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
