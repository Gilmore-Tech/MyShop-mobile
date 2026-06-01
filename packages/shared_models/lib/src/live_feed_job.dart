/// Anonymised snapshot of a recently created artisan job, surfaced on the
/// provider artisan home "Live Job Feed" carousel for social-proof display.
///
/// Mirrors the backend `LiveFeedJobDto`. The carousel is intentionally
/// non-interactive (no tap target) — these snapshots are read-only signals
/// that the platform is alive. By contract, this payload never includes
/// client identity, photos, or precise drop location. `latitude`/`longitude`
/// are approximate values used only for distance calculation client-side.
class LiveFeedJob {
  const LiveFeedJob({
    required this.id,
    required this.categoryName,
    required this.areaLabel,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  factory LiveFeedJob.fromJson(Map<String, dynamic> json) {
    return LiveFeedJob(
      id: json['id'] as String,
      categoryName: json['categoryName'] as String? ?? 'Service',
      areaLabel: json['areaLabel'] as String? ?? 'Kumasi area',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final String id;
  final String categoryName;
  final String areaLabel;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
}
