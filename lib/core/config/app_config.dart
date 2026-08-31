import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig({required this.environment, required this.apiBaseUrl});

  static const productionBaseUrl = 'http://cifra.aquafim.com:3002/api/v1';
  static const supportedEnvironments = {
    'development',
    'qa',
    'test',
    'staging',
    'production',
  };
  static const qaPackageName = 'com.aquafim.ddr001diag.qa';
  static const rvOnly = true;
  static const appUpdatesEnabled = false;
  static bool isInspectionTypeEnabled(String type) => !rvOnly || type == 'a';

  final String environment;
  final Uri apiBaseUrl;

  bool get isDevelopment => environment == 'development';

  void validateRuntimePackage(String packageName) {
    final isQaPackage = packageName == qaPackageName;
    if ((environment == 'qa') != isQaPackage) {
      throw StateError(
        'El package y APP_ENV no corresponden al mismo ambiente.',
      );
    }
  }

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
    final configuredUrl =
        (apiBaseUrlOverride ?? const String.fromEnvironment('API_BASE_URL'))
            .trim();
    final raw = configuredUrl.isEmpty && environment == 'production'
        ? productionBaseUrl
        : configuredUrl;
    if (raw.isEmpty) {
      throw StateError('Falta la configuración del servicio.');
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('API_BASE_URL no es una URL válida.');
    }
    final host = uri.host.toLowerCase();
    final isProductionHost =
        host == 'cifra.aquafim.com' || host.endsWith('.cifra.aquafim.com');
    final isLoopback = host == '127.0.0.1' || host == 'localhost';
    final hasApiPath = uri.path == '/api/v1';
    if (environment == 'qa') {
      if (!isLoopback ||
          !hasApiPath ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw StateError('La build QA sólo permite la API TEST local.');
      }
      return AppConfig(environment: environment, apiBaseUrl: uri);
    }
    if (environment == 'test') {
      final isTestDomain = host.endsWith('.test') || host.endsWith('.invalid');
      if ((!isLoopback && !isTestDomain) ||
          !hasApiPath ||
          (isLoopback && uri.scheme != 'http') ||
          (!isLoopback && uri.scheme != 'https')) {
        throw StateError('La build TEST sólo permite endpoints de prueba.');
      }
      return AppConfig(environment: environment, apiBaseUrl: uri);
    }
    if (isProductionHost && environment != 'production') {
      throw StateError('Un ambiente no productivo no puede usar producción.');
    }
    if (environment == 'production' && isLoopback) {
      throw StateError('Producción no puede usar un endpoint local.');
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
