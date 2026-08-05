import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowed = bool.fromEnvironment(
  'ALLOW_PRODUCTION_CONNECTIVITY_TESTS',
  defaultValue: false,
);
const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');

void main() {
  late Uri base;

  setUpAll(() {
    if (!_allowed) {
      throw StateError('Ejecuta con ALLOW_PRODUCTION_CONNECTIVITY_TESTS=true.');
    }
    base = Uri.parse(_configuredBaseUrl);
    if (base.scheme != 'http' ||
        base.host != 'cifra.aquafim.com' ||
        base.port != 3002 ||
        base.path != '/api/v1') {
      throw StateError(
        'API_BASE_URL debe ser http://cifra.aquafim.com:3002/api/v1.',
      );
    }
  });

  test('DNS resuelve cifra.aquafim.com a una dirección IPv4', () async {
    final addresses = await InternetAddress.lookup(
      base.host,
    ).timeout(const Duration(seconds: 10));
    final ipv4 = addresses
        .where((address) => address.type == InternetAddressType.IPv4)
        .toList();
    _diagnostic('DNS host=${base.host} addresses=${addresses.join(',')}');
    expect(ipv4, isNotEmpty, reason: 'Android debe poder resolver una IPv4.');
  });

  test('TCP permite abrir el puerto 3002', () async {
    final stopwatch = Stopwatch()..start();
    final socket = await Socket.connect(
      base.host,
      base.port,
      timeout: const Duration(seconds: 10),
    );
    addTearDown(socket.destroy);
    _diagnostic(
      'TCP remote=${socket.remoteAddress.address}:${socket.remotePort} '
      'elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    expect(socket.remotePort, base.port);
  });

  test('health/live responde 200 sin redirección y con JSON válido', () async {
    final result = await _request(base, 'GET', '/health/live');
    expect(result.statusCode, HttpStatus.ok);
    expect(result.redirects, isEmpty);
    expect(result.contentType, contains('application/json'));
    expect(result.json['status'], 'ok');
  });

  test('health/ready confirma dependencias del servidor', () async {
    final result = await _request(base, 'GET', '/health/ready');
    expect(result.statusCode, HttpStatus.ok);
    expect(result.json, containsPair('status', 'ready'));
    expect(result.json, containsPair('database', 'ok'));
    expect(result.json, containsPair('storage', 'ok'));
    expect(result.json, containsPair('configuration', 'ok'));
  });

  test('cinco probes consecutivos permanecen disponibles', () async {
    for (var attempt = 1; attempt <= 5; attempt++) {
      final result = await _request(base, 'GET', '/health/live');
      expect(result.statusCode, HttpStatus.ok, reason: 'Intento $attempt');
    }
  });

  test(
    'ruta de login existe y valida una solicitud sin crear sesión',
    () async {
      final result = await _request(
        base,
        'POST',
        '/field-sessions/start',
        body: const <String, Object?>{},
      );
      expect(result.statusCode, 422);
      expect(result.json['title'], 'Validation error');
      expect(result.json['errors'], isA<List<Object?>>());
      expect(result.json['requestId'], isNotEmpty);
    },
  );
}

Future<
  ({
    int statusCode,
    List<RedirectInfo> redirects,
    String contentType,
    Map<String, dynamic> json,
  })
>
_request(
  Uri base,
  String method,
  String relative, {
  Map<String, Object?>? body,
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 10);
  try {
    final uri = base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}$relative',
    );
    final stopwatch = Stopwatch()..start();
    final request = await client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      'X-Request-ID',
      'connectivity-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'DDR001-Android-Connectivity-Test',
    );
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final raw = await utf8.decoder.bind(response).join();
    final decoded = raw.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    _diagnostic(
      '$method ${uri.path} status=${response.statusCode} '
      'elapsedMs=${stopwatch.elapsedMilliseconds} bytes=${raw.length}',
    );
    return (
      statusCode: response.statusCode,
      redirects: response.redirects,
      contentType: response.headers.contentType?.mimeType ?? '',
      json: decoded,
    );
  } finally {
    client.close(force: true);
  }
}

void _diagnostic(String message) {
  // La salida no incluye credenciales ni datos de usuarios.
  // ignore: avoid_print
  print('[PRODUCTION-CONNECTIVITY] $message');
}
