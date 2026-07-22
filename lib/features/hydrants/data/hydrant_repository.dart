import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'hydrant_api_models.dart';

class HydrantRepository {
  HydrantRepository({required this.client, required this.box});
  final ApiClient client;
  final Box<String> box;

  List<CachedHydrant> cached() {
    final values = <CachedHydrant>[];
    for (final raw in box.values) {
      try {
        values.add(
          CachedHydrant.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          ),
        );
      } on Object {
        continue;
      }
    }
    values.sort((a, b) => a.accountNumber.compareTo(b.accountNumber));
    return values;
  }

  DateTime? get lastUpdated {
    final dates = cached().map((e) => e.updatedAt).toList();
    dates.sort();
    return dates.isEmpty ? null : dates.last;
  }

  Future<List<CachedHydrant>> refresh({
    String? search,
    int pageSize = 200,
  }) async {
    try {
      var page = 1;
      var hasMore = true;
      while (hasMore) {
        final response = await client.dio.get<Map<String, dynamic>>(
          '/hydrants',
          queryParameters: {
            if (search?.trim().isNotEmpty == true) 'search': search!.trim(),
            'page': page,
            'pageSize': pageSize,
          },
        );
        final data = response.data ?? const {};
        final rawItems = (data['items'] as List? ?? const []);
        final now = DateTime.now().toUtc();
        for (final raw in rawItems.whereType<Map>()) {
          final item = CachedHydrant.fromApi(
            Map<String, dynamic>.from(raw),
            now,
          );
          await box.put(item.hydrantId, jsonEncode(item.toJson()));
        }
        final total = int.tryParse('${data['total'] ?? ''}');
        hasMore =
            rawItems.length == pageSize &&
            (total == null || page * pageSize < total);
        page++;
      }
      return cached();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<CachedHydrant> findByAccount(String accountNumber) async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/hydrants/${Uri.encodeComponent(accountNumber.trim())}',
      );
      final item = CachedHydrant.fromApi(
        response.data ?? const {},
        DateTime.now().toUtc(),
      );
      await box.put(item.hydrantId, jsonEncode(item.toJson()));
      return item;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
