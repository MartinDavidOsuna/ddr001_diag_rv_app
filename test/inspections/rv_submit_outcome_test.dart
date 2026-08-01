import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/features/inspections/data/inspection_remote_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/foundation_fakes.dart';

void main() {
  InspectionRemoteRepository repositoryFor(String body) {
    final dio = Dio()
      ..httpClientAdapter = FakeHttpAdapter(
        (_) async => jsonResponse(body, 200),
      );
    return InspectionRemoteRepository(
      ApiClient(
        config: AppConfig.fromEnvironment(
          environmentOverride: 'development',
          apiBaseUrlOverride: 'https://example.test/api/v1',
        ),
        sessionStorage: MemorySessionStorage(),
        dio: dio,
      ),
    );
  }

  for (final result in ['official', 'already_official']) {
    test('submit interpreta $result como confirmación persistida', () async {
      final response = await repositoryFor(
        '{"result":"$result","inspectionId":"inspection",'
        '"officialInspectionId":"official","status":"submitted",'
        '"rvStatus":"completed","lastStatusChangedAt":"2026-08-01T10:00:00Z"}',
      ).submit('inspection');
      expect(response.result, result);
      expect(response.status, 'submitted');
      expect(response.officialInspectionId, 'official');
    });
  }

  test('submit interpreta conflicto persistido con sus referencias', () async {
    final response = await repositoryFor(
      '{"result":"conflict","inspectionId":"loser",'
      '"officialInspectionId":"winner","conflictId":"conflict",'
      '"status":"conflict","rvStatus":"conflict",'
      '"lastStatusChangedAt":"2026-08-01T10:00:00Z"}',
    ).submit('loser');
    expect(response.result, 'conflict');
    expect(response.conflictId, 'conflict');
    expect(response.officialInspectionId, 'winner');
  });
}
