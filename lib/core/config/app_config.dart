import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({required this.environment, required this.apiBaseUrl});

  static const productionBaseUrl = 'http://cifra.aquafim.com:3002/api/v1';
  static const supportedEnvironments = {
    'development',
    'test',
    'staging',
    'production',
  };
  static const rvOnly = true;
  static const appUpdatesEnabled = false;
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
    if (!supportedEnvironments.contains(environment)) {
      throw StateError('APP_ENV no corresponde a un ambiente válido.');
    }
    final raw =
        (apiBaseUrlOverride ?? const String.fromEnvironment('API_BASE_URL'))
            .trim();
    if (raw.isEmpty) {
      throw StateError('Falta la configuración del servicio.');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw StateError('API_BASE_URL no es una URL válida.');
    }
    final isApprovedProductionHttp =
        environment == 'production' &&
        uri.scheme == 'http' &&
        uri.host == 'cifra.aquafim.com' &&
        uri.port == 3002 &&
        uri.path == '/api/v1' &&
        !uri.hasQuery &&
        !uri.hasFragment;
    if (uri.scheme != 'https' && !isApprovedProductionHttp) {
      throw StateError(
        'La conexión configurada no cumple la política de seguridad.',
      );
    }
    return AppConfig(environment: environment, apiBaseUrl: uri);
  }
}
