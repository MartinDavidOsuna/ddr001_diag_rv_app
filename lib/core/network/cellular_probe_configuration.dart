class CellularProbeConfiguration {
  const CellularProbeConfiguration({
    required this.url,
    this.httpMethod = 'GET',
    this.expectedStatusCode = 204,
    this.connectTimeout = const Duration(seconds: 12),
    this.readTimeout = const Duration(seconds: 12),
    this.networkTimeout = const Duration(seconds: 60),
    this.maximumResponseBytes = 1024,
    this.methodVersion = 'cellular-network-http-demo-v1',
  });

  /// Endpoint DEMO, centralizado y sustituible por uno controlado en Etapa 5.
  /// La solicitud no incluye datos del reporte ni parámetros identificables.
  static const demo = CellularProbeConfiguration(
    url: 'https://connectivitycheck.gstatic.com/generate_204',
  );

  final String url;
  final String httpMethod;
  final int expectedStatusCode;
  final Duration connectTimeout;
  final Duration readTimeout;
  final Duration networkTimeout;
  final int maximumResponseBytes;
  final String methodVersion;

  Map<String, Object> toChannelArguments(String probeId) => {
    'probeId': probeId,
    'url': url,
    'httpMethod': httpMethod,
    'expectedStatusCode': expectedStatusCode,
    'connectTimeoutMs': connectTimeout.inMilliseconds,
    'readTimeoutMs': readTimeout.inMilliseconds,
    'networkTimeoutMs': networkTimeout.inMilliseconds,
    'maximumResponseBytes': maximumResponseBytes,
    'methodVersion': methodVersion,
  };
}
