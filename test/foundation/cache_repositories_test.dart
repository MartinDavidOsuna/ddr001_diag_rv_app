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
    'respuesta completa reconcilia registros remotos y retira obsoletos',
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
      expect(values.map((e) => e.accountNumber), ['CTA-001']);
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

  test(
    'snapshot de catálogo usa una solicitud y reutiliza ETag con 304',
    () async {
      var invocation = 0;
      final adapter = FakeHttpAdapter((options) async {
        invocation++;
        if (invocation == 2) return ResponseBody.fromString('', 304);
        return jsonResponse(
          '{"items":[{"hydrant_id":"735d3d0e-78a3-4ca8-a34b-6c0513458d29","account_number":"CTA-SNAPSHOT"}],"total":1}',
          200,
          headers: {
            'etag': ['"snapshot-v1"'],
          },
        );
      });
      final repository = HydrantRepository(
        client: clientWith(adapter),
        box: Hive.box<String>('local_hydrants_v1'),
      );
      final first = await repository.refreshCatalogSnapshot();
      final second = await repository.refreshCatalogSnapshot();
      expect(first.single.accountNumber, 'CTA-SNAPSHOT');
      expect(second.single.accountNumber, 'CTA-SNAPSHOT');
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.path, endsWith('/hydrants/sync'));
      expect(adapter.requests.last.headers['If-None-Match'], '"snapshot-v1"');
    },
  );

  test('snapshot 404 activa fallback paginado una vez por sesión', () async {
    final adapter = FakeHttpAdapter((options) async {
      if (options.path.endsWith('/hydrants/sync')) {
        return jsonResponse(
          '{"title":"Not found","detail":"Hydrant not found."}',
          404,
        );
      }
      return jsonResponse(
        '{"items":[{"hydrant_id":"735d3d0e-78a3-4ca8-a34b-6c0513458d29","account_number":"CTA-FALLBACK"}],"total":1}',
        200,
      );
    });
    final repository = HydrantRepository(
      client: clientWith(adapter),
      box: Hive.box<String>('local_hydrants_v1'),
    );

    final first = await repository.refreshCatalogSnapshot();
    final second = await repository.refreshCatalogSnapshot();

    expect(first.single.accountNumber, 'CTA-FALLBACK');
    expect(second.single.accountNumber, 'CTA-FALLBACK');
    expect(repository.syncEndpointSupported, isFalse);
    expect(
      adapter.requests.where(
        (request) => request.path.endsWith('/hydrants/sync'),
      ),
      hasLength(1),
    );
    expect(
      adapter.requests
          .where((request) => request.path.endsWith('/hydrants'))
          .every((request) => request.queryParameters['scope'] == 'all'),
      isTrue,
    );
  });

  for (final status in [401, 403, 500]) {
    test('snapshot $status no activa fallback y conserva caché', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse('{"title":"Error"}', status),
      );
      final repository = HydrantRepository(
        client: clientWith(adapter),
        box: Hive.box<String>('local_hydrants_v1'),
      );
      await repository.box.put(
        'cached',
        jsonEncode(
          CachedHydrant(
            hydrantId: 'cached',
            accountNumber: 'CTA-CACHE',
            scope: 'all',
            updatedAt: DateTime.utc(2026),
          ).toJson(),
        ),
      );

      await expectLater(
        repository.refreshCatalogSnapshot(),
        throwsA(isA<Object>()),
      );
      expect(repository.cached(scope: 'all').single.accountNumber, 'CTA-CACHE');
      expect(adapter.requests, hasLength(status >= 500 ? 2 : 1));
      expect(
        adapter.requests.every(
          (request) => request.path.endsWith('/hydrants/sync'),
        ),
        isTrue,
      );
    });
  }

  test('mapa envía radio de 2 km y conserva cursor', () async {
    final adapter = FakeHttpAdapter(
      (_) async => jsonResponse(
        '{"items":[{"hydrantId":"735d3d0e-78a3-4ca8-a34b-6c0513458d29","accountNumber":"CTA-MAP","latitude":21.9,"longitude":-102.3}],"nextCursor":"next","hasMore":true,"generatedAt":"2026-07-28T12:00:00Z"}',
        200,
      ),
    );
    final repository = HydrantRepository(
      client: clientWith(adapter),
      box: Hive.box<String>('local_hydrants_v1'),
    );

    final page = await repository.fetchMapPage(
      latitude: 21.9,
      longitude: -102.3,
    );

    expect(page.items.single.accountNumber, 'CTA-MAP');
    expect(page.nextCursor, 'next');
    expect(adapter.requests.single.queryParameters['radiusKm'], 2);
    expect(repository.cached(scope: 'all').single.accountNumber, 'CTA-MAP');
  });

  test(
    'snapshot local sobrevive reinicio y cursor actualiza sólo los cambios',
    () async {
      var invocation = 0;
      final adapter = FakeHttpAdapter((options) async {
        invocation++;
        if (invocation == 1) {
          return jsonResponse(
            '{"items":[{"hydrant_id":"735d3d0e-78a3-4ca8-a34b-6c0513458d29","account_number":"CTA-MAP","latitude":21.9,"longitude":-102.3,"rvStatus":"available","updated_at":"2026-08-01T00:00:00Z"}],"total":1,"syncCursor":"cursor-1"}',
            200,
          );
        }
        return jsonResponse(
          '{"items":[{"hydrantId":"735d3d0e-78a3-4ca8-a34b-6c0513458d29","accountNumber":"CTA-MAP","latitude":21.9,"longitude":-102.3,"rvStatus":"validated","updatedAt":"2026-08-02T00:00:00Z"}],"hasMore":false,"syncCursor":"cursor-2","generatedAt":"2026-08-02T00:00:01Z"}',
          200,
        );
      });
      final repository = HydrantRepository(
        client: clientWith(adapter),
        box: Hive.box<String>('local_hydrants_v1'),
      );
      await repository.refreshCatalogSnapshot();

      final restarted = HydrantRepository(
        client: clientWith(adapter),
        box: Hive.box<String>('local_hydrants_v1'),
      );
      expect(restarted.cached(scope: 'all'), hasLength(1));
      expect(restarted.cached(scope: 'all').single.rvStatus, 'available');

      await restarted.refreshMapChanges();
      expect(adapter.requests.last.queryParameters['scope'], 'all');
      expect(adapter.requests.last.queryParameters['cursor'], 'cursor-1');
      expect(restarted.cached(scope: 'all').single.rvStatus, 'validated');
    },
  );

  test('alta manual conserva UUID, propietario y ámbito local', () async {
    final repository = HydrantRepository(
      client: clientWith(FakeHttpAdapter((_) async => jsonResponse('{}', 500))),
      box: Hive.box<String>('local_hydrants_v1'),
    );
    const localId = '735d3d0e-78a3-4ca8-a34b-6c0513458d29';
    final value = await repository.createManual(
      localId: localId,
      accountNumber: 'CAMPO-01',
      createdByUserId: 'user-a',
      accountId: 'rv-field',
      environment: 'test',
      reason: 'No aparece en catálogo',
    );

    expect(value.hydrantId, localId);
    expect(value.createdByUserId, 'user-a');
    expect(value.source, 'manual');
    expect(value.toAppModel().source.name, 'fieldCreated');
    expect(repository.cached(scope: 'mine').single.hydrantId, localId);
  });

  test('sincronización manual envía idempotencia y enlaza ID remoto', () async {
    late FakeHttpAdapter adapter;
    adapter = FakeHttpAdapter(
      (_) async => jsonResponse(
        '{"id":"remote-01","localReference":"735d3d0e-78a3-4ca8-a34b-6c0513458d29","status":"created"}',
        201,
      ),
    );
    final repository = HydrantRepository(
      client: clientWith(adapter),
      box: Hive.box<String>('local_hydrants_v1'),
    );
    const localId = '735d3d0e-78a3-4ca8-a34b-6c0513458d29';
    await repository.createManual(
      localId: localId,
      accountNumber: 'CAMPO-02',
      createdByUserId: 'user-a',
      accountId: 'rv-field',
      environment: 'test',
      reason: 'No aparece en catálogo',
    );
    final linked = await repository.synchronizeManual(
      localId,
      idempotencyKey: 'manualHydrant:$localId',
    );

    expect(adapter.requests.single.path, '/hydrants/manual');
    expect(
      adapter.requests.single.headers['Idempotency-Key'],
      'manualHydrant:$localId',
    );
    expect(linked.remoteId, 'remote-01');
    expect(linked.hydrantId, localId);
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
