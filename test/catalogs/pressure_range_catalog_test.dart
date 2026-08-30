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
    await hive.open(boxes: const ['pressure_ranges_test']);
    box = Hive.box<String>('pressure_ranges_test');
  });
  tearDown(() => hive.close());

  test('formats ranges in Spanish without insignificant zeros', () {
    const range = PressureRangeOption(
      localId: 'x',
      minimum: .5,
      maximum: 6.5,
      unit: 'bar',
      status: CatalogSyncStatus.synced,
    );
    expect(range.display, '0,5–6,5 bar');
    expect(range.normalizedKey, '0.5000|6.5000|bar');
  });

  test('creates once locally and isolates a pending range by owner', () async {
    final repository = _repository(box)..setOwner('user-a');
    final first = await repository.createPressureRange(
      0,
      100,
      'PSI',
      ownerUserId: 'user-a',
    );
    final duplicate = await repository.createPressureRange(
      0.0,
      100.00,
      ' psi ',
      ownerUserId: 'user-a',
    );
    expect(duplicate.localId, first.localId);
    expect(repository.pressureRanges.single.display, '0–100 psi');
    repository.setOwner('user-b');
    expect(repository.pressureRanges, isEmpty);
    repository.setOwner('user-a');
    expect(repository.pressureRanges.single.status, CatalogSyncStatus.pending);
  });

  test('rejects invalid bounds and uncontrolled units', () async {
    final repository = _repository(box)..setOwner('user-a');
    expect(
      () => repository.createPressureRange(2, 2, 'psi', ownerUserId: 'user-a'),
      throwsFormatException,
    );
    expect(
      () =>
          repository.createPressureRange(0, 100, 'kPa', ownerUserId: 'user-a'),
      throwsFormatException,
    );
  });
}

DynamicCatalogRepository _repository(Box<String> box) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid/api/v1'));
  dio.httpClientAdapter = FakeHttpAdapter(
    (_) async => jsonResponse('{"title":"Synthetic failure"}', 500),
  );
  return DynamicCatalogRepository(
    client: ApiClient(
      config: AppConfig(
        environment: 'test',
        apiBaseUrl: Uri.parse('https://example.invalid/api/v1'),
      ),
      sessionStorage: MemorySessionStorage(),
      dio: dio,
    ),
    box: box,
  );
}
