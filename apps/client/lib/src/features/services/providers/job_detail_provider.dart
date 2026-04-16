import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Job Status ────────────────────────────────────────────────────────────────
// EDD § 7.1 Job Request & Bid Lifecycle.
// Status progression: queued → pending → bids_received → selecting_artisan
//                     → confirmed → en_route → arrived → in_progress
//                     → completed | cancelled

enum JobStatus {
  queued,
  pending,
  bidsReceived,
  selectingArtisan,
  confirmed,
  enRoute,
  arrived,
  inProgress,
  completed,
  cancelled,
}

extension JobStatusX on JobStatus {
  String get displayLabel => switch (this) {
        JobStatus.queued           => 'Queued',
        JobStatus.pending          => 'Pending',
        JobStatus.bidsReceived     => 'Bids Received',
        JobStatus.selectingArtisan => 'Ongoing',
        JobStatus.confirmed        => 'Confirmed',
        JobStatus.enRoute          => 'En Route',
        JobStatus.arrived          => 'Arrived',
        JobStatus.inProgress       => 'In Progress',
        JobStatus.completed        => 'Completed',
        JobStatus.cancelled        => 'Cancelled',
      };

  Color get badgeColor => switch (this) {
        JobStatus.completed        => MyShopColors.success,
        JobStatus.cancelled        => MyShopColors.error,
        JobStatus.inProgress       => MyShopColors.primaryGold,
        JobStatus.enRoute          => MyShopColors.primaryGold,
        JobStatus.arrived          => MyShopColors.primaryGold,
        JobStatus.selectingArtisan => MyShopColors.primaryGold,
        JobStatus.confirmed        => MyShopColors.success,
        _                          => MyShopColors.warning,
      };
}

// ── Timeline Step ─────────────────────────────────────────────────────────────
// Represents a single step in the Request Timeline displayed on the detail screen.

enum TimelineStepStatus { completed, active, pending }

class TimelineStep {
  final String title;
  final TimelineStepStatus status;

  /// Formatted time string, e.g. "TODAY, 09:15 AM". Null for future steps.
  final String? timeLabel;

  /// Subtitle badge text shown for active/pending steps, e.g. "IN PROGRESS".
  final String? badgeLabel;

  /// Supporting description for the step.
  final String description;

  const TimelineStep({
    required this.title,
    required this.status,
    this.timeLabel,
    this.badgeLabel,
    required this.description,
  });
}

// ── Bid Summary ───────────────────────────────────────────────────────────────
// Lightweight model for the bid count and artisan avatar stack shown in the card.

class BidSummary {
  final int count;

  /// Up to 3 placeholder colours for the avatar stack.
  final List<Color> avatarColors;

  const BidSummary({required this.count, required this.avatarColors});
}

// ── Job Detail ────────────────────────────────────────────────────────────────
// Full detail model for a single artisan job request.
// API: GET /v1/jobs/:id (EDD § Marketplace Endpoints)

class JobDetail {
  final String id;
  final String title;
  final String categoryName;
  final String location;
  final JobStatus status;
  final bool isImmediate;

  /// Only set when [isImmediate] is false — the scheduled appointment time.
  final DateTime? scheduledFor;

  final String description;

  /// Number of reference photos attached.
  final int photoCount;

  /// Placeholder colours for reference photo cards.
  final List<Color> photoColors;

  final BidSummary bids;
  final List<TimelineStep> timeline;

  const JobDetail({
    required this.id,
    required this.title,
    required this.categoryName,
    required this.location,
    required this.status,
    required this.isImmediate,
    this.scheduledFor,
    required this.description,
    required this.photoCount,
    required this.photoColors,
    required this.bids,
    required this.timeline,
  });
}

// ── Mock data ─────────────────────────────────────────────────────────────────

final _mockJobDetail = JobDetail(
  id: 'JOB-3847',
  title: 'Kitchen Cabinetry',
  categoryName: 'Carpentry & Decor',
  location: 'Kumasi, Ashanti Region',
  status: JobStatus.selectingArtisan,
  isImmediate: true,
  description:
      'Need a professional carpenter to install modern, high-gloss kitchen '
      'cabinets. The space is roughly 4×3 meters. I already have the materials '
      'delivered, just need expert assembly and precision fitting. Focus on '
      'soft-close hinges and seamless handles.',
  photoCount: 4,
  photoColors: [
    Color(0xFF6D4C3D), // warm wood tone placeholder
    Color(0xFF607D8B), // cool grey placeholder
    Color(0xFF4E342E), // dark brown placeholder
    Color(0xFF455A64), // slate placeholder
  ],
  bids: const BidSummary(
    count: 12,
    avatarColors: [
      Color(0xFF5D4037), // Samuel Kwaku
      Color(0xFF795548), // Isaac Osei
      Color(0xFF607D8B), // Kwame Mensah
    ],
  ),
  timeline: const [
    TimelineStep(
      title: 'Request Posted',
      status: TimelineStepStatus.completed,
      timeLabel: 'TODAY, 09:15 AM',
      description:
          'Your request for Kitchen Cabinetry was successfully posted to the marketplace.',
    ),
    TimelineStep(
      title: 'Bids Received',
      status: TimelineStepStatus.completed,
      timeLabel: 'TODAY, 10:35 AM',
      description:
          '12 local artisans have sent their offers for your review.',
    ),
    TimelineStep(
      title: 'Selecting Artisan',
      status: TimelineStepStatus.active,
      badgeLabel: 'IN PROGRESS',
      description:
          'Review bids and chat with artisans to finalize the selection.',
    ),
    TimelineStep(
      title: 'Assigned to Artisan',
      status: TimelineStepStatus.pending,
      badgeLabel: 'PENDING',
      description: 'An artisan will be assigned once you select a bid.',
    ),
  ],
);

// ── Provider ──────────────────────────────────────────────────────────────────

final jobDetailProvider =
    AsyncNotifierProvider.autoDispose.family<_JobDetailNotifier, JobDetail, String>(
  _JobDetailNotifier.new,
);

class _JobDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<JobDetail, String> {
  @override
  Future<JobDetail> build(String jobId) async {
    // TODO: replace with GET /v1/jobs/:id via API client
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockJobDetail;
  }
}
