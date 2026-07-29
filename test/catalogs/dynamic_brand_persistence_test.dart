import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/features/catalogs/dynamic_catalog_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/foundation_fakes.dart';
import '../helpers/hive_test_environment.dart';

void main() {
  late HiveTestEnvironment hive;
  late Box<String> box;

  setUp(() async {
    hive = HiveTestEnvironment();
    await hive.open(boxes: const ['dynamic_brand_test']);
    box = Hive.box<String>('dynamic_brand_test');
  });

  tearDown(() => hive.close());

  test(
    'casing variants resolve to one uppercase brand within one type',
    () async {
      final repository = _repository(box);

      final first = await repository.createBrand(
        'Bermad',
        BrandElementType.valve,
      );
      final duplicate = await repository.createBrand(
        ' bermad ',
        BrandElementType.valve,
      );

      expect(duplicate.localId, first.localId);
      expect(repository.brands(BrandElementType.valve), hasLength(1));
      expect(duplicate.name, 'BERMAD');
      expect(duplicate.normalizedName, 'BERMAD');
    },
  );

  test('equal names remain separate in different element types', () async {
    final repository = _repository(box);

    final valve = await repository.createBrand(
      'Bermad',
      BrandElementType.valve,
    );
    final solenoid = await repository.createBrand(
      'bermad',
      BrandElementType.solenoid,
    );

    expect(valve.localId, isNot(solenoid.localId));
    expect(repository.brands(BrandElementType.valve).single.name, 'BERMAD');
    expect(repository.brands(BrandElementType.solenoid).single.name, 'BERMAD');
  });

  test(
    'a synchronization failure preserves the uppercase pending brand',
    () async {
      final repository = _repository(box);
      final created = await repository.createBrand(
        ' Cla-Val ',
        BrandElementType.valve,
      );

      await repository.synchronizePending();

      final preserved = repository.brands(BrandElementType.valve).single;
      expect(preserved.localId, created.localId);
      expect(preserved.remoteId, isNull);
      expect(preserved.name, 'CLA-VAL');
      expect(preserved.status, CatalogSyncStatus.error);
    },
  );
}

DynamicCatalogRepository _repository(Box<String> box) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
  dio.httpClientAdapter = FakeHttpAdapter(
    (_) async => jsonResponse('{"title":"Synthetic failure"}', 500),
  );
  final client = ApiClient(
    config: AppConfig(
      environment: 'test',
      apiBaseUrl: Uri.parse('https://example.invalid/api/v1'),
    ),
    sessionStorage: MemorySessionStorage(),
    dio: dio,
  );
  return DynamicCatalogRepository(client: client, box: box);
}
