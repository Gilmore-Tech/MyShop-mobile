import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import 'myshop_support_legal_screen.dart' show SupportLegalAsync;

/// Paginated list of the caller's support tickets.
///
/// The widget is dumb — it only displays whatever the caller's provider
/// hands to it. Pagination is forward-only and surfaces via [onLoadMore]
/// when the user nears the bottom of the list. Pull-to-refresh fires
/// [onRefresh].
class MyShopTicketsListScreen extends StatefulWidget {
  const MyShopTicketsListScreen({
    super.key,
    required this.state,
    required this.onTicketTap,
    required this.onNewTicket,
    required this.onRefresh,
    required this.onLoadMore,
    required this.hasMore,
  });

  final SupportLegalAsync<List<SupportTicket>> state;
  final void Function(SupportTicket ticket) onTicketTap;
  final VoidCallback onNewTicket;
  final Future<void> Function() onRefresh;

  /// Fired once when the user scrolls within ~120 px of the end of the
  /// list. Caller is responsible for de-duping concurrent calls.
  final VoidCallback onLoadMore;
  final bool hasMore;

  @override
  State<MyShopTicketsListScreen> createState() =>
      _MyShopTicketsListScreenState();
}

class _MyShopTicketsListScreenState extends State<MyShopTicketsListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    if (!widget.hasMore) return;
    if (widget.state.loading) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'My tickets',
          style: MyShopTypography.h1.copyWith(fontSize: 18),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onNewTicket,
        backgroundColor: MyShopColors.primaryGold,
        foregroundColor: MyShopColors.textOnPrimary,
        icon: const Icon(Icons.add),
        label: Text(
          'New ticket',
          style: MyShopTypography.button.copyWith(
            color: MyShopColors.textOnPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final state = widget.state;
    if (state.loading && !state.hasData) {
      return const _ListSkeleton();
    }
    if (state.hasError && !state.hasData) {
      return _ErrorBody(
        error: state.error!,
        onRetry: widget.onRefresh,
      );
    }
    final tickets = state.data ?? const [];
    if (tickets.isEmpty) {
      return const _EmptyBody();
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        96, // FAB clearance
      ),
      itemCount: tickets.length + (widget.hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: MyShopSpacing.sm),
      itemBuilder: (context, index) {
        if (index >= tickets.length) {
          return const Padding(
            padding: EdgeInsets.all(MyShopSpacing.md),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final t = tickets[index];
        return _TicketRow(
          ticket: t,
          onTap: () => widget.onTicketTap(t),
        );
      },
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket, required this.onTap});
  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = ticket.lastMessagePreview ?? ticket.description ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ticket.subject.isEmpty
                        ? _categoryLabel(ticket.category)
                        : ticket.subject,
                    style: MyShopTypography.h3.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusPill(status: ticket.status),
              ],
            ),
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                preview,
                style: MyShopTypography.body2,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: MyShopSpacing.sm),
            Row(
              children: [
                Text(
                  _categoryLabel(ticket.category),
                  style: MyShopTypography.caption.copyWith(
                    color: MyShopColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTimestamp(ticket.lastMessageAt ?? ticket.updatedAt),
                  style: MyShopTypography.caption,
                ),
                if (ticket.hasUnread) ...[
                  const SizedBox(width: MyShopSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: MyShopColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      ticket.unreadCount > 99 ? '99+' : '${ticket.unreadCount}',
                      style: MyShopTypography.caption.copyWith(
                        color: MyShopColors.textOnPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _categoryLabel(TicketCategory c) {
    switch (c) {
      case TicketCategory.account:
        return 'Account';
      case TicketCategory.payments:
        return 'Payments';
      case TicketCategory.rides:
        return 'Rides';
      case TicketCategory.jobs:
        return 'Jobs';
      case TicketCategory.payouts:
        return 'Payouts';
      case TicketCategory.verification:
        return 'Verification';
      case TicketCategory.safety:
        return 'Safety';
      case TicketCategory.bug:
        return 'Bug';
      case TicketCategory.other:
        return 'Other';
    }
  }

  static String _formatTimestamp(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final TicketStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = _styleFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: MyShopTypography.caption.copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  static (String, Color, Color) _styleFor(TicketStatus s) {
    switch (s) {
      case TicketStatus.open:
        return ('Open', MyShopColors.infoLight, MyShopColors.info);
      case TicketStatus.inProgress:
        return ('In progress', MyShopColors.warningLight, MyShopColors.warning);
      case TicketStatus.waitingUser:
        return (
          'Reply needed',
          MyShopColors.primaryGoldLight,
          MyShopColors.primaryGoldDark
        );
      case TicketStatus.resolved:
        return ('Resolved', MyShopColors.successLight, MyShopColors.success);
      case TicketStatus.closed:
        return ('Closed', MyShopColors.surfaceGrey, MyShopColors.textSecondary);
    }
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: MyShopSpacing.sm),
      itemBuilder: (_, __) => Container(
        height: 88,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        const Center(
          child: Icon(
            Icons.inbox_outlined,
            size: 56,
            color: MyShopColors.textSecondary,
          ),
        ),
        const SizedBox(height: MyShopSpacing.md),
        Center(
          child: Text(
            'No tickets yet',
            style: MyShopTypography.h3.copyWith(fontSize: 16),
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: MyShopSpacing.xl,
          ),
          child: Text(
            'When you open a ticket, your conversation with support will show up here.',
            style: MyShopTypography.body2,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});
  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        const Center(
          child: Icon(
            Icons.error_outline,
            size: 56,
            color: MyShopColors.error,
          ),
        ),
        const SizedBox(height: MyShopSpacing.md),
        Center(
          child: Text(
            "Couldn't load your tickets",
            style: MyShopTypography.h3.copyWith(fontSize: 16),
          ),
        ),
        const SizedBox(height: MyShopSpacing.md),
        Center(
          child: TextButton(
            onPressed: onRetry,
            child: Text(
              'Try again',
              style: MyShopTypography.button.copyWith(
                color: MyShopColors.primaryGold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
