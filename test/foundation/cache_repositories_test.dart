import 'dart:convert';

import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/features/checklist/data/checklist_repository.dart';
import 'package:ddr001diag/features/hydrants/data/hydrant_api_models.dart';
import 'package:ddr001diag/features/hydrants/data/hydrant_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/foundation_fakes.dart';
import '../helpers/hive_test_environment.dart';

void main() {
  late HiveTestEnvironment environment;
  late MemorySessionStorage storage;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
    storage = MemorySessionStorage();
  });
  tearDown(() => environment.close());

  ApiClient clientWith(FakeHttpAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: 'https://example.test/api/v1',
      ),
      sessionStorage: storage,
      dio: dio,
    );
  }

  test('mapea hidrante API al modelo local RV', () {
    final value = CachedHydrant.fromApi({
      'hydrant_id': '735d3d0e-78a3-4ca8-a34b-6c0513458d29',
      'account_number': 'CTA-001',
      'installation_year': 2018,
      'flow_lps': 12.5,
      'latitude': 21.9,
      'longitude': -102.3,
      'locality': 'Pabellón',
      'municipality': 'Aguascalientes',
      'calculated_status': 'pending',
    }, DateTime.utc(2026));
    final app = value.toAppModel();
    expect(app.id, value.hydrantId);
    expect(app.code, 'CTA-001');
    expect(app.latitude, 21.9);
    expect(app.f02b.status.name, 'notRequired');
  });

  test(
    'caché de hidrantes conserva datos y no elimina páginas previas',
    () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(
          '{"items":[{"hydrant_id":"735d3d0e-78a3-4ca8-a34b-6c0513458d29","account_number":"CTA-001","latitude":21.9,"longitude":-102.3}],"total":1}',
          200,
        ),
      );
      final repository = HydrantRepository(
        client: clientWith(adapter),
        box: Hive.box<String>('local_hydrants_v1'),
      );
      await repository.box.put(
        'previous',
        jsonEncode(
          CachedHydrant(
            hydrantId: 'previous',
            accountNumber: 'CTA-000',
            scope: 'mine',
            updatedAt: DateTime.utc(2025),
          ).toJson(),
        ),
      );
      final values = await repository.refresh();
      expect(
        values.map((e) => e.accountNumber),
        containsAll(['CTA-000', 'CTA-001']),
      );
      expect(repository.lastUpdated, isNotNull);
    },
  );

  test('caché separa catálogo general de lista personal', () async {
    final adapter = FakeHttpAdapter(
      (_) async => jsonResponse(
        '{"items":[{"hydrant_id":"735d3d0e-78a3-4ca8-a34b-6c0513458d29","account_number":"CTA-ALL","rvStatus":"completed","latestInspectionStatus":"submitted"}],"total":1}',
        200,
      ),
    );
    final repository = HydrantRepository(
      client: clientWith(adapter),
      box: Hive.box<String>('local_hydrants_v1'),
    );
    await repository.refresh(scope: 'all');
    expect(adapter.requests.single.queryParameters['scope'], 'all');
    expect(repository.cached(scope: 'all').single.accountNumber, 'CTA-ALL');
    expect(repository.cached(scope: 'mine'), isEmpty);
    expect(
      repository.cached(scope: 'all').single.toAppModel().f02a.status.name,
      'completed',
    );
  });

  test('checklist 200 guarda definición y ETag', () async {
    final adapter = FakeHttpAdapter(
      (_) async => jsonResponse(
        _checklist,
        200,
        headers: {
          'etag': ['"v1"'],
        },
      ),
    );
    final repository = ChecklistRepository(
      client: clientWith(adapter),
      box: Hive.box<String>('rv_checklist_cache_v1'),
    );
    final value = await repository.refresh();
    expect(value.version, 1);
    expect(value.etag, '"v1"');
    expect(repository.cached()?.sections.single.items.single.photoSlot, isNull);
  });

  test('checklist 304 envía If-None-Match y reutiliza caché', () async {
    late FakeHttpAdapter adapter;
    adapter = FakeHttpAdapter((_) async => ResponseBody.fromString('', 304));
    final box = Hive.box<String>('rv_checklist_cache_v1');
    final initialAdapter = FakeHttpAdapter(
      (_) async => jsonResponse(
        _checklist,
        200,
        headers: {
          'etag': ['"v1"'],
        },
      ),
    );
    await ChecklistRepository(
      client: clientWith(initialAdapter),
      box: box,
    ).refresh();
    final value = await ChecklistRepository(
      client: clientWith(adapter),
      box: box,
    ).refresh();
    expect(value.version, 1);
    expect(adapter.requests.single.headers['If-None-Match'], '"v1"');
  });

  test('checklist usa caché offline', () async {
    final box = Hive.box<String>('rv_checklist_cache_v1');
    await ChecklistRepository(
      client: clientWith(
        FakeHttpAdapter(
          (_) async => jsonResponse(
            _checklist,
            200,
            headers: {
              'etag': ['"v1"'],
            },
          ),
        ),
      ),
      box: box,
    ).refresh();
    final offline = FakeHttpAdapter(
      (options) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'offline',
      ),
    );
    final value = await ChecklistRepository(
      client: clientWith(offline),
      box: box,
    ).refresh();
    expect(value.title, 'Revisión visual');
  });
}

const _checklist = '''
{"id":"0e67f79d-edde-49f9-81bf-b0464f1f19b4","code":"RV","version":1,"title":"Revisión visual","publishedAt":"2026-01-01T00:00:00.000Z","sections":[{"id":"25eff288-8093-4d1c-8473-26aeac0cba9f","code":"GENERAL","title":"General","order":1,"items":[{"id":"867fae6b-f67d-4e77-bca4-264f111cfb02","code":"VISIBLE","label":"¿Es visible?","type":"boolean","required":true,"order":1,"unit":null,"photoSlot":null,"helpText":null}]}]}
''';
