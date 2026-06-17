import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../domain/loyalty_models.dart';
import '../providers/points_history_provider.dart';

/// Full, paginated points ledger from `GET /v1/loyalty/transactions`.
/// Scroll to the bottom to load the next page.
class PointsHistoryScreen extends ConsumerStatefulWidget {
  const PointsHistoryScreen({super.key});

  @override
  ConsumerState<PointsHistoryScreen> createState() =>
      _PointsHistoryScreenState();
}

class _PointsHistoryScreenState extends ConsumerState<PointsHistoryScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      ref.read(pointsHistoryProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final state = ref.watch(pointsHistoryProvider);

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Points history',
          style: TextStyle(
            color: MyShopColors.textPrimary,
            fontSize: w * 0.044,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
      ),
      body: _body(state),
    );
  }

  Widget _body(PointsHistoryState state) {
    if (state.isLoadingInitial) {
      return const Center(
        child: CircularProgressIndicator(color: MyShopColors.primaryGold),
      );
    }
    if (state.error != null && state.isEmpty) {
      return _ErrorBody(
        onRetry: () => ref.read(pointsHistoryProvider.notifier).refresh(),
      );
    }
    if (state.isEmpty) {
      return const _EmptyBody();
    }

    return RefreshIndicator(
      color: MyShopColors.primaryGold,
      onRefresh: () => ref.read(pointsHistoryProvider.notifier).refresh(),
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const _LoadMoreFooter();
          }
          return _TransactionTile(tx: state.items[index]);
        },
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});

  final LoyaltyTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isEarn = tx.isEarn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isEarn
                  ? MyShopColors.primaryGoldLight
                  : MyShopColors.errorLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isEarn
                  ? Icons.add_circle_outline_rounded
                  : Icons.remove_circle_outline_rounded,
              color: isEarn ? MyShopColors.primaryGold : MyShopColors.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.label,
                  style: const TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle(tx),
                  style: const TextStyle(
                    color: MyShopColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                tx.pointsDisplay,
                style: TextStyle(
                  color: isEarn ? MyShopColors.primaryGold : MyShopColors.error,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Bal ${tx.balanceAfter}',
                style: const TextStyle(
                  color: MyShopColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(LoyaltyTransaction tx) {
    final date = tx.createdAtDate;
    final dateLabel = date == null ? '' : _formatDate(date);
    final type = tx.bookingType;
    if (type != null && type.isNotEmpty) {
      final cap = type[0].toUpperCase() + type.substring(1);
      return dateLabel.isEmpty ? cap : '$cap · $dateLabel';
    }
    return dateLabel;
  }
}

String _formatDate(DateTime dt) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hh:$mm';
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: MyShopColors.primaryGold,
          ),
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_rounded,
              color: MyShopColors.textHint, size: 56),
          const SizedBox(height: 14),
          Text(
            'No points activity yet',
            style: TextStyle(
              color: MyShopColors.textPrimary,
              fontSize: MediaQuery.sizeOf(context).width * 0.044,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Complete rides and jobs to start earning loyalty points.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MyShopColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: MyShopColors.error, size: 48),
          const SizedBox(height: 12),
          const Text('Could not load points history'),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
