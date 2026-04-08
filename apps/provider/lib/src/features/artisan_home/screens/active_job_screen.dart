import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

/// Active job — "accepted" landing view shown immediately after the artisan
/// taps "Accept & Start Job". Kicks off the navigation lifecycle: client
/// details, next steps checklist, message/call CTAs.
///
/// PRD Reference: PRD 5.3 — navigation, mark arrived/in_progress/complete,
/// chat/call, emergency button, welfare check response.
class ActiveJobScreen extends StatelessWidget {
  const ActiveJobScreen({
    super.key,
    this.title = 'Emergency Pipe Leak Repair',
    this.jobId = '#ART-88291',
    this.acceptedAt = 'Today, 10:42 AM',
    this.clientName = 'Ama Serwaa',
    this.clientLocation = 'Adum, Kumasi',
    this.distanceKm = 1.2,
    this.requestTitle = 'Emergency: Burst Main Pipe in Kitchen',
    this.postedAgo = 'Posted 2 mins ago',
    this.rating = 5.0,
    this.reviewsCount = 12,
    this.locationAddress = 'East Legon, near French School',
    this.durationEstimate = 'approx. 2 - 3 hours',
    this.preferredStart = 'ASAP - Today',
    this.description =
        '"We have a major leak under the kitchen sink that started about an hour ago. Water is pooling on the floor. I need someone to replace the U-bend and check for any other blockages. I have some basic tools but please bring your professional kit."',
    this.tags = const ['Plumbing', 'Emergency'],
    this.nextSteps = const [
      'Move towards client location',
      'Gather your plumbing tools & spare washers',
      "Message client if you're running late",
    ],
  });

  final String title;
  final String jobId;
  final String acceptedAt;
  final String clientName;
  final String clientLocation;
  final double distanceKm;
  final String requestTitle;
  final String postedAgo;
  final double rating;
  final int reviewsCount;
  final String locationAddress;
  final String durationEstimate;
  final String preferredStart;
  final String description;
  final List<String> tags;
  final List<String> nextSteps;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: title, jobId: jobId),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: MyShopSpacing.md,
                ),
                children: [
                  _AcceptedCard(
                    acceptedAt: acceptedAt,
                    nextSteps: nextSteps,
                    onMessage: () => context.push('/chat'),
                    onCall: () {},
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ORIGINAL REQUEST',
                          style: MyShopTypography.overline.copyWith(
                            color: MyShopColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: MyShopColors.surfaceWhite,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: MyShopColors.primaryGold,
                            width: 1.4,
                          ),
                        ),
                        child: Text(
                          'Priority',
                          style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.primaryGold,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _ClientCard(
                    clientName: clientName,
                    clientLocation: clientLocation,
                    distanceKm: distanceKm,
                    requestTitle: requestTitle,
                    postedAgo: postedAgo,
                    rating: rating,
                    reviewsCount: reviewsCount,
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'LOCATION',
                    value: locationAddress,
                  ),
                  const _RowDivider(),
                  _InfoRow(
                    icon: Icons.access_time,
                    label: 'DURATION ESTIMATE',
                    value: durationEstimate,
                  ),
                  const _RowDivider(),
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'PREFERRED START',
                    value: preferredStart,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Text(
                    'JOB DESCRIPTION',
                    style: MyShopTypography.overline.copyWith(
                      color: MyShopColors.textSecondary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(MyShopSpacing.md),
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MyShopColors.divider),
                    ),
                    child: Text(
                      description,
                      style: MyShopTypography.body1.copyWith(
                        fontWeight: FontWeight.w400,
                        height: 1.55,
                      ),
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  Wrap(
                    spacing: MyShopSpacing.sm,
                    runSpacing: MyShopSpacing.sm,
                    children: [
                      for (final tag in tags) _TagPill(label: tag),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.xxl),
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
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.jobId});

  final String title;
  final String jobId;

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MyShopTypography.h1.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Job ID: $jobId',
                  style: MyShopTypography.body2,
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
// Accepted card
// ─────────────────────────────────────────────────────────────────────────────

class _AcceptedCard extends StatelessWidget {
  const _AcceptedCard({
    required this.acceptedAt,
    required this.nextSteps,
    required this.onMessage,
    required this.onCall,
  });

  final String acceptedAt;
  final List<String> nextSteps;
  final VoidCallback onMessage;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.successLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: MyShopColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Accepted',
                      style: MyShopTypography.body2.copyWith(
                        color: MyShopColors.success,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.more_vert,
                size: 20,
                color: MyShopColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            acceptedAt,
            style: MyShopTypography.body2,
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Next steps inner card
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: MyShopColors.success,
                    ),
                    const SizedBox(width: MyShopSpacing.sm),
                    Text(
                      'Next Steps for You',
                      style: MyShopTypography.h3.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MyShopSpacing.sm),
                for (final step in nextSteps) _NextStepRow(text: step),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),

          // Message + Call buttons
          Row(
            children: [
              Expanded(
                child: _GreenOutlinedButton(
                  icon: Icons.chat_bubble_outline,
                  label: 'Message',
                  onTap: onMessage,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: _GreenOutlinedButton(
                  icon: Icons.phone_outlined,
                  label: 'Call Client',
                  onTap: onCall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NextStepRow extends StatelessWidget {
  const _NextStepRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 2),
            decoration: const BoxDecoration(
              color: MyShopColors.successLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              size: 12,
              color: MyShopColors.success,
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: MyShopTypography.body1.copyWith(
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GreenOutlinedButton extends StatelessWidget {
  const _GreenOutlinedButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.success, width: 1.4),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: MyShopColors.success),
            const SizedBox(width: MyShopSpacing.sm),
            Text(
              label,
              style: MyShopTypography.button.copyWith(
                color: MyShopColors.success,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Client card
// ─────────────────────────────────────────────────────────────────────────────

class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.clientName,
    required this.clientLocation,
    required this.distanceKm,
    required this.requestTitle,
    required this.postedAgo,
    required this.rating,
    required this.reviewsCount,
  });

  final String clientName;
  final String clientLocation;
  final double distanceKm;
  final String requestTitle;
  final String postedAgo;
  final double rating;
  final int reviewsCount;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: MyShopColors.avatarPlaceholder,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person,
                    color: MyShopColors.textSecondary),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            clientName,
                            style: MyShopTypography.h3.copyWith(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          size: 16,
                          color: MyShopColors.info,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: MyShopColors.primaryGold,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '$clientLocation  •  ${distanceKm.toStringAsFixed(1)} km away',
                            style: MyShopTypography.body2.copyWith(
                              color: MyShopColors.primaryGold,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: MyShopColors.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'NOW',
                  style: MyShopTypography.caption.copyWith(
                    color: MyShopColors.textOnPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          const Divider(height: 1, color: MyShopColors.divider),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            requestTitle,
            style: MyShopTypography.h2.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Row(
            children: [
              const Icon(
                Icons.access_time,
                size: 14,
                color: MyShopColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(postedAgo, style: MyShopTypography.body2),
              const SizedBox(width: MyShopSpacing.md),
              const Icon(
                Icons.star,
                size: 14,
                color: MyShopColors.ratingStar,
              ),
              const SizedBox(width: 4),
              Text(
                rating.toStringAsFixed(1),
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.primaryGold,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Text('($reviewsCount Reviews)', style: MyShopTypography.body2),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info rows
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: MyShopColors.textPrimary),
          ),
          const SizedBox(width: MyShopSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: MyShopTypography.overline.copyWith(
                    color: MyShopColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
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

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 52),
      child: Divider(height: 1, color: MyShopColors.divider),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tag pill
// ─────────────────────────────────────────────────────────────────────────────

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: MyShopTypography.body2.copyWith(
          color: MyShopColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
