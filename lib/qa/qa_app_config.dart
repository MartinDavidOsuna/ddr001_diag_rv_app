import '../core/config/app_config.dart';

const qaNoNetworkBaseUrl = 'https://ddr001-rv-qa.invalid/api/v1';

class QaAppConfig {
  QaAppConfig({Uri? apiBaseUrl})
    : apiBaseUrl = apiBaseUrl ?? Uri.parse(qaNoNetworkBaseUrl);

  final Uri apiBaseUrl;
  final String environment = 'qa';
  final bool syncEnabled = false;
  final bool fixtureMode = true;
  final String buildLabel = 'QA · NO PRODUCCIÓN';

  bool get isQa => true;
  bool get allowsProductionNetwork => false;

  AppConfig get apiClientConfig =>
      AppConfig(environment: environment, apiBaseUrl: apiBaseUrl);
}

QaAppConfig createQaAppConfig() => QaAppConfig();
