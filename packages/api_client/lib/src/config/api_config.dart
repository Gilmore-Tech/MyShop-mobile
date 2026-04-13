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
}
