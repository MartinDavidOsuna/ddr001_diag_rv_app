import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({required this.environment, required this.apiBaseUrl});

  static const developmentFallback = 'http://192.168.1.111:3000/api/v1';
  static const rvOnly = true;
  static bool isInspectionTypeEnabled(String type) => !rvOnly || type == 'a';

  final String environment;
  final Uri apiBaseUrl;

  bool get isDevelopment => environment == 'development';

  factory AppConfig.fromEnvironment({
    String? environmentOverride,
    String? apiBaseUrlOverride,
    bool debugMode = kDebugMode,
  }) {
    final environment =
        (environmentOverride ??
                const String.fromEnvironment(
                  'APP_ENV',
                  defaultValue: 'development',
                ))
            .trim()
            .toLowerCase();
    var raw =
        (apiBaseUrlOverride ?? const String.fromEnvironment('API_BASE_URL'))
            .trim();
    if (raw.isEmpty && debugMode && environment == 'development') {
      raw = developmentFallback;
    }
    if (raw.isEmpty) {
      throw StateError(
        'API_BASE_URL es obligatorio fuera del entorno de desarrollo debug.',
      );
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw StateError('API_BASE_URL no es una URL válida.');
    }
    if (!debugMode && uri.scheme != 'https') {
      throw StateError('API_BASE_URL debe usar HTTPS en release.');
    }
    return AppConfig(environment: environment, apiBaseUrl: uri);
  }
}
