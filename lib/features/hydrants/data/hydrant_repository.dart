import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/security/local_data_scope.dart';
import 'hydrant_api_models.dart';

class HydrantRepository {
  HydrantRepository({required this.client, required this.box});
  final ApiClient client;
  final Box<String> box;
  LocalDataScope? _accessScope;
  bool _scopeConfigured = false;
  final Map<String, Future<List<CachedHydrant>>> _activeRefreshes = {};

  void setAccessScope(LocalDataScope? scope) {
    _accessScope = scope;
    _scopeConfigured = true;
  }

  String _key(String scope, String hydrantId) {
    final namespace = _accessScope?.namespace;
    return namespace == null
        ? '$scope:$hydrantId'
        : '$namespace/$scope/$hydrantId';
  }

  bool _isAccessibleKey(Object key) {
    if (!_scopeConfigured) return true;
    final namespace = _accessScope?.namespace;
    return namespace != null && '$key'.startsWith('$namespace/');
  }

  List<CachedHydrant> cached({String? scope}) {
    final values = <CachedHydrant>[];
    for (final entry in box.toMap().entries) {
      if (!_isAccessibleKey(entry.key)) continue;
      try {
        final item = CachedHydrant.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (scope == null || item.scope == scope) values.add(item);
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

  Future<CachedHydrant> createManual({
    required String localId,
    required String accountNumber,
    required String createdByUserId,
    required String accountId,
    required String environment,
    required String reason,
    String? locality,
    String? municipality,
    double? latitude,
    double? longitude,
  }) async {
    final item = CachedHydrant(
      hydrantId: localId,
      accountNumber: accountNumber,
      scope: 'mine',
      locality: locality,
      municipality: municipality,
      latitude: latitude,
      longitude: longitude,
      updatedAt: DateTime.now().toUtc(),
      source: 'manual',
      createdByUserId: createdByUserId,
      accountId: accountId,
      environment: environment,
      reason: reason,
    );
    await box.put(_key('mine', localId), jsonEncode(item.toJson()));
    await box.put(
      _key('all', localId),
      jsonEncode({...item.toJson(), 'scope': 'all'}),
    );
    return item;
  }

  Future<CachedHydrant> synchronizeManual(
    String localId, {
    required String idempotencyKey,
  }) async {
    final local = cached().firstWhere(
      (item) => item.hydrantId == localId && item.source == 'manual',
    );
    if (local.remoteId != null) return local;
    try {
      final response = await client.dio.post<Map<String, dynamic>>(
        '/hydrants/manual',
        data: {
          'localReference': local.hydrantId,
          'visibleCode': local.accountNumber,
          if (local.locality?.isNotEmpty == true) 'locality': local.locality,
          if (local.municipality?.isNotEmpty == true)
            'municipality': local.municipality,
          if (local.latitude != null) 'latitude': local.latitude,
          if (local.longitude != null) 'longitude': local.longitude,
          'reason': local.reason,
        },
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      final remoteId = response.data?['id']?.toString();
      if (remoteId == null || remoteId.isEmpty) {
        throw const FormatException('remote hydrant id');
      }
      CachedHydrant linked(String scope) => CachedHydrant.fromJson({
        ...local.toJson(),
        'scope': scope,
        'remoteId': remoteId,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      final mine = linked('mine');
      await box.put(_key('mine', localId), jsonEncode(mine.toJson()));
      await box.put(_key('all', localId), jsonEncode(linked('all').toJson()));
      return mine;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<CachedHydrant>> refresh({
    String? search,
    int pageSize = 200,
    String scope = 'mine',
  }) {
    final key = '$scope|${search?.trim() ?? ''}|$pageSize';
    final active = _activeRefreshes[key];
    if (active != null) return active;
    final future = _performRefresh(
      search: search,
      pageSize: pageSize,
      scope: scope,
    );
    _activeRefreshes[key] = future;
    return future.whenComplete(() => _activeRefreshes.remove(key));
  }

  Future<List<CachedHydrant>> _performRefresh({
    String? search,
    required int pageSize,
    required String scope,
  }) async {
    try {
      var page = 1;
      var hasMore = true;
      final downloaded = <CachedHydrant>[];
      while (hasMore) {
        final response = await client.dio.get<Map<String, dynamic>>(
          '/hydrants',
          queryParameters: {
            if (search?.trim().isNotEmpty == true) 'search': search!.trim(),
            'scope': scope,
            'page': page,
            'pageSize': pageSize,
          },
        );
        final data = response.data ?? const {};
        final rawItems = (data['items'] as List? ?? const []);
        final now = DateTime.now().toUtc();
        downloaded.addAll(
          rawItems.whereType<Map>().map(
            (raw) => CachedHydrant.fromApi(
              Map<String, dynamic>.from(raw),
              now,
              scope: scope,
            ),
          ),
        );
        final total = int.tryParse('${data['total'] ?? ''}');
        hasMore =
            rawItems.length == pageSize &&
            (total == null || page * pageSize < total);
        page++;
      }
      final replacement = {
        for (final item in downloaded)
          _key(scope, item.hydrantId): jsonEncode(item.toJson()),
      };
      final existingKeys = box.keys
          .where((key) {
            if (!_isAccessibleKey(key)) return false;
            try {
              final value = CachedHydrant.fromJson(
                Map<String, dynamic>.from(jsonDecode(box.get(key)!) as Map),
              );
              return value.scope == scope && value.source != 'manual';
            } on Object {
              return false;
            }
          })
          .where((key) => !replacement.containsKey(key))
          .toList(growable: false);
      await box.putAll(replacement);
      await box.deleteAll(existingKeys);
      return cached(scope: scope);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<({DateTime date, int submitted, int pending})> todayStats() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/profile/today-stats',
      );
      final data = response.data ?? const {};
      return (
        date: DateTime.parse('${data['date']}').toLocal(),
        submitted: (data['completed'] as num?)?.toInt() ?? 0,
        pending: (data['pending'] as num?)?.toInt() ?? 0,
      );
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
        scope: 'all',
      );
      await box.put(_key('all', item.hydrantId), jsonEncode(item.toJson()));
      return item;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
