/// Environment-aware API configuration.
class ApiConfig {
  const ApiConfig({required this.baseUrl});

  /// Reads the base URL from a compile-time `--dart-define=API_BASE_URL=...`.
  /// Falls back to the Render-hosted staging server.
  factory ApiConfig.fromEnvironment() {
    const url = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://myshop-api-2hy2.onrender.com/v1',
    );
    return const ApiConfig(baseUrl: url);
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
