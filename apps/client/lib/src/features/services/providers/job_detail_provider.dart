import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Job Status ────────────────────────────────────────────────────────────────
// EDD § 7.1 Job Request & Bid Lifecycle.
// Status progression: queued → pending → bids_received → selecting_artisan
//                     → confirmed → en_route → arrived → in_progress
//                     → completed | cancelled

enum JobStatus {
  queued,
  open,
  confirmed,
  enRoute,
  arrived,
  inProgress,
  artisanMarkedComplete,
  completed,
  cancelled,
}

extension JobStatusX on JobStatus {
  String get displayLabel => switch (this) {
        JobStatus.queued               => 'Queued',
        JobStatus.open                 => 'Open',
        JobStatus.confirmed            => 'Confirmed',
        JobStatus.enRoute              => 'En Route',
        JobStatus.arrived              => 'Arrived',
        JobStatus.inProgress           => 'In Progress',
        JobStatus.artisanMarkedComplete => 'Awaiting Confirmation',
        JobStatus.completed            => 'Completed',
        JobStatus.cancelled            => 'Cancelled',
      };

  Color get badgeColor => switch (this) {
        JobStatus.completed            => MyShopColors.success,
        JobStatus.cancelled            => MyShopColors.error,
        JobStatus.inProgress           => MyShopColors.primaryGold,
        JobStatus.artisanMarkedComplete => MyShopColors.primaryGold,
        JobStatus.enRoute              => MyShopColors.primaryGold,
        JobStatus.arrived              => MyShopColors.primaryGold,
        JobStatus.confirmed            => MyShopColors.success,
        _                              => MyShopColors.warning,
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
  final IconData categoryIcon;
  final String location;
  final JobStatus status;
  final bool isImmediate;

  /// Only set when [isImmediate] is false — the scheduled appointment time.
  final DateTime? scheduledFor;

  final String description;

  /// URLs of reference photos attached to this job.
  final List<String> photoUrls;

  final BidSummary bids;
  final List<TimelineStep> timeline;

  const JobDetail({
    required this.id,
    required this.title,
    required this.categoryName,
    required this.categoryIcon,
    required this.location,
    required this.status,
    required this.isImmediate,
    this.scheduledFor,
    required this.description,
    required this.photoUrls,
    required this.bids,
    required this.timeline,
  });
}

// ── Mock data ─────────────────────────────────────────────────────────────────

final _mockJobDetail = JobDetail(
  id: 'JOB-3847',
  title: 'Kitchen Cabinetry',
  categoryName: 'Carpentry & Decor',
  categoryIcon: Icons.carpenter,
  location: 'Kumasi, Ashanti Region',
  status: JobStatus.open,
  isImmediate: true,
  description:
      'Need a professional carpenter to install modern, high-gloss kitchen '
      'cabinets. The space is roughly 4×3 meters. I already have the materials '
      'delivered, just need expert assembly and precision fitting. Focus on '
      'soft-close hinges and seamless handles.',
  photoUrls: const [],
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
    try {
      final jobService = ref.watch(jobServiceProvider);
      final data = await jobService.getJob(jobId);
      return _parseJobDetail(data);
    } catch (_) {
      // Fallback to mock during development / if endpoint not ready
      return _mockJobDetail;
    }
  }

  /// Parse API response into [JobDetail].
  JobDetail _parseJobDetail(Map<String, dynamic> data) {
    final status = _parseJobStatus(data['status'] as String? ?? 'pending');
    final bidsData = data['bids'] as List<dynamic>? ?? [];
    final categoryName =
        (data['category'] as Map<String, dynamic>?)?['name'] as String? ?? '';

    // The backend stores title + description merged as "title\n\ndescription".
    // Split them apart for display.
    final rawDescription = data['description'] as String? ?? '';
    final splitIndex = rawDescription.indexOf('\n\n');
    final title =
        splitIndex > 0 ? rawDescription.substring(0, splitIndex) : rawDescription;
    final description =
        splitIndex > 0 ? rawDescription.substring(splitIndex + 2) : '';

    return JobDetail(
      id: data['id'] as String? ?? '',
      title: title,
      categoryName: categoryName,
      categoryIcon: _categoryIcon(categoryName),
      location: data['addressText'] as String? ?? '',
      status: status,
      isImmediate: data['scheduledFor'] == null,
      scheduledFor: data['scheduledFor'] != null
          ? DateTime.tryParse(data['scheduledFor'] as String)
          : null,
      description: description,
      photoUrls: (data['photos'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      bids: BidSummary(
        count: bidsData.length,
        avatarColors: const [Color(0xFF5D4037), Color(0xFF795548), Color(0xFF607D8B)],
      ),
      timeline: _buildTimeline(status),
    );
  }

  static IconData _categoryIcon(String categoryName) {
    final lower = categoryName.toLowerCase();
    if (lower.contains('plumb')) return Icons.plumbing;
    if (lower.contains('electr')) return Icons.electrical_services;
    if (lower.contains('carpen') || lower.contains('wood')) return Icons.carpenter;
    if (lower.contains('paint')) return Icons.format_paint;
    if (lower.contains('clean')) return Icons.cleaning_services;
    if (lower.contains('tow') || lower.contains('car')) return Icons.car_repair;
    if (lower.contains('repair')) return Icons.build_rounded;
    if (lower.contains('delivery') || lower.contains('package')) return Icons.local_shipping;
    if (lower.contains('tailor') || lower.contains('fashion') || lower.contains('dress')) return Icons.checkroom;
    return Icons.handyman_rounded;
  }

  static JobStatus _parseJobStatus(String status) {
    return switch (status) {
      'queued'                 => JobStatus.queued,
      'open'                   => JobStatus.open,
      'confirmed'              => JobStatus.confirmed,
      'en_route'               => JobStatus.enRoute,
      'arrived'                => JobStatus.arrived,
      'in_progress'            => JobStatus.inProgress,
      'artisan_marked_complete' => JobStatus.artisanMarkedComplete,
      'completed'              => JobStatus.completed,
      'cancelled'              => JobStatus.cancelled,
      _                        => JobStatus.open,
    };
  }

  static List<TimelineStep> _buildTimeline(JobStatus status) {
    // Skip cancelled — it's a terminal state shown via the status badge.
    if (status == JobStatus.cancelled) {
      return const [
        TimelineStep(
          title: 'Cancelled',
          status: TimelineStepStatus.active,
          badgeLabel: 'CANCELLED',
          description: 'This job request has been cancelled.',
        ),
      ];
    }

    final steps = <TimelineStep>[];
    final statusIndex = JobStatus.values.indexOf(status);

    final allSteps = [
      (JobStatus.queued, 'Request Posted', 'Your service request was posted to the marketplace.'),
      (JobStatus.open, 'Awaiting Bids', 'Artisans in your area are reviewing your request.'),
      (JobStatus.confirmed, 'Artisan Confirmed', 'An artisan has been assigned to your job.'),
      (JobStatus.enRoute, 'En Route', 'The artisan is on their way to your location.'),
      (JobStatus.arrived, 'Arrived', 'The artisan has arrived at your location.'),
      (JobStatus.inProgress, 'In Progress', 'Work is underway.'),
      (JobStatus.artisanMarkedComplete, 'Awaiting Confirmation', 'The artisan has marked the job complete. Please confirm.'),
      (JobStatus.completed, 'Completed', 'The job has been completed successfully.'),
    ];

    for (final (stepStatus, title, desc) in allSteps) {
      final stepIndex = JobStatus.values.indexOf(stepStatus);
      final TimelineStepStatus tss;
      if (stepIndex < statusIndex) {
        tss = TimelineStepStatus.completed;
      } else if (stepIndex == statusIndex) {
        tss = TimelineStepStatus.active;
      } else {
        tss = TimelineStepStatus.pending;
      }
      steps.add(TimelineStep(
        title: title,
        status: tss,
        badgeLabel: tss == TimelineStepStatus.active ? 'CURRENT' : null,
        description: desc,
      ));
    }
    return steps;
  }
}
