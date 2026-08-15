/// Earnings models matching the new backend split:
///   - GET /v1/payments/earnings/today-card  → [EarningsTodayCard]
///   - GET /v1/payments/earnings/summary     → [EarningsSummary]
///   - GET /v1/payments/earnings/report      → [EarningsReport]
///
/// All money values are int pesewas (100 pesewas = ₵1). All ISO timestamps
/// are UTC.

/// Selected period for the summary + preset-mode report endpoints.
enum EarningsPeriod {
  today,
  week,
  month;

  String get wire => name; // 'today' | 'week' | 'month'

  static EarningsPeriod parse(String? raw) {
    switch (raw) {
      case 'today':
        return EarningsPeriod.today;
      case 'week':
        return EarningsPeriod.week;
      case 'month':
        return EarningsPeriod.month;
    }
    return EarningsPeriod.week;
  }
}

/// Time-bucket size for the report's `series[]`.
enum EarningsGranularity {
  day,
  week,
  month;

  String get wire => name;

  static EarningsGranularity parse(String? raw) {
    switch (raw) {
      case 'day':
        return EarningsGranularity.day;
      case 'week':
        return EarningsGranularity.week;
      case 'month':
        return EarningsGranularity.month;
    }
    return EarningsGranularity.day;
  }
}

/// Active role passed via `?role=…`. The mobile should always pass this
/// explicitly so a future second profile doesn't leak earnings across roles.
enum EarningsRole {
  driver,
  artisan;

  String get wire => name;

  static EarningsRole parse(String? raw) =>
      raw == 'artisan' ? EarningsRole.artisan : EarningsRole.driver;
}

/// Backend error codes the earnings endpoints can return.
class EarningsErrorCodes {
  EarningsErrorCodes._();

  static const roleNotResolved = 'ROLE_NOT_RESOLVED';
  static const providerNotFound = 'PROVIDER_NOT_FOUND';
  static const rangeAmbiguous = 'EARNINGS_RANGE_AMBIGUOUS';
  static const rangeInvalid = 'EARNINGS_RANGE_INVALID';
  static const rangeTooLarge = 'EARNINGS_RANGE_TOO_LARGE';
}

/// Server-authored authority for the provider payout call-to-action.
///
/// This contract is deliberately fail-closed. Older backend responses, an
/// unknown future mode, or malformed JSON all resolve to [unavailable]; the
/// mobile must never infer permission to move money from a positive balance.
enum PayoutCapabilityMode {
  automaticExact,
  manualAggregate,
  unavailable;

  static PayoutCapabilityMode parse(String? raw) {
    switch (raw) {
      case 'automatic_exact':
        return PayoutCapabilityMode.automaticExact;
      case 'manual_aggregate':
        return PayoutCapabilityMode.manualAggregate;
      default:
        return PayoutCapabilityMode.unavailable;
    }
  }
}

enum PayoutCapabilityReason {
  payoutInProgress,
  automaticPayoutActive,
  manualPayoutAvailable,
  noAvailableBalance,
  cashCommissionCoversBalance,
  payoutRailUnavailable,
  unknown;

  static PayoutCapabilityReason parse(String? raw) {
    switch (raw) {
      case 'PAYOUT_IN_PROGRESS':
        return PayoutCapabilityReason.payoutInProgress;
      case 'AUTOMATIC_PAYOUT_ACTIVE':
        return PayoutCapabilityReason.automaticPayoutActive;
      case 'MANUAL_PAYOUT_AVAILABLE':
        return PayoutCapabilityReason.manualPayoutAvailable;
      case 'NO_AVAILABLE_BALANCE':
        return PayoutCapabilityReason.noAvailableBalance;
      case 'CASH_COMMISSION_COVERS_BALANCE':
        return PayoutCapabilityReason.cashCommissionCoversBalance;
      case 'PAYOUT_RAIL_UNAVAILABLE':
        return PayoutCapabilityReason.payoutRailUnavailable;
      default:
        return PayoutCapabilityReason.unknown;
    }
  }
}

class PayoutCapability {
  const PayoutCapability({
    required this.mode,
    required this.canRequest,
    required this.reason,
    this.rawReasonCode,
  });

  const PayoutCapability.unavailable()
      : mode = PayoutCapabilityMode.unavailable,
        canRequest = false,
        reason = PayoutCapabilityReason.unknown,
        rawReasonCode = null;

  factory PayoutCapability.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const PayoutCapability.unavailable();
    }

    final modeValue = raw['mode'];
    final reasonValue = raw['reasonCode'];
    final mode =
        PayoutCapabilityMode.parse(modeValue is String ? modeValue : null);
    final rawReason = reasonValue is String ? reasonValue : null;
    final reason = PayoutCapabilityReason.parse(rawReason);
    final canRequest = mode == PayoutCapabilityMode.manualAggregate &&
        raw['canRequest'] == true &&
        reason == PayoutCapabilityReason.manualPayoutAvailable;

    return PayoutCapability(
      mode: mode,
      canRequest: canRequest,
      reason: reason,
      rawReasonCode: rawReason,
    );
  }

  final PayoutCapabilityMode mode;
  final bool canRequest;
  final PayoutCapabilityReason reason;

  /// Retained for diagnostics only. UI authority is always derived from the
  /// parsed enum fields above.
  final String? rawReasonCode;
}

/// Server-authored primary action for the provider earnings balance.
///
/// This supersedes [PayoutCapability] when the `primaryAction` key is present
/// in an earnings-summary response. The parser is deliberately strict:
/// malformed or future action values become [unsupported] and must never fall
/// back to legacy payout authority. Legacy fallback is allowed only when an
/// older backend omits the `primaryAction` key entirely.
enum EarningsPrimaryActionKind {
  requestWithdrawal,
  payRemainingCommission,
  payoutInProgress,
  setupPayoutMethod,
  reconciliationRequired,
  none,
  unsupported;

  static EarningsPrimaryActionKind parse(String raw) {
    return switch (raw) {
      'request_withdrawal' => EarningsPrimaryActionKind.requestWithdrawal,
      'pay_remaining_commission' =>
        EarningsPrimaryActionKind.payRemainingCommission,
      'payout_in_progress' => EarningsPrimaryActionKind.payoutInProgress,
      'setup_payout_method' => EarningsPrimaryActionKind.setupPayoutMethod,
      'reconciliation_required' =>
        EarningsPrimaryActionKind.reconciliationRequired,
      'none' => EarningsPrimaryActionKind.none,
      _ => EarningsPrimaryActionKind.unsupported,
    };
  }
}

class EarningsPrimaryAction {
  const EarningsPrimaryAction({
    required this.kind,
    required this.amountPesewas,
    required this.reasonCode,
    required this.rawKind,
  });

  const EarningsPrimaryAction.unsupported({this.rawKind})
      : kind = EarningsPrimaryActionKind.unsupported,
        amountPesewas = 0,
        reasonCode = 'UNSUPPORTED_PRIMARY_ACTION';

  factory EarningsPrimaryAction.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return const EarningsPrimaryAction.unsupported();
    }

    final rawKind = raw['kind'];
    final rawAmount = raw['amountPesewas'];
    final rawReason = raw['reasonCode'];
    if (rawKind is! String ||
        rawKind.trim().isEmpty ||
        rawAmount is! int ||
        rawAmount < 0 ||
        rawAmount > _maxSafeJsonInteger ||
        rawReason is! String ||
        rawReason.trim().isEmpty) {
      return EarningsPrimaryAction.unsupported(
        rawKind: rawKind is String ? rawKind : null,
      );
    }

    final kind = EarningsPrimaryActionKind.parse(rawKind);
    if (kind == EarningsPrimaryActionKind.unsupported) {
      return EarningsPrimaryAction.unsupported(rawKind: rawKind);
    }

    return EarningsPrimaryAction(
      kind: kind,
      amountPesewas: rawAmount,
      reasonCode: rawReason,
      rawKind: rawKind,
    );
  }

  final EarningsPrimaryActionKind kind;
  final int amountPesewas;
  final String reasonCode;

  /// Retained for diagnostics. UI and money-moving authority use [kind].
  final String? rawKind;

  bool get isSupported => kind != EarningsPrimaryActionKind.unsupported;
}

class EarningsPrimaryActionReasonCodes {
  EarningsPrimaryActionReasonCodes._();

  static const manualWithdrawalAvailable = 'MANUAL_WITHDRAWAL_AVAILABLE';
  static const outstandingDeductions = 'OUTSTANDING_DEDUCTIONS';
  static const payoutDestinationRequired = 'PAYOUT_DESTINATION_REQUIRED';
  static const reconciliationRequired = 'RECONCILIATION_REQUIRED';
  static const payoutInProgress = 'PAYOUT_IN_PROGRESS';
  static const holdActive = 'HOLD_ACTIVE';
  static const belowMinimum = 'BELOW_MINIMUM';
  static const noWithdrawableBalance = 'NO_WITHDRAWABLE_BALANCE';
  static const automaticPayoutActive = 'AUTOMATIC_PAYOUT_ACTIVE';
}

// ────────────────────────────────────────────────────────────────────────────
// Today-card — homepage "Today's earnings"
// ────────────────────────────────────────────────────────────────────────────

/// Driver/artisan homepage card. Mirrors `GET /v1/payments/earnings/today-card`.
///
/// `bookingsCount` is the role-agnostic name for what the backend returns as
/// either `tripsCount` (driver) or `jobsCount` (artisan).
class EarningsTodayCard {
  const EarningsTodayCard({
    required this.role,
    required this.date,
    required this.bookingsCount,
    required this.hoursWorkedMinutes,
    required this.tipsEarnedPesewas,
    required this.grossEarningsPesewas,
    required this.commissionPesewas,
    required this.netEarningsPesewas,
  });

  factory EarningsTodayCard.fromJson(Map<String, dynamic> json) {
    final role = EarningsRole.parse(json['role'] as String?);
    final count = (json['tripsCount'] ?? json['jobsCount'] ?? 0) as num;
    final net = (json['netEarningsPesewas'] as num?)?.toInt() ?? 0;
    final commission = (json['commissionPesewas'] as num?)?.toInt() ?? 0;
    // Older builds didn't return gross — back-compute from net + commission
    // so an in-flight backend rollout doesn't blank the headline.
    final gross =
        (json['grossEarningsPesewas'] as num?)?.toInt() ?? (net + commission);
    return EarningsTodayCard(
      role: role,
      date: (json['date'] as String?) ?? '',
      bookingsCount: count.toInt(),
      hoursWorkedMinutes: (json['hoursWorkedMinutes'] as num?)?.toInt() ?? 0,
      tipsEarnedPesewas: (json['tipsEarnedPesewas'] as num?)?.toInt() ?? 0,
      grossEarningsPesewas: gross,
      commissionPesewas: commission,
      netEarningsPesewas: net,
    );
  }

  static EarningsTodayCard empty(EarningsRole role) => EarningsTodayCard(
        role: role,
        date: '',
        bookingsCount: 0,
        hoursWorkedMinutes: 0,
        tipsEarnedPesewas: 0,
        grossEarningsPesewas: 0,
        commissionPesewas: 0,
        netEarningsPesewas: 0,
      );

  final EarningsRole role;

  /// `YYYY-MM-DD` in UTC (Ghana = UTC+0).
  final String date;

  /// `tripsCount` for drivers, `jobsCount` for artisans.
  final int bookingsCount;

  /// Active trip/job time only — does NOT include online idle time.
  final int hoursWorkedMinutes;

  final int tipsEarnedPesewas;

  /// Total fare across cash + in-app rides today, before commission.
  /// Drives the headline figure on the home dashboard card.
  final int grossEarningsPesewas;

  /// Platform commission recorded across today's bookings.
  /// next to gross.
  final int commissionPesewas;

  /// Provider take-home after effective commission, across cash and in-app
  /// bookings. Client-funded promos do not reduce this value and provider
  /// commission-relief campaigns increase it. This is earnings history, not
  /// necessarily the amount of a platform-to-provider transfer.
  final int netEarningsPesewas;

  /// Backward-compatible name used by existing home/profile widgets. The
  /// backend's authoritative provider-earnings field must win over a mobile
  /// reconstruction so commission relief is never understated.
  int get effectiveEarningsPesewas =>
      netEarningsPesewas < 0 ? 0 : netEarningsPesewas;
}

// ────────────────────────────────────────────────────────────────────────────
// Summary — earnings tab top card
// ────────────────────────────────────────────────────────────────────────────

/// One bucket of the summary's gap-filled series. Each entry is a single day
/// when `granularity = day` (the only value backend returns for presets).
class EarningsSummaryPoint {
  const EarningsSummaryPoint({
    required this.bucketStart,
    required this.netPesewas,
  });

  factory EarningsSummaryPoint.fromJson(Map<String, dynamic> json) {
    return EarningsSummaryPoint(
      bucketStart:
          DateTime.tryParse(json['bucketStart'] as String? ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      netPesewas: (json['netPesewas'] as num?)?.toInt() ?? 0,
    );
  }

  final DateTime bucketStart;
  final int netPesewas;
}

enum EarningsReconciliationReason {
  none,
  withdrawalDestinationReview,
  withdrawalTransferFailed,
  withdrawalTransferReversed,
  withdrawalFinalizationReview,
  financialReconciliationRequired,
  unknown;

  static EarningsReconciliationReason parse(Object? raw) {
    return switch (raw) {
      null => EarningsReconciliationReason.none,
      'WITHDRAWAL_DESTINATION_REVIEW' =>
        EarningsReconciliationReason.withdrawalDestinationReview,
      'WITHDRAWAL_TRANSFER_FAILED' =>
        EarningsReconciliationReason.withdrawalTransferFailed,
      'WITHDRAWAL_TRANSFER_REVERSED' =>
        EarningsReconciliationReason.withdrawalTransferReversed,
      'WITHDRAWAL_FINALIZATION_REVIEW' =>
        EarningsReconciliationReason.withdrawalFinalizationReview,
      'FINANCIAL_RECONCILIATION_REQUIRED' =>
        EarningsReconciliationReason.financialReconciliationRequired,
      _ => EarningsReconciliationReason.unknown,
    };
  }
}

/// Mirrors `GET /v1/payments/earnings/summary`.
class EarningsSummary {
  const EarningsSummary({
    required this.role,
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.availableBalancePesewas,
    required this.todayAvailableBalancePesewas,
    required this.weeklyAvailableBalancePesewas,
    required this.netEarningsPesewas,
    required this.tipsEarnedPesewas,
    required this.paidOutPesewas,
    required this.cashCommissionOwedPesewas,
    required this.pendingPayoutsPesewas,
    required this.series,
    required this.granularity,
    this.payoutCapability = const PayoutCapability.unavailable(),
    bool? hasValidCashCommissionOwedPesewas,
    bool? hasValidPendingPayoutsPesewas,
    this.availableBeforeDeductionsPesewas,
    this.deductionsAppliedPesewas,
    this.withdrawableBalancePesewas,
    this.remainingDebtPesewas,
    this.heldBalancePesewas,
    this.reconciliationReason = EarningsReconciliationReason.none,
    this.nextPayoutEligibleAt,
    this.minimumWithdrawalPesewas,
    bool? hasBalanceBreakdownContract,
    this.hasPrimaryActionContract = false,
    this.primaryAction,
  })  : hasValidCashCommissionOwedPesewas =
            (hasValidCashCommissionOwedPesewas ?? true) &&
                cashCommissionOwedPesewas >= 0 &&
                cashCommissionOwedPesewas <= _maxSafeJsonInteger,
        hasValidPendingPayoutsPesewas =
            (hasValidPendingPayoutsPesewas ?? true) &&
                pendingPayoutsPesewas >= 0 &&
                pendingPayoutsPesewas <= _maxSafeJsonInteger,
        hasBalanceBreakdownContract = hasBalanceBreakdownContract ??
            (availableBeforeDeductionsPesewas != null ||
                deductionsAppliedPesewas != null ||
                withdrawableBalancePesewas != null ||
                remainingDebtPesewas != null ||
                heldBalancePesewas != null ||
                nextPayoutEligibleAt != null ||
                minimumWithdrawalPesewas != null);

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    return EarningsSummary(
      role: EarningsRole.parse(json['role'] as String?),
      period: EarningsPeriod.parse(json['period'] as String?),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '')?.toUtc(),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? '')?.toUtc(),
      availableBalancePesewas:
          (json['availableBalancePesewas'] as num?)?.toInt() ?? 0,
      todayAvailableBalancePesewas:
          (json['todayAvailableBalancePesewas'] as num?)?.toInt() ?? 0,
      weeklyAvailableBalancePesewas:
          (json['weeklyAvailableBalancePesewas'] as num?)?.toInt() ?? 0,
      netEarningsPesewas: (json['netEarningsPesewas'] as num?)?.toInt() ?? 0,
      tipsEarnedPesewas: (json['tipsEarnedPesewas'] as num?)?.toInt() ?? 0,
      paidOutPesewas: (json['paidOutPesewas'] as num?)?.toInt() ?? 0,
      cashCommissionOwedPesewas:
          _nonNegativeIntOrNull(json['cashCommissionOwedPesewas']) ?? 0,
      hasValidCashCommissionOwedPesewas:
          _nonNegativeIntOrNull(json['cashCommissionOwedPesewas']) != null,
      pendingPayoutsPesewas:
          _nonNegativeIntOrNull(json['pendingPayoutsPesewas']) ?? 0,
      hasValidPendingPayoutsPesewas:
          _nonNegativeIntOrNull(json['pendingPayoutsPesewas']) != null,
      payoutCapability: PayoutCapability.fromJson(json['payoutCapability']),
      availableBeforeDeductionsPesewas: _nonNegativeIntOrNull(
        json['availableBeforeDeductionsPesewas'],
      ),
      deductionsAppliedPesewas: _nonNegativeIntOrNull(
        json['deductionsAppliedPesewas'],
      ),
      withdrawableBalancePesewas: _nonNegativeIntOrNull(
        json['withdrawableBalancePesewas'],
      ),
      remainingDebtPesewas: _nonNegativeIntOrNull(json['remainingDebtPesewas']),
      heldBalancePesewas: _nonNegativeIntOrNull(json['heldBalancePesewas']),
      reconciliationReason: EarningsReconciliationReason.parse(
        json['reconciliationReasonCode'],
      ),
      nextPayoutEligibleAt: _utcDateTimeOrNull(json['nextPayoutEligibleAt']),
      minimumWithdrawalPesewas: _positiveIntOrNull(
        json['minimumWithdrawalPesewas'],
      ),
      hasBalanceBreakdownContract: _containsAnyKey(
        json,
        _balanceBreakdownContractKeys,
      ),
      hasPrimaryActionContract: json.containsKey('primaryAction'),
      primaryAction: json.containsKey('primaryAction')
          ? EarningsPrimaryAction.fromJson(json['primaryAction'])
          : null,
      series: (json['series'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(EarningsSummaryPoint.fromJson)
              .toList(growable: false) ??
          const <EarningsSummaryPoint>[],
      granularity: EarningsGranularity.parse(json['granularity'] as String?),
    );
  }

  static EarningsSummary empty(EarningsRole role, EarningsPeriod period) =>
      EarningsSummary(
        role: role,
        period: period,
        startDate: null,
        endDate: null,
        availableBalancePesewas: 0,
        todayAvailableBalancePesewas: 0,
        weeklyAvailableBalancePesewas: 0,
        netEarningsPesewas: 0,
        tipsEarnedPesewas: 0,
        paidOutPesewas: 0,
        cashCommissionOwedPesewas: 0,
        pendingPayoutsPesewas: 0,
        series: const [],
        granularity: EarningsGranularity.day,
      );

  final EarningsRole role;
  final EarningsPeriod period;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Period-agnostic visible balance. This can include retained pre-cutover
  /// funds that are not eligible for automatic payout; [payoutCapability]
  /// remains the sole authority for any money-moving action.
  final int availableBalancePesewas;

  /// Net earnings from today only — always shown alongside the period.
  final int todayAvailableBalancePesewas;

  /// Net earnings over the last 7 days.
  final int weeklyAvailableBalancePesewas;

  /// Net earnings over the **selected period** (excludes tips).
  final int netEarningsPesewas;

  /// Tips earned in the selected period. Disjoint from [netEarningsPesewas]:
  /// tips carry no commission and are disbursed directly to the provider's
  /// MoMo when the client adds them, so they never accrue to
  /// [availableBalancePesewas]. Surfaced so the dashboard's "total earned"
  /// line can read net + tips together.
  final int tipsEarnedPesewas;

  /// Money already disbursed in the selected period. Excludes cash trips.
  final int paidOutPesewas;

  /// Durable outstanding CASH_COMMISSION debt the provider owes the platform.
  /// This remains authoritative until the backend transactionally applies a
  /// remittance or clawback deduction and returns a reduced value. Mobile must
  /// not infer that an available payout balance has already offset this debt.
  final int cashCommissionOwedPesewas;

  /// Whether [cashCommissionOwedPesewas] came from an exact non-negative,
  /// JSON-safe integer. Malformed wire values render as zero for compatibility
  /// but can never authorise a money-moving action.
  final bool hasValidCashCommissionOwedPesewas;

  /// In-flight payouts (Paystack transfer queued / processing). Shown
  /// inline so the driver knows the money is on its way.
  final int pendingPayoutsPesewas;

  /// Whether [pendingPayoutsPesewas] came from an exact non-negative,
  /// JSON-safe integer. See [hasValidCashCommissionOwedPesewas].
  final bool hasValidPendingPayoutsPesewas;

  /// Released provider earnings before server-side deductions are applied.
  /// Null means the response came from an older or incomplete backend.
  final int? availableBeforeDeductionsPesewas;

  /// Deductions selected for the currently available earnings balance.
  final int? deductionsAppliedPesewas;

  /// Amount the provider can currently request from the payout rail.
  final int? withdrawableBalancePesewas;

  /// Debt still owed after the backend's authoritative deductions view.
  final int? remainingDebtPesewas;

  /// Earnings retained by the server hold policy and not yet withdrawable.
  final int? heldBalancePesewas;

  /// Sanitized reason why funds are held for financial review. Raw gateway or
  /// internal failure text is never rendered to the provider.
  final EarningsReconciliationReason reconciliationReason;

  /// Earliest known release time for held earnings. Null is valid when no
  /// held funds exist or the backend cannot provide one release timestamp.
  final DateTime? nextPayoutEligibleAt;

  /// Server-configured minimum required for a manual withdrawal. This is
  /// additive and must be present and valid before the app explains a
  /// `BELOW_MINIMUM` primary action.
  final int? minimumWithdrawalPesewas;

  /// Distinguishes a genuinely old response (all additive balance keys
  /// absent) from a partial or malformed new contract. Only the former may
  /// enter the legacy payout-capability fallback.
  final bool hasBalanceBreakdownContract;

  /// Distinguishes an old backend (key absent) from an explicit malformed or
  /// unsupported action (key present). Only the former may use legacy payout
  /// capability as a compatibility fallback.
  final bool hasPrimaryActionContract;
  final EarningsPrimaryAction? primaryAction;

  /// Server-authored payout CTA authority. Missing on older backend builds;
  /// the default is intentionally unavailable rather than inferred from the
  /// balance.
  final PayoutCapability payoutCapability;

  /// Gap-filled time series — every bucket present even with `netPesewas: 0`.
  final List<EarningsSummaryPoint> series;

  final EarningsGranularity granularity;

  /// Arithmetic difference retained for reporting compatibility only.
  ///
  /// Do not use this value to authorise a payout, calculate a commission
  /// remittance, or claim that commission debt was offset. Those transitions
  /// require a backend transaction and an updated summary.
  int get effectiveBalancePesewas =>
      availableBalancePesewas - cashCommissionOwedPesewas;

  /// Balance figure shown in the dashboard headline. Any durable commission
  /// debt takes precedence over available payout funds and is shown in full.
  int get headlineBalancePesewas => cashCommissionOwedPesewas > 0
      ? -cashCommissionOwedPesewas
      : availableBalancePesewas;

  /// True whenever durable cash-commission debt remains outstanding.
  bool get isInArrears => cashCommissionOwedPesewas > 0;

  /// True only when all additive money fields passed strict non-negative-int
  /// parsing. A partial rollout can still render the legacy summary, but it
  /// cannot authorise a withdrawal.
  bool get hasAuthoritativeBalanceBreakdown =>
      hasValidCashCommissionOwedPesewas &&
      hasValidPendingPayoutsPesewas &&
      availableBeforeDeductionsPesewas != null &&
      deductionsAppliedPesewas != null &&
      withdrawableBalancePesewas != null &&
      remainingDebtPesewas != null &&
      heldBalancePesewas != null &&
      deductionsAppliedPesewas! <= availableBeforeDeductionsPesewas! &&
      withdrawableBalancePesewas ==
          availableBeforeDeductionsPesewas! - deductionsAppliedPesewas! &&
      cashCommissionOwedPesewas >= 0 &&
      cashCommissionOwedPesewas <= _maxSafeJsonInteger &&
      cashCommissionOwedPesewas <= remainingDebtPesewas! &&
      // A balance cannot be both withdrawable and still owe residual debt.
      // Contradictory server data must never authorise a money-moving action.
      (withdrawableBalancePesewas == 0 || remainingDebtPesewas == 0);

  /// Frozen production minimum for the current manual-withdrawal contract.
  static const requiredMinimumWithdrawalPesewas = 1500;

  int get selectedPeriodEarnedPesewas => netEarningsPesewas + tipsEarnedPesewas;
}

const int _maxSafeJsonInteger = 9007199254740991;

const _balanceBreakdownContractKeys = <String>[
  'availableBeforeDeductionsPesewas',
  'deductionsAppliedPesewas',
  'withdrawableBalancePesewas',
  'remainingDebtPesewas',
  'heldBalancePesewas',
  'reconciliationReasonCode',
  'nextPayoutEligibleAt',
  'minimumWithdrawalPesewas',
];

bool _containsAnyKey(Map<String, dynamic> json, List<String> keys) =>
    keys.any(json.containsKey);

int? _nonNegativeIntOrNull(Object? raw) =>
    raw is int && raw >= 0 && raw <= _maxSafeJsonInteger ? raw : null;

int? _positiveIntOrNull(Object? raw) =>
    raw is int && raw > 0 && raw <= _maxSafeJsonInteger ? raw : null;

DateTime? _utcDateTimeOrNull(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

// ────────────────────────────────────────────────────────────────────────────
// Report — detailed report view
// ────────────────────────────────────────────────────────────────────────────

/// One bucket of the report's gap-filled series. Carries every metric so the
/// same data can drive multiple chart layers (gross + tips, net stack, etc.).
class EarningsReportPoint {
  const EarningsReportPoint({
    required this.bucketStart,
    required this.grossPesewas,
    required this.netPesewas,
    required this.commissionPesewas,
    required this.tipsPesewas,
    required this.count,
  });

  factory EarningsReportPoint.fromJson(Map<String, dynamic> json) {
    return EarningsReportPoint(
      bucketStart:
          DateTime.tryParse(json['bucketStart'] as String? ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      grossPesewas: (json['grossPesewas'] as num?)?.toInt() ?? 0,
      netPesewas: (json['netPesewas'] as num?)?.toInt() ?? 0,
      commissionPesewas: (json['commissionPesewas'] as num?)?.toInt() ?? 0,
      tipsPesewas: (json['tipsPesewas'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  final DateTime bucketStart;
  final int grossPesewas;
  final int netPesewas;
  final int commissionPesewas;
  final int tipsPesewas;
  final int count;
}

/// Mirrors `GET /v1/payments/earnings/report`.
class EarningsReport {
  const EarningsReport({
    required this.role,
    required this.startDate,
    required this.endDate,
    required this.granularity,
    required this.grossEarningsPesewas,
    required this.netEarningsPesewas,
    required this.commissionChargedPesewas,
    required this.tipsEarnedPesewas,
    required this.bookingsCompleted,
    required this.averageFarePesewas,
    required this.hoursWorkedMinutes,
    required this.trendPct,
    required this.series,
  });

  factory EarningsReport.fromJson(Map<String, dynamic> json) {
    final completed =
        (json['tripsCompleted'] ?? json['jobsCompleted'] ?? 0) as num;
    return EarningsReport(
      role: EarningsRole.parse(json['role'] as String?),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '')?.toUtc(),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? '')?.toUtc(),
      granularity: EarningsGranularity.parse(json['granularity'] as String?),
      grossEarningsPesewas:
          (json['grossEarningsPesewas'] as num?)?.toInt() ?? 0,
      netEarningsPesewas: (json['netEarningsPesewas'] as num?)?.toInt() ?? 0,
      commissionChargedPesewas:
          (json['commissionChargedPesewas'] as num?)?.toInt() ?? 0,
      tipsEarnedPesewas: (json['tipsEarnedPesewas'] as num?)?.toInt() ?? 0,
      bookingsCompleted: completed.toInt(),
      averageFarePesewas: (json['averageFarePesewas'] as num?)?.toInt() ?? 0,
      hoursWorkedMinutes: (json['hoursWorkedMinutes'] as num?)?.toInt() ?? 0,
      trendPct: (json['trendPct'] as num?)?.toDouble(),
      series: (json['series'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(EarningsReportPoint.fromJson)
              .toList(growable: false) ??
          const <EarningsReportPoint>[],
    );
  }

  static EarningsReport empty(EarningsRole role) => EarningsReport(
        role: role,
        startDate: null,
        endDate: null,
        granularity: EarningsGranularity.day,
        grossEarningsPesewas: 0,
        netEarningsPesewas: 0,
        commissionChargedPesewas: 0,
        tipsEarnedPesewas: 0,
        bookingsCompleted: 0,
        averageFarePesewas: 0,
        hoursWorkedMinutes: 0,
        trendPct: null,
        series: const [],
      );

  final EarningsRole role;
  final DateTime? startDate;
  final DateTime? endDate;
  final EarningsGranularity granularity;

  /// Gross — includes cash AND in-app trips.
  final int grossEarningsPesewas;
  final int netEarningsPesewas;
  final int commissionChargedPesewas;
  final int tipsEarnedPesewas;

  /// `tripsCompleted` for drivers, `jobsCompleted` for artisans.
  final int bookingsCompleted;

  /// Integer-rounded `gross / count`. Backend returns 0 when `count == 0`.
  final int averageFarePesewas;

  /// Active trip/job time only.
  final int hoursWorkedMinutes;

  /// Null when the previous equal-length window had zero earnings — render
  /// as `—` or hide the badge.
  final double? trendPct;

  final List<EarningsReportPoint> series;

  /// Backward-compatible alias for the authoritative provider take-home.
  /// Do not reconstruct this from gross and commission on-device: doing so
  /// can understate provider-targeted commission relief during mixed-version
  /// rollouts.
  int get effectiveEarningsPesewas =>
      netEarningsPesewas < 0 ? 0 : netEarningsPesewas;
}

// ────────────────────────────────────────────────────────────────────────────
// Report request shape
// ────────────────────────────────────────────────────────────────────────────

/// Identifies a report query — either a preset period OR a custom date range.
/// Used as the family key for the report provider so different queries cache
/// independently.
class EarningsReportQuery {
  const EarningsReportQuery.preset({
    required this.role,
    required EarningsPeriod period,
  })  : period = period,
        from = null,
        to = null,
        granularity = null;

  const EarningsReportQuery.range({
    required this.role,
    required DateTime this.from,
    required DateTime this.to,
    this.granularity,
  }) : period = null;

  final EarningsRole role;
  final EarningsPeriod? period;
  final DateTime? from;
  final DateTime? to;
  final EarningsGranularity? granularity;

  bool get isPreset => period != null;

  @override
  bool operator ==(Object other) =>
      other is EarningsReportQuery &&
      other.role == role &&
      other.period == period &&
      other.from == from &&
      other.to == to &&
      other.granularity == granularity;

  @override
  int get hashCode => Object.hash(role, period, from, to, granularity);
}

// ────────────────────────────────────────────────────────────────────────────
// Errors
// ────────────────────────────────────────────────────────────────────────────

/// Thrown by the earnings service so callers can pattern-match on the
/// backend's machine-readable error code.
class EarningsApiException implements Exception {
  const EarningsApiException({required this.code, this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'EarningsApiException($code): ${message ?? ''}';
}
