/// A service job request created by a client for an artisan.
///
/// Status flow:
///   open → queued → confirmed → artisan_en_route → arrived →
///   in_progress → artisan_marked_complete → completed
///   (can be cancelled at most stages)
class Job {
  const Job({
    required this.id,
    required this.status,
    required this.categoryId,
    required this.description,
    required this.latitude,
    required this.longitude,
    this.categoryName,
    this.addressText,
    this.photos = const [],
    this.scheduledFor,
    this.clientName,
    this.clientPhone,
    this.clientPhotoUrl,
    this.agreedPricePesewas,
    this.shareToken,
    this.artisansNotified,
    this.createdAt,
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['jobId'] as String? ?? json['id'] as String,
      status: JobStatus.fromString(json['status'] as String),
      categoryId: json['categoryId'] as String? ?? '',
      categoryName: json['categoryName'] as String?,
      description: json['description'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      addressText: json['addressText'] as String?,
      photos: (json['photos'] as List<dynamic>?)?.cast<String>() ?? const [],
      scheduledFor: json['scheduledFor'] as String?,
      clientName: json['clientName'] as String?,
      clientPhone: json['clientPhone'] as String?,
      clientPhotoUrl: json['clientPhotoUrl'] as String?,
      agreedPricePesewas: json['agreedPricePesewas'] as int?,
      shareToken: json['shareToken'] as String?,
      artisansNotified: json['artisansNotified'] as int?,
      createdAt: json['createdAt'] as String?,
    );
  }

  final String id;
  final JobStatus status;
  final String categoryId;
  final String? categoryName;
  final String description;
  final double latitude;
  final double longitude;
  final String? addressText;
  final List<String> photos;
  final String? scheduledFor;
  final String? clientName;
  final String? clientPhone;
  final String? clientPhotoUrl;
  final int? agreedPricePesewas;
  final String? shareToken;
  final int? artisansNotified;
  final String? createdAt;

  bool get isOpen => status == JobStatus.open;
  bool get isActive => status.isActive;
  bool get isScheduled => scheduledFor != null;

  Job copyWith({
    String? id,
    JobStatus? status,
    String? categoryId,
    String? categoryName,
    String? description,
    double? latitude,
    double? longitude,
    String? addressText,
    List<String>? photos,
    String? scheduledFor,
    String? clientName,
    String? clientPhone,
    String? clientPhotoUrl,
    int? agreedPricePesewas,
    String? shareToken,
    int? artisansNotified,
    String? createdAt,
  }) {
    return Job(
      id: id ?? this.id,
      status: status ?? this.status,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      addressText: addressText ?? this.addressText,
      photos: photos ?? this.photos,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      clientName: clientName ?? this.clientName,
      clientPhone: clientPhone ?? this.clientPhone,
      clientPhotoUrl: clientPhotoUrl ?? this.clientPhotoUrl,
      agreedPricePesewas: agreedPricePesewas ?? this.agreedPricePesewas,
      shareToken: shareToken ?? this.shareToken,
      artisansNotified: artisansNotified ?? this.artisansNotified,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Job status flow matching the backend enum.
enum JobStatus {
  open,
  queued,
  confirmed,
  artisanEnRoute,
  arrived,
  inProgress,
  artisanMarkedComplete,
  completed,
  cancelled;

  /// Parse a snake_case string from the backend.
  static JobStatus fromString(String value) {
    switch (value) {
      case 'open':
        return JobStatus.open;
      case 'queued':
        return JobStatus.queued;
      case 'confirmed':
        return JobStatus.confirmed;
      case 'artisan_en_route':
        return JobStatus.artisanEnRoute;
      case 'arrived':
        return JobStatus.arrived;
      case 'in_progress':
        return JobStatus.inProgress;
      case 'artisan_marked_complete':
        return JobStatus.artisanMarkedComplete;
      case 'completed':
        return JobStatus.completed;
      case 'cancelled':
        return JobStatus.cancelled;
      default:
        return JobStatus.open;
    }
  }

  /// Convert to the snake_case string the backend expects.
  String toJson() {
    switch (this) {
      case JobStatus.artisanEnRoute:
        return 'artisan_en_route';
      case JobStatus.inProgress:
        return 'in_progress';
      case JobStatus.artisanMarkedComplete:
        return 'artisan_marked_complete';
      default:
        return name;
    }
  }

  bool get isActive =>
      this == confirmed ||
      this == artisanEnRoute ||
      this == arrived ||
      this == inProgress;
}
