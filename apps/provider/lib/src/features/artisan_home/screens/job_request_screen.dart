import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../artisan_jobs/providers/pending_incoming_jobs_provider.dart';
import '../../artisan_jobs/providers/submitted_bids_provider.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../driver_home/providers/driver_location_provider.dart';
import '../widgets/bid_status_banner.dart';
import 'bid_submission_screen.dart';

/// Full job request details — opened when an incoming job request is
/// received via Socket.IO or from the live job feed cards.
///
/// PRD Reference: PRD 5.3 — incoming job notification (category, description,
/// photos, client location, 5-minute bid window).
class JobRequestScreen extends ConsumerWidget {
  const JobRequestScreen({
    super.key,
    required this.job,
    this.bidStatus = BidStatus.none,
    this.submittedBidAmount = 0,
    this.platformFeePercent = 10,
  });

  final Job job;
  final BidStatus bidStatus;
  final num submittedBidAmount;
  final num platformFeePercent;

  String get _requestId =>
      job.id.length >= 8 ? '#${job.id.substring(0, 8).toUpperCase()}' : '#${job.id}';
  String get _clientName => job.clientName ?? 'Client';
  String get _clientLocation => job.addressText ?? 'Location pending';
  String get _title => job.categoryName != null && job.categoryName!.isNotEmpty
      ? '${job.categoryName} request'
      : 'Service Request';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionAsync = ref.watch(driverLocationStreamProvider);
    final distanceKm = positionAsync.maybeWhen(
      data: (pos) => _distanceKm(
        pos.latitude,
        pos.longitude,
        job.latitude,
        job.longitude,
      ),
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(requestId: _requestId),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: MyShopSpacing.md,
                ),
                children: [
                  if (bidStatus != BidStatus.none) ...[
                    BidStatusBanner(
                      status: bidStatus,
                      // Anchor the countdown to the actual bid expiry so it
                      // keeps decreasing across screen opens / rebuilds.
                      expiresAt: ref
                          .watch(submittedBidsProvider)[job.id]
                          ?.expiresAt,
                      // Admin-assigned jobs have no bid window — swap the
                      // countdown for a "Quote when ready" hint.
                      showCountdown: job.status != JobStatus.adminAssigned,
                      onAcceptStartJob: () => context.push('/active-job'),
                      onMessage: () => context.push('/chat'),
                    ),
                    const SizedBox(height: MyShopSpacing.md),
                  ],
                  _ClientSummaryCard(
                    clientName: _clientName,
                    clientPhotoUrl: job.clientPhotoUrl,
                    clientLocation: _clientLocation,
                    distanceKm: distanceKm,
                    title: _title,
                    postedAgo: _formatPostedAgo(job.createdAt),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionHeader(
                    icon: Icons.info_outline,
                    label: 'JOB DESCRIPTION',
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _DescriptionCard(
                    text: job.description.isNotEmpty
                        ? job.description
                        : 'No description provided.',
                  ),
                  if (job.photos.isNotEmpty) ...[
                    const SizedBox(height: MyShopSpacing.lg),
                    const _SectionHeader(
                      icon: Icons.photo_library_outlined,
                      label: 'PHOTOS',
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    _PhotosRow(photos: job.photos),
                  ],
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionHeader(
                    icon: Icons.near_me_outlined,
                    label: 'LOCATION',
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _LocationCard(
                    label: _clientLocation,
                    latitude: job.latitude,
                    longitude: job.longitude,
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  if (bidStatus == BidStatus.none) ...[
                    if (job.artisansNotified != null &&
                        job.artisansNotified! > 0)
                      _BidStatusCard(artisansNotified: job.artisansNotified!),
                    const SizedBox(height: MyShopSpacing.lg),
                    if (_isBiddable(
                      job,
                      artisanUserId: ref.watch(currentUserProvider)?.id,
                    )) ...[
                      _PlaceBidButton(
                        onTap: () => BidSubmissionScreen.show(
                          context,
                          job: job,
                          distanceKm: distanceKm ?? 0,
                        ),
                      ),
                      const SizedBox(height: MyShopSpacing.md),
                      _DeclineButton(
                        onTap: () {
                          ref
                              .read(pendingIncomingJobsProvider.notifier)
                              .remove(job.id);
                          context.pop();
                        },
                      ),
                    ] else
                      _NotBiddableNotice(
                        status: job.status,
                        assignedToMe: job.assignedArtisanId != null &&
                            job.assignedArtisanId ==
                                ref.watch(currentUserProvider)?.id,
                      ),
                  ] else ...[
                    Text(
                      'Your Submitted Bid',
                      style: MyShopTypography.h3.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    _SubmittedBidCard(
                      total: submittedBidAmount,
                      feePercent: platformFeePercent,
                    ),
                  ],
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── helpers ─────────────────────────────────────────────────────────────────

/// Whether a bid can be placed on a job in its current state for the given
/// authenticated artisan.
///
/// Two bid-accepting states:
///   - `open`             → standard public bid window (first 5 min after post)
///   - `adminAssigned`    → admin manually routed the job to this specific
///                          artisan after the public window closed with zero
///                          bids. Only the assigned artisan may quote.
///
/// Everything else (`pendingAdmin`, `queued`, `confirmed+`, `cancelled`)
/// rejects bids with `JOB_NOT_OPEN` (400) — we mirror that gate in the UI.
bool _isBiddable(Job job, {String? artisanUserId}) {
  if (job.status == JobStatus.open) return true;
  if (job.status == JobStatus.adminAssigned) {
    // Only the artisan the admin picked can quote on an admin-assigned job.
    return artisanUserId != null &&
        job.assignedArtisanId != null &&
        job.assignedArtisanId == artisanUserId;
  }
  return false;
}

double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  final meters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  return meters / 1000;
}

/// Banner shown in place of the "Place Bid" button when the job isn't in
/// a state that accepts bids (pending admin approval, already confirmed,
/// cancelled, etc.).
class _NotBiddableNotice extends StatelessWidget {
  const _NotBiddableNotice({
    required this.status,
    this.assignedToMe = false,
  });

  final JobStatus status;

  /// True when the job is admin-assigned and this artisan is the one
  /// picked. (We only get here if `_isBiddable` returned false — which for
  /// an admin-assigned job means the assignment belongs to someone else,
  /// so this is almost always false.)
  final bool assignedToMe;

  (String, String, IconData, Color) get _content {
    switch (status) {
      case JobStatus.pendingAdmin:
        return (
          'Awaiting admin review',
          "No artisans bid on this job in time. An admin is reviewing it "
              'and will assign it shortly.',
          Icons.hourglass_top,
          MyShopColors.warning,
        );
      case JobStatus.adminAssigned:
        return assignedToMe
            ? (
                'Ready to quote',
                'You can submit your price on this job.',
                Icons.check_circle_outline,
                MyShopColors.success,
              )
            : (
                'Assigned to another artisan',
                'An admin has routed this job to a different artisan.',
                Icons.lock_outline,
                MyShopColors.textSecondary,
              );
      case JobStatus.queued:
        return (
          'Queued',
          "This job is waiting for artisans to become available. Check back shortly.",
          Icons.schedule,
          MyShopColors.warning,
        );
      case JobStatus.confirmed:
      case JobStatus.artisanEnRoute:
      case JobStatus.arrived:
      case JobStatus.inProgress:
      case JobStatus.artisanMarkedComplete:
      case JobStatus.completed:
        return (
          'Already assigned',
          "The client has already chosen an artisan for this job.",
          Icons.lock_outline,
          MyShopColors.textSecondary,
        );
      case JobStatus.cancelled:
        return (
          'Cancelled',
          "This job has been cancelled and is no longer accepting bids.",
          Icons.cancel_outlined,
          MyShopColors.error,
        );
      case JobStatus.open:
        return (
          'Ready',
          'You can place a bid on this job.',
          Icons.check_circle_outline,
          MyShopColors.success,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, body, icon, color) = _content;
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MyShopTypography.h3.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textSecondary,
                    height: 1.4,
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

String _formatPostedAgo(String? createdAt) {
  if (createdAt == null) return 'Just posted';
  final parsed = DateTime.tryParse(createdAt);
  if (parsed == null) return 'Just posted';
  final diff = DateTime.now().toUtc().difference(parsed.toUtc());
  if (diff.inSeconds < 30) return 'Just posted';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.requestId});

  final String requestId;

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
        border: Border(
          bottom: BorderSide(color: MyShopColors.divider),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request Details',
                style: MyShopTypography.h1.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'ID: $requestId',
                style: MyShopTypography.overline.copyWith(
                  color: MyShopColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Client summary card
// ─────────────────────────────────────────────────────────────────────────────

class _ClientSummaryCard extends StatelessWidget {
  const _ClientSummaryCard({
    required this.clientName,
    required this.clientPhotoUrl,
    required this.clientLocation,
    required this.distanceKm,
    required this.title,
    required this.postedAgo,
  });

  final String clientName;
  final String? clientPhotoUrl;
  final String clientLocation;
  final double? distanceKm;
  final String title;
  final String postedAgo;

  @override
  Widget build(BuildContext context) {
    final distanceText = distanceKm != null
        ? '${distanceKm!.toStringAsFixed(1)} km away'
        : '—';

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ClientAvatar(photoUrl: clientPhotoUrl),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clientName,
                      style: MyShopTypography.h3.copyWith(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
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
                            '$clientLocation  •  $distanceText',
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'NOW',
                  style: MyShopTypography.caption.copyWith(
                    color: MyShopColors.textOnPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          const Divider(height: 1, color: MyShopColors.divider),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            title,
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
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientAvatar extends StatelessWidget {
  const _ClientAvatar({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header (icon + uppercase label)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: MyShopColors.textPrimary),
        const SizedBox(width: MyShopSpacing.sm),
        Text(
          label,
          style: MyShopTypography.overline.copyWith(
            color: MyShopColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Description card
// ─────────────────────────────────────────────────────────────────────────────

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Text(
        text,
        style: MyShopTypography.body1.copyWith(
          color: MyShopColors.textPrimary,
          fontWeight: FontWeight.w400,
          height: 1.55,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photos row — real Cloudinary URLs
// ─────────────────────────────────────────────────────────────────────────────

class _PhotosRow extends StatelessWidget {
  const _PhotosRow({required this.photos});

  final List<String> photos;

  @override
  Widget build(BuildContext context) {
    // Show up to 3 inline; collapse the rest into a "+N More" tile.
    const maxInline = 3;
    final inlineCount = photos.length > maxInline ? maxInline : photos.length;
    final remaining = photos.length - inlineCount;

    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (int i = 0; i < inlineCount; i++) ...[
            _PhotoThumb(
              url: photos[i],
              onTap: () => _openGallery(context, photos, i),
            ),
            const SizedBox(width: MyShopSpacing.md),
          ],
          if (remaining > 0)
            _MorePhotosTile(
              remaining: remaining,
              onTap: () => _openGallery(context, photos, inlineCount),
            ),
        ],
      ),
    );
  }

  void _openGallery(BuildContext context, List<String> urls, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PhotoGallery(urls: urls, initialIndex: initialIndex),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.url, required this.onTap});

  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 110,
          height: 110,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 110,
            height: 110,
            color: MyShopColors.surfaceGrey,
          ),
          errorWidget: (_, __, ___) => Container(
            width: 110,
            height: 110,
            color: MyShopColors.surfaceGrey,
            alignment: Alignment.center,
            child: const Icon(
              Icons.broken_image_outlined,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _MorePhotosTile extends StatelessWidget {
  const _MorePhotosTile({required this.remaining, required this.onTap});

  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DottedBorderBox(
        child: Container(
          width: 90,
          height: 110,
          alignment: Alignment.center,
          child: Text(
            '+$remaining More',
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: urls.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: urls[i],
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight dashed-border container — avoids pulling in a third-party dep.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MyShopColors.divider
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(12),
    );

    final path = Path()..addRRect(rrect);
    const dashWidth = 5.0;
    const dashSpace = 4.0;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Location card — real Google Map
// ─────────────────────────────────────────────────────────────────────────────

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;

  Future<void> _openDirections(BuildContext context) async {
    // Use the device's "pick" behavior where possible:
    //  - iOS: Apple Maps (always installed) with driving directions.
    //  - Android: `geo:` with a directions query so Google Maps or whatever
    //    the user has mapped to the geo intent picks it up.
    //  - Fallback (web or unknown): Google Maps URL that works in Safari /
    //    Chrome and also opens the GMaps app if installed.
    final candidates = <Uri>[
      if (Platform.isIOS)
        Uri.parse('http://maps.apple.com/?daddr=$latitude,$longitude&dirflg=d')
      else if (Platform.isAndroid)
        Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=$latitude,$longitude&travelmode=driving',
      ),
    ];

    for (final uri in candidates) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (_) {
        // Try the next candidate.
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open a maps app.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = LatLng(latitude, longitude);

    return InkWell(
      onTap: () => _openDirections(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Google Maps consumes taps, so we put an overlay on top that
            // forwards them to the same navigate handler.
            SizedBox(
              height: 160,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: target,
                        zoom: 15,
                      ),
                      liteModeEnabled: true,
                      markers: {
                        Marker(
                          markerId: const MarkerId('job'),
                          position: target,
                        ),
                      },
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      scrollGesturesEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      zoomGesturesEnabled: false,
                    ),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openDirections(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
                vertical: MyShopSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 16,
                    color: MyShopColors.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: MyShopTypography.body1,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: MyShopColors.primaryGold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.navigation,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Navigate',
                          style: MyShopTypography.body2.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
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
// Bid status card — uses real artisansNotified count
// ─────────────────────────────────────────────────────────────────────────────

class _BidStatusCard extends StatelessWidget {
  const _BidStatusCard({required this.artisansNotified});

  final int artisansNotified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.group_outlined,
            size: 18,
            color: MyShopColors.primaryGold,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              '$artisansNotified artisan${artisansNotified == 1 ? '' : 's'} '
              'notified — be quick to bid',
              style: MyShopTypography.body1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action buttons
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceBidButton extends StatelessWidget {
  const _PlaceBidButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: MyShopColors.darkSlate,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          'PLACE BID',
          style: MyShopTypography.button.copyWith(
            color: MyShopColors.textOnDarkSlate,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submitted bid summary (dashed border)
// ─────────────────────────────────────────────────────────────────────────────

class _SubmittedBidCard extends StatelessWidget {
  const _SubmittedBidCard({required this.total, required this.feePercent});

  final num total;
  final num feePercent;

  @override
  Widget build(BuildContext context) {
    final fee = (total * feePercent) / 100;
    final net = total - fee;
    return DottedBorderBox(
      child: Padding(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total Bid Amount',
                    style: MyShopTypography.body1.copyWith(
                      color: MyShopColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  'GHS ${total.toStringAsFixed(2)}',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Platform Fee (${feePercent.toInt()}%)',
                    style: MyShopTypography.body1.copyWith(
                      color: MyShopColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  '-GHS ${fee.toStringAsFixed(2)}',
                  style: MyShopTypography.body1.copyWith(
                    color: MyShopColors.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.sm),
            const Divider(height: 1, color: MyShopColors.divider),
            const SizedBox(height: MyShopSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimated Net',
                    style: MyShopTypography.body1.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'GHS ${net.toStringAsFixed(2)}',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeclineButton extends StatelessWidget {
  const _DeclineButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: MyShopColors.divider),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                shape: BoxShape.circle,
                border: Border.all(color: MyShopColors.error, width: 1.5),
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: MyShopColors.error,
              ),
            ),
            const SizedBox(width: MyShopSpacing.sm),
            Text(
              'Decline',
              style: MyShopTypography.button.copyWith(
                color: MyShopColors.error,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
