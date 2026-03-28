import 'package:flutter/material.dart';

/// Incoming bids list (max 3) with artisan profile, rating, portfolio, bid amount, message. Select preferred artisan
/// PRD Reference: PRD 4.5
class BidReviewScreen extends StatelessWidget {
  const BidReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BidReviewScreen')),
      body: const Center(
        child: Text('TODO: Implement BidReviewScreen'),
      ),
    );
  }
}
