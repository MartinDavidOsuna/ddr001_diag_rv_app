import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowed = bool.fromEnvironment(
  'ALLOW_PRODUCTION_READONLY_TESTS',
  defaultValue: false,
);
const _baseUrl = String.fromEnvironment('API_BASE_URL');
const _accessToken = String.fromEnvironment('READONLY_ACCESS_TOKEN');

void main() {
  test('smoke remoto ejecuta exclusivamente lecturas autorizadas', () async {
    if (!_allowed) {
      throw StateError(
        'Las pruebas de producción requieren autorización explícita.',
      );
    }
    final base = Uri.tryParse(_baseUrl);
    if (base == null ||
        base.scheme != 'http' ||
        base.host != 'cifra.aquafim.com' ||
        base.port != 3002) {
      throw StateError('La URL no corresponde al ambiente autorizado.');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    addTearDown(client.close);

    final live = await _get(client, base, '/health/live');
    expect(live.statusCode, 200);
    expect(live.json['status'], 'ok');

    final ready = await _get(client, base, '/health/ready');
    expect(ready.statusCode, 200);
    expect(ready.json['status'], 'ready');

    final version = await _get(client, base, '/version');
    expect(version.statusCode, 200);
    expect(version.json['features'], isA<Map>());

    if (_accessToken.isEmpty) return;

    final hydrants = await _get(
      client,
      base,
      '/hydrants?scope=all&page=1&pageSize=5',
      bearer: _accessToken,
    );
    expect(hydrants.statusCode, 200);
    expect(hydrants.json['items'], isA<List>());
    expect((hydrants.json['items'] as List).length, lessThanOrEqualTo(5));

    final map = await _get(
      client,
      base,
      '/hydrants/map?lat=21&lng=-102&radiusKm=2&pageSize=5',
      bearer: _accessToken,
    );
    expect(map.statusCode, 200);
    expect(map.json['items'], isA<List>());
  });
}

Future<({int statusCode, Map<String, dynamic> json})> _get(
  HttpClient client,
  Uri base,
  String relative, {
  String? bearer,
}) async {
  final started = Stopwatch()..start();
  final uri = base.resolve(
    '${base.path.replaceAll(RegExp(r'/$'), '')}$relative',
  );
  // This suite intentionally exposes only method/path/timing, never tokens.
  // ignore: avoid_print
  print('[READONLY-SMOKE] GET ${uri.path} mutationRisk=none');
  final request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  if (bearer?.isNotEmpty == true) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  }
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  // ignore: avoid_print
  print(
    '[READONLY-SMOKE] GET ${uri.path} status=${response.statusCode} '
    'elapsedMs=${started.elapsedMilliseconds} bytes=${body.length}',
  );
  return (
    statusCode: response.statusCode,
    json: body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(body) as Map),
  );
}
