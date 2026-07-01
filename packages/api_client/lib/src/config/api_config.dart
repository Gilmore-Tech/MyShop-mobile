/// Environment-aware API configuration.
class ApiConfig {
  const ApiConfig({required this.baseUrl});

  /// Reads the base URL from a compile-time `--dart-define=API_BASE_URL=...`.
  /// Debug/profile builds retain a local fallback for contributor ergonomics;
  /// release builds fail fast so a missing CI secret can never silently ship
  /// a store binary pointed at the wrong environment.
  factory ApiConfig.fromEnvironment() {
    const configured = String.fromEnvironment('API_BASE_URL');
    const isRelease = bool.fromEnvironment('dart.vm.product');
    if (configured.isEmpty && isRelease) {
      throw StateError(
        'API_BASE_URL is required in release builds. Use tool/build.sh.',
      );
    }
    final url = configured.isEmpty
        ? 'https://api.myshop.gilmoretechnologiesgh.com/v1'
        : configured;
    return ApiConfig(baseUrl: url);
  }

  final String baseUrl;

  /// The WebSocket base URL derived from [baseUrl].
  /// Strips the `/v1` path suffix — Socket.IO connects to the server root.
  String get wsBaseUrl {
    final uri = Uri.parse(baseUrl);
    // Strip /v1 or any path suffix — Socket.IO connects at the root
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }
}
