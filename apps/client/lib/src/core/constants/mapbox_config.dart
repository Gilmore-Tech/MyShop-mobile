class MapboxConfig {
  const MapboxConfig._();

  static const String accessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue:
        'pk.eyJ1IjoiZ2lsbW9yZSIsImEiOiJjbW5sMGx3dXcweXU5MnBxdHdodW5maDBwIn0.Lke90nHHdkavw3XOTENjQg',
  );

  static const String styleUrl = String.fromEnvironment(
    'MAPBOX_STYLE_URL',
    defaultValue: 'mapbox://styles/gilmore/cmnl0y49000br01s7f9cd95jy',
  );

  /// Default map center — Kumasi, Ashanti Region.
  static const double defaultLat = 6.6885;
  static const double defaultLng = -1.6244;
}
