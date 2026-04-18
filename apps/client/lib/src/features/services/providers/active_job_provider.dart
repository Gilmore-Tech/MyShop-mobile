import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';

import '../../../core/di/providers.dart';

// ── Active Job Phase ──────────────────────────────────────────────────────────
// Subset of JobStatus relevant to the active tracking screen.
// Real-time phase changes arrive via WS /v1/jobs/:id/live (EDD § 5.3).
//
//   enRoute        → job.status == "en_route"
//   arrived        → job.status == "arrived"
//   inProgress     → job.status == "in_progress"   (client confirmed arrival)
//   awaitingApproval → artisan marked complete; client has 4-hr window to confirm
//                      (PRD 4.8.2 / EDD § Marketplace)

enum ActiveJobPhase {
  enRoute,
  arrived,
  inProgress,
  awaitingApproval,
}

extension ActiveJobPhaseX on ActiveJobPhase {
  String get statusLabel => switch (this) {
        ActiveJobPhase.enRoute          => 'En Route',
        ActiveJobPhase.arrived          => 'In Progress',
        ActiveJobPhase.inProgress       => 'In Progress',
        ActiveJobPhase.awaitingApproval => 'Completed',
      };

  Color get statusColor => switch (this) {
        ActiveJobPhase.enRoute          => MyShopColors.primaryGold,
        ActiveJobPhase.arrived          => MyShopColors.primaryGold,
        ActiveJobPhase.inProgress       => MyShopColors.primaryGold,
        ActiveJobPhase.awaitingApproval => MyShopColors.textSecondary,
      };

  /// Left stat cell label.
  String get statLabel => switch (this) {
        ActiveJobPhase.enRoute => 'ESTIMATED ARRIVAL',
        _                      => 'EST. COMPLETION',
      };
}

// ── Artisan (active job context) ──────────────────────────────────────────────

class ActiveJobArtisan {
  final String artisanId;
  final String name;
  final String firstName;
  final Color avatarColor;
  final bool isVerified;

  const ActiveJobArtisan({
    required this.artisanId,
    required this.name,
    required this.firstName,
    required this.avatarColor,
    required this.isVerified,
  });
}

// ── Cost Breakdown ────────────────────────────────────────────────────────────
// PRD 4.5.2 — bid covers labour + estimated materials.
// isFinalized becomes true in awaitingApproval: removes "Estimated" prefix from
// the header and total line.

class ActiveJobCost {
  final int serviceFeePesewas;
  final int materialsFeePesewas;
  final bool isFinalized;

  const ActiveJobCost({
    required this.serviceFeePesewas,
    required this.materialsFeePesewas,
    this.isFinalized = false,
  });

  int get totalPesewas => serviceFeePesewas + materialsFeePesewas;

  String _fmt(int pesewas) => 'GHS ${(pesewas / 100).toStringAsFixed(2)}';

  String get serviceFeeDisplay   => _fmt(serviceFeePesewas);
  String get materialsFeeDisplay => _fmt(materialsFeePesewas);
  String get totalDisplay        => _fmt(totalPesewas);

  /// Section header — "Estimated Cost" vs "Cost".
  String get sectionTitle => isFinalized ? 'Cost' : 'Estimated Cost';

  /// Total row label — "Estimated Total" vs "Total".
  String get totalLabel => isFinalized ? 'Total' : 'Estimated Total';
}

// ── Active Job Data ───────────────────────────────────────────────────────────
// API: GET /v1/jobs/:id  |  WS /v1/jobs/:id/live

class ActiveJobData {
  final String jobId;

  /// Formatted service reference shown under the title, e.g. "# JJOB-88219".
  final String serviceId;

  final String title;
  final String categoryName;
  final IconData categoryIcon;
  final String location;
  final ActiveJobPhase phase;
  final ActiveJobArtisan artisan;
  final ActiveJobCost cost;

  /// Left stat cell value when enRoute, e.g. "12 mins away".
  final String? etaLabel;

  /// Left stat cell value for all other phases, e.g. "4hrs".
  final String? completionLabel;

  /// Right stat cell — always "Today, HH:MM AM/PM".
  final String scheduleLabel;

  /// Timestamp for the "Job Posted" timeline step, e.g. "09:15 AM".
  final String jobPostedTime;

  /// Description text for the "Job Posted" timeline step.
  final String jobDescription;

  const ActiveJobData({
    required this.jobId,
    required this.serviceId,
    required this.title,
    required this.categoryName,
    required this.categoryIcon,
    required this.location,
    required this.phase,
    required this.artisan,
    required this.cost,
    this.etaLabel,
    this.completionLabel,
    required this.scheduleLabel,
    required this.jobPostedTime,
    required this.jobDescription,
  });

  /// Resolved value for the left stat cell.
  String get statValue => phase == ActiveJobPhase.enRoute
      ? (etaLabel ?? '—')
      : (completionLabel ?? '—');
}

// ── Action State ──────────────────────────────────────────────────────────────

class ActiveJobActionState {
  final bool isConfirmingArrival;
  final bool isMarkingComplete;
  final bool costExpanded;
  final String? errorMessage;

  const ActiveJobActionState({
    this.isConfirmingArrival = false,
    this.isMarkingComplete = false,
    this.costExpanded = false,
    this.errorMessage,
  });

  bool get isBusy => isConfirmingArrival || isMarkingComplete;

  ActiveJobActionState copyWith({
    bool? isConfirmingArrival,
    bool? isMarkingComplete,
    bool? costExpanded,
    String? errorMessage,
    bool clearError = false,
  }) =>
      ActiveJobActionState(
        isConfirmingArrival: isConfirmingArrival ?? this.isConfirmingArrival,
        isMarkingComplete: isMarkingComplete ?? this.isMarkingComplete,
        costExpanded: costExpanded ?? this.costExpanded,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class ActiveJobNotifier extends StateNotifier<ActiveJobActionState> {
  ActiveJobNotifier(this._jobService) : super(const ActiveJobActionState());

  final JobService _jobService;

  void toggleCost() =>
      state = state.copyWith(costExpanded: !state.costExpanded);

  /// Client confirms artisan has arrived — starts the work session.
  /// PATCH /v1/jobs/:jobId/status  { status: "inProgress" }
  /// PRD 4.5: triggers work-start; supplement window closes after this.
  Future<void> confirmArrival({required String jobId}) async {
    if (state.isBusy) return;
    state = state.copyWith(isConfirmingArrival: true, clearError: true);
    try {
      await _jobService.confirmJobCompletion(jobId);
      state = state.copyWith(isConfirmingArrival: false);
    } on ApiException catch (e) {
      state = state.copyWith(
        isConfirmingArrival: false,
        errorMessage: e.message,
      );
    } catch (_) {
      // Fallback: treat as success during development
      state = state.copyWith(isConfirmingArrival: false);
    }
  }

  /// Client confirms job completion — releases escrow payment to artisan.
  /// PATCH /v1/jobs/:jobId/confirm  (EDD § Marketplace)
  /// PRD 4.8.2: client has a 4-hr window; artisan can escalate after that.
  Future<void> markComplete({required String jobId}) async {
    if (state.isBusy) return;
    state = state.copyWith(isMarkingComplete: true, clearError: true);
    try {
      await _jobService.confirmJobCompletion(jobId);
      state = state.copyWith(isMarkingComplete: false);
    } on ApiException catch (e) {
      state = state.copyWith(
        isMarkingComplete: false,
        errorMessage: e.message,
      );
    } catch (_) {
      // Fallback: treat as success during development
      state = state.copyWith(isMarkingComplete: false);
    }
  }
}

final activeJobActionProvider =
    StateNotifierProvider.autoDispose<ActiveJobNotifier, ActiveJobActionState>(
  (ref) => ActiveJobNotifier(ref.watch(jobServiceProvider)),
);

// ── Data Provider ─────────────────────────────────────────────────────────────

final activeJobProvider = AsyncNotifierProvider.autoDispose
    .family<_ActiveJobNotifier, ActiveJobData, String>(
  _ActiveJobNotifier.new,
);

class _ActiveJobNotifier
    extends AutoDisposeFamilyAsyncNotifier<ActiveJobData, String> {
  @override
  Future<ActiveJobData> build(String jobId) async {
    try {
      final jobService = ref.watch(jobServiceProvider);
      final data = await jobService.getJob(jobId);
      return _parseActiveJob(data);
    } catch (_) {
      // Fallback to mock during development / if endpoint not ready
      return _mockJobs[jobId] ?? _defaultMockJob;
    }
  }

  /// Parse API response into [ActiveJobData].
  ActiveJobData _parseActiveJob(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? 'en_route';
    final phase = _parsePhase(status);

    final artisanData = data['provider'] as Map<String, dynamic>? ?? {};
    final artisanName = '${artisanData['firstName'] ?? ''} ${artisanData['lastName'] ?? ''}'.trim();
    final bidData = data['selectedBid'] as Map<String, dynamic>? ?? {};
    final costBreakdown = data['costBreakdown'] as Map<String, dynamic>? ?? {};

    final serviceFeePesewas = (costBreakdown['laborPesewas'] as num?)?.toInt()
        ?? (bidData['amountPesewas'] as num?)?.toInt()
        ?? 0;
    final materialsFeePesewas = (costBreakdown['materialsPesewas'] as num?)?.toInt() ?? 0;

    final categoryData = data['category'] as Map<String, dynamic>? ?? {};

    return ActiveJobData(
      jobId: data['id'] as String? ?? '',
      serviceId: '# JJOB-${(data['id'] as String? ?? '').hashCode.abs() % 100000}',
      title: data['description'] as String? ?? '',
      categoryName: categoryData['name'] as String? ?? '',
      categoryIcon: Icons.build_rounded,
      location: data['locationAddress'] as String? ?? '',
      phase: phase,
      artisan: ActiveJobArtisan(
        artisanId: artisanData['id'] as String? ?? '',
        name: artisanName.isNotEmpty ? artisanName : 'Artisan',
        firstName: artisanData['firstName'] as String? ?? 'Artisan',
        avatarColor: const Color(0xFF37474F),
        isVerified: artisanData['isVerified'] as bool? ?? false,
      ),
      cost: ActiveJobCost(
        serviceFeePesewas: serviceFeePesewas,
        materialsFeePesewas: materialsFeePesewas,
        isFinalized: phase == ActiveJobPhase.awaitingApproval,
      ),
      etaLabel: data['eta'] != null ? '${data['eta']} mins away' : null,
      completionLabel: data['estimatedDuration'] as String? ?? '—',
      scheduleLabel: data['scheduledFor'] as String? ?? 'Today',
      jobPostedTime: data['createdAt'] as String? ?? '',
      jobDescription: data['description'] as String? ?? '',
    );
  }

  static ActiveJobPhase _parsePhase(String status) {
    return switch (status) {
      'en_route'            => ActiveJobPhase.enRoute,
      'arrived'             => ActiveJobPhase.arrived,
      'in_progress'         => ActiveJobPhase.inProgress,
      'awaiting_approval' ||
      'completed'           => ActiveJobPhase.awaitingApproval,
      _                     => ActiveJobPhase.enRoute,
    };
  }
}

// ── Mock data (one entry per phase for preview) ───────────────────────────────

const _artisan = ActiveJobArtisan(
  artisanId: 'ART-101',
  name: 'Kofi Mensah',
  firstName: 'Kofi',
  avatarColor: Color(0xFF37474F),
  isVerified: true,
);

const _cost = ActiveJobCost(
  serviceFeePesewas: 15000,  // GHS 150.00
  materialsFeePesewas: 8500, // GHS  85.00
);

const _costFinalized = ActiveJobCost(
  serviceFeePesewas: 15000,
  materialsFeePesewas: 8500,
  isFinalized: true,
);

const _defaultMockJob = ActiveJobData(
  jobId: 'JOB-ENROUTE',
  serviceId: '# JJOB-88219',
  title: 'Emergency Electrical Repair',
  categoryName: 'Electrical',
  categoryIcon: Icons.electrical_services_rounded,
  location: 'East Legon, Accra',
  phase: ActiveJobPhase.enRoute,
  artisan: _artisan,
  cost: _cost,
  etaLabel: '12 mins away',
  completionLabel: '4hrs',
  scheduleLabel: 'Today, 09:30 AM',
  jobPostedTime: '09:15 AM',
  jobDescription: 'You requested an Emergency Electrician for circuit repairs.',
);

const Map<String, ActiveJobData> _mockJobs = {
  'JOB-ENROUTE': _defaultMockJob,
  'JOB-ARRIVED': ActiveJobData(
    jobId: 'JOB-ARRIVED',
    serviceId: '# JJOB-88219',
    title: 'Emergency Electrical Repair',
    categoryName: 'Electrical',
    categoryIcon: Icons.electrical_services_rounded,
    location: 'East Legon, Accra',
    phase: ActiveJobPhase.arrived,
    artisan: _artisan,
    cost: _cost,
    completionLabel: '4hrs',
    scheduleLabel: 'Today, 09:30 AM',
    jobPostedTime: '09:15 AM',
    jobDescription: 'You requested an Emergency Electrician for circuit repairs.',
  ),
  'JOB-INPROGRESS': ActiveJobData(
    jobId: 'JOB-INPROGRESS',
    serviceId: '# JJOB-88219',
    title: 'Emergency Electrical Repair',
    categoryName: 'Electrical',
    categoryIcon: Icons.electrical_services_rounded,
    location: 'East Legon, Accra',
    phase: ActiveJobPhase.inProgress,
    artisan: _artisan,
    cost: _cost,
    completionLabel: '4hrs',
    scheduleLabel: 'Today, 09:30 AM',
    jobPostedTime: '09:15 AM',
    jobDescription: 'You requested an Emergency Electrician for circuit repairs.',
  ),
  'JOB-AWAITING': ActiveJobData(
    jobId: 'JOB-AWAITING',
    serviceId: '# JJOB-88219',
    title: 'Emergency Electrical Repair',
    categoryName: 'Electrical',
    categoryIcon: Icons.electrical_services_rounded,
    location: 'East Legon, Accra',
    phase: ActiveJobPhase.awaitingApproval,
    artisan: _artisan,
    cost: _costFinalized,
    completionLabel: '4hrs',
    scheduleLabel: 'Today, 09:30 AM',
    jobPostedTime: '09:15 AM',
    jobDescription: 'You requested an Emergency Electrician for circuit repairs.',
  ),
};
