/// DTOs for the regions endpoint.
/// Matches the contract in `docs/region-mobile-handoff.md` (GET /v1/regions).

/// An active platform region a provider can call home.
///
/// During the Ashanti pilot the list returns exactly one region, but the
/// shape supports N regions without a rework. Send [id] back as `regionId`
/// on `POST /auth/register`; [code] is a stable slug handy as a widget key,
/// not for sending.
class Region {
  const Region({
    required this.id,
    required this.name,
    required this.code,
  });

  factory Region.fromJson(Map<String, dynamic> json) {
    return Region(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String? ?? '',
    );
  }

  final String id; // UUID — sent as regionId on register
  final String name; // display label for the picker (e.g. "Ashanti")
  final String code; // stable slug (e.g. "ashanti")
}
