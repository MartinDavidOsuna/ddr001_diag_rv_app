import 'package:dio/dio.dart';

import 'qa_app_config.dart';

class QaNetworkBlockedException implements Exception {
  const QaNetworkBlockedException(this.code);

  final String code;

  @override
  String toString() => 'QaNetworkBlockedException($code)';
}

abstract final class QaNetworkPolicy {
  static const requestFlag = 'explicitQaRequest';
  static const approvedHost = 'ddr001-rv-qa.invalid';
  static const productionHosts = {'cifra.aquafim.com', 'www.cifra.aquafim.com'};

  static void install(Dio dio, QaAppConfig config) {
    validateConfiguredEndpoint(config);
    dio.interceptors.insert(
      0,
      InterceptorsWrapper(
        onRequest: (options, handler) {
          try {
            validateRequest(config, options);
            options.followRedirects = false;
            handler.next(options);
          } on QaNetworkBlockedException catch (error) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                error: error,
                message: error.code,
              ),
            );
          }
        },
        onResponse: (response, handler) {
          try {
            final location = response.headers.value('location');
            validateRedirect(
              config,
              location == null
                  ? null
                  : response.requestOptions.uri.resolve(location),
            );
            handler.next(response);
          } on QaNetworkBlockedException catch (error) {
            handler.reject(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
                error: error,
                message: error.code,
              ),
            );
          }
        },
      ),
    );
  }

  static void validateConfiguredEndpoint(QaAppConfig config) {
    _validateQaUri(config.apiBaseUrl);
    if (config.syncEnabled || !config.fixtureMode) {
      throw const QaNetworkBlockedException('QA_CONFIGURATION_UNSAFE');
    }
  }

  static void validateRequest(QaAppConfig config, RequestOptions request) {
    validateConfiguredEndpoint(config);
    if (request.extra[requestFlag] != true) {
      throw const QaNetworkBlockedException('QA_FLAG_REQUIRED');
    }
    _validateQaUri(request.uri);
    if (!config.syncEnabled) {
      throw const QaNetworkBlockedException('QA_NETWORK_DISABLED');
    }
  }

  static void validateRedirect(QaAppConfig config, Uri? redirect) {
    if (redirect == null) return;
    _validateQaUri(redirect);
  }

  static void _validateQaUri(Uri uri) {
    final host = uri.host.trim().toLowerCase();
    final productionLike = productionHosts.any(
      (value) =>
          host == value || host.endsWith('.$value') || host.contains(value),
    );
    if (uri.scheme != 'https' ||
        host.isEmpty ||
        productionLike ||
        host != approvedHost ||
        uri.hasPort ||
        !uri.path.startsWith('/api/v1')) {
      throw const QaNetworkBlockedException('QA_HOST_REJECTED');
    }
  }
}
