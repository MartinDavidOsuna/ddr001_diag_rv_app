import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/security/local_data_scope.dart';
import 'hydrant_api_models.dart';

class HydrantMapBounds {
  const HydrantMapBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  final double south, west, north, east;
}

class HydrantMapPage {
  const HydrantMapPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
    required this.generatedAt,
    this.syncCursor,
  });

  final List<CachedHydrant> items;
  final String? nextCursor;
  final bool hasMore;
  final DateTime generatedAt;
  final String? syncCursor;
}

class HydrantRepository {
  HydrantRepository({required this.client, required this.box});
  final ApiClient client;
  final Box<String> box;
  LocalDataScope? _accessScope;
  bool _scopeConfigured = false;
  final Map<String, Future<List<CachedHydrant>>> _activeRefreshes = {};
  final Map<String, List<CachedHydrant>> _memoryCache = {};
  Future<List<CachedHydrant>>? _activeSnapshotRefresh;
  bool? _syncEndpointSupported;

  bool? get syncEndpointSupported => _syncEndpointSupported;

  void setAccessScope(LocalDataScope? scope) {
    _accessScope = scope;
    _scopeConfigured = true;
    _memoryCache.clear();
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
    final cacheKey = scope ?? '*';
    final memory = _memoryCache[cacheKey];
    if (memory != null) return List.unmodifiable(memory);
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
    _memoryCache[cacheKey] = List.unmodifiable(values);
    return List.unmodifiable(values);
  }

  DateTime? get lastUpdated {
    final dates = cached().map((e) => e.updatedAt).toList();
    dates.sort();
    return dates.isEmpty ? null : dates.last;
  }

  String get _snapshotMetadataKey =>
      '${_accessScope?.namespace ?? 'unscoped'}/meta/catalog-snapshot';

  bool isCatalogCacheStale({Duration ttl = const Duration(minutes: 15)}) {
    final raw = box.get(_snapshotMetadataKey);
    if (raw == null) return true;
    try {
      final updatedAt = DateTime.tryParse(
        '${(jsonDecode(raw) as Map)['updatedAt'] ?? ''}',
      )?.toUtc();
      return updatedAt == null ||
          DateTime.now().toUtc().difference(updatedAt) >= ttl;
    } on Object {
      return true;
    }
  }

  Future<List<CachedHydrant>> refreshCatalogSnapshot({
    bool recheckCapability = false,
    bool force = false,
    void Function(int received, int? total)? onProgress,
  }) {
    final active = _activeSnapshotRefresh;
    if (active != null) return active;
    if (recheckCapability) _syncEndpointSupported = null;
    final future = _syncEndpointSupported == false
        ? _performRefresh(pageSize: 200, scope: 'all', onProgress: onProgress)
        : _performCatalogSnapshotRefresh(force: force, onProgress: onProgress);
    _activeSnapshotRefresh = future;
    return future.whenComplete(() => _activeSnapshotRefresh = null);
  }

  Future<List<CachedHydrant>> _performCatalogSnapshotRefresh({
    required bool force,
    void Function(int received, int? total)? onProgress,
  }) async {
    final requestWatch = Stopwatch()..start();
    try {
      String? etag;
      final rawMetadata = box.get(_snapshotMetadataKey);
      if (rawMetadata != null) {
        try {
          etag = (jsonDecode(rawMetadata) as Map)['etag']?.toString();
        } on Object {
          etag = null;
        }
      }
      final response = await client.dio.get<Map<String, dynamic>>(
        '/hydrants/sync',
        options: Options(
          headers: {if (!force) 'If-None-Match': ?etag},
          validateStatus: (status) =>
              status != null &&
              ((status >= 200 && status < 300) || status == 304),
        ),
      );
      _syncEndpointSupported = true;
      if (response.statusCode == 304) {
        onProgress?.call(
          cached(scope: 'all').length,
          cached(scope: 'all').length,
        );
        assert(() {
          // ignore: avoid_print
          print(
            '[HYDRANTS] syncStrategy=snapshot status=304 '
            'requestDurationMs=${requestWatch.elapsedMilliseconds}',
          );
          return true;
        }());
        return cached(scope: 'all');
      }
      final decodeWatch = Stopwatch()..start();
      final rawItems = response.data?['items'] as List? ?? const [];
      final now = DateTime.now().toUtc();
      final downloaded = rawItems
          .whereType<Map>()
          .map(
            (raw) => CachedHydrant.fromApi(
              Map<String, dynamic>.from(raw),
              now,
              scope: 'all',
            ),
          )
          .toList(growable: false);
      decodeWatch.stop();
      onProgress?.call(downloaded.length, downloaded.length);
      final replacement = {
        for (final item in downloaded)
          _key('all', item.hydrantId): jsonEncode(item.toJson()),
      };
      final cacheWatch = Stopwatch()..start();
      await box.putAll(replacement);
      final stale = box.keys
          .where((key) {
            if (!_isAccessibleKey(key) || replacement.containsKey(key)) {
              return false;
            }
            final raw = box.get(key);
            if (raw == null) return false;
            try {
              final item = CachedHydrant.fromJson(
                Map<String, dynamic>.from(jsonDecode(raw) as Map),
              );
              return item.scope == 'all' && item.source != 'manual';
            } on Object {
              return false;
            }
          })
          .toList(growable: false);
      await box.deleteAll(stale);
      await box.put(
        _snapshotMetadataKey,
        jsonEncode({
          'etag': response.headers.value('etag'),
          'updatedAt': now.toIso8601String(),
          'count': downloaded.length,
          'cursor': response.data?['syncCursor']?.toString(),
        }),
      );
      cacheWatch.stop();
      _memoryCache.clear();
      assert(() {
        // ignore: avoid_print
        print(
          '[HYDRANTS] syncStrategy=snapshot '
          'requestDurationMs=${requestWatch.elapsedMilliseconds} '
          'decodeDurationMs=${decodeWatch.elapsedMilliseconds} '
          'cacheWriteDurationMs=${cacheWatch.elapsedMilliseconds} '
          'itemsReceived=${downloaded.length} pagesReceived=1',
        );
        return true;
      }());
      return cached(scope: 'all');
    } on DioException catch (error) {
      if (error.requestOptions.path == '/hydrants/sync' &&
          error.response?.statusCode == 404) {
        _syncEndpointSupported = false;
        assert(() {
          // ignore: avoid_print
          print(
            '[HYDRANTS] syncStrategy=fallback reason=sync_endpoint_404 '
            'requestDurationMs=${requestWatch.elapsedMilliseconds}',
          );
          return true;
        }());
        return _performRefresh(
          pageSize: 200,
          scope: 'all',
          onProgress: onProgress,
        );
      }
      throw ApiException.fromDio(error);
    }
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
    _memoryCache.clear();
    return item;
  }

  Future<bool> deleteUnsyncedManualLocal({
    required String hydrantId,
    required String creatorId,
  }) async {
    final records = cached()
        .where((item) => item.hydrantId == hydrantId)
        .toList();
    if (records.isEmpty ||
        records.any(
          (item) =>
              item.source != 'manual' ||
              item.createdByUserId != creatorId ||
              item.remoteId != null,
        )) {
      return false;
    }
    await box.deleteAll([_key('mine', hydrantId), _key('all', hydrantId)]);
    _memoryCache.clear();
    return true;
  }

  Future<HydrantMapPage> fetchMapPage({
    double? latitude,
    double? longitude,
    double radiusKm = 2,
    HydrantMapBounds? bounds,
    int pageSize = 100,
    String? cursor,
    bool allCatalog = false,
  }) async {
    final radiusMode = latitude != null || longitude != null;
    if (!allCatalog &&
        (radiusMode == (bounds != null) ||
            (radiusMode && (latitude == null || longitude == null)))) {
      throw ArgumentError(
        'Provide either latitude/longitude or visible bounds.',
      );
    }
    if (allCatalog && (radiusMode || bounds != null)) {
      throw ArgumentError('allCatalog cannot be combined with a region.');
    }
    final watch = Stopwatch()..start();
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/hydrants/map',
        queryParameters: {
          if (radiusMode) 'lat': latitude,
          if (radiusMode) 'lng': longitude,
          if (radiusMode) 'radiusKm': radiusKm,
          if (bounds != null) 'south': bounds.south,
          if (bounds != null) 'west': bounds.west,
          if (bounds != null) 'north': bounds.north,
          if (bounds != null) 'east': bounds.east,
          if (allCatalog) 'scope': 'all',
          'pageSize': pageSize,
          if (cursor case final value?) ...{'cursor': value},
        },
      );
      final data = response.data ?? const {};
      final now =
          DateTime.tryParse('${data['generatedAt'] ?? ''}')?.toUtc() ??
          DateTime.now().toUtc();
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (raw) => CachedHydrant.fromApi(
              Map<String, dynamic>.from(raw),
              now,
              scope: 'all',
            ),
          )
          .toList(growable: false);
      final cacheWatch = Stopwatch()..start();
      await box.putAll({
        for (final item in items)
          _key('all', item.hydrantId): jsonEncode(item.toJson()),
      });
      cacheWatch.stop();
      _memoryCache.clear();
      assert(() {
        // ignore: avoid_print
        print(
          '[HYDRANTS] mapQueryDurationMs=${watch.elapsedMilliseconds} '
          'cacheWriteDurationMs=${cacheWatch.elapsedMilliseconds} '
          'itemsReceived=${items.length}',
        );
        return true;
      }());
      return HydrantMapPage(
        items: items,
        nextCursor: data['nextCursor']?.toString(),
        hasMore: data['hasMore'] == true,
        generatedAt: now,
        syncCursor: data['syncCursor']?.toString(),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<CachedHydrant>> refreshMapChanges() async {
    final rawMetadata = box.get(_snapshotMetadataKey);
    String? cursor;
    if (rawMetadata != null) {
      try {
        cursor = (jsonDecode(rawMetadata) as Map)['cursor']?.toString();
      } on Object {
        cursor = null;
      }
    }
    if (cursor == null || cursor.isEmpty) return refreshCatalogSnapshot();
    var currentCursor = cursor;
    var hasMore = false;
    do {
      final page = await fetchMapPage(
        allCatalog: true,
        pageSize: 500,
        cursor: currentCursor,
      );
      final writes = <String, String>{};
      final removals = <String>[];
      for (final item in page.items) {
        final key = _key('all', item.hydrantId);
        if (item.isActive) {
          writes[key] = jsonEncode(item.toJson());
        } else {
          removals.add(key);
        }
      }
      if (writes.isNotEmpty) await box.putAll(writes);
      if (removals.isNotEmpty) await box.deleteAll(removals);
      currentCursor = page.syncCursor ?? currentCursor;
      hasMore = page.hasMore && page.nextCursor != null;
      if (hasMore) currentCursor = page.nextCursor!;
    } while (hasMore);
    final metadata = rawMetadata == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(rawMetadata) as Map);
    await box.put(
      _snapshotMetadataKey,
      jsonEncode({
        ...metadata,
        'cursor': currentCursor,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'count': cached(scope: 'all').length,
      }),
    );
    _memoryCache.clear();
    return cached(scope: 'all');
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
      _memoryCache.clear();
      return mine;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> linkServerHydrantId(String localId, String serverId) async {
    final records = cached()
        .where((item) => item.hydrantId == localId)
        .toList(growable: false);
    if (records.isEmpty || records.every((item) => item.remoteId == serverId)) {
      return;
    }
    for (final item in records) {
      final linked = CachedHydrant.fromJson({
        ...item.toJson(),
        'remoteId': serverId,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await box.put(_key(item.scope, localId), jsonEncode(linked.toJson()));
    }
    _memoryCache.clear();
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
    void Function(int received, int? total)? onProgress,
  }) async {
    final requestWatch = Stopwatch()..start();
    try {
      var page = 1;
      var hasMore = true;
      int? expectedTotal;
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
        expectedTotal = total ?? expectedTotal;
        onProgress?.call(downloaded.length, expectedTotal);
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
      _memoryCache.clear();
      assert(() {
        // ignore: avoid_print
        print(
          '[HYDRANTS] syncStrategy=fallback '
          'requestDurationMs=${requestWatch.elapsedMilliseconds} '
          'itemsReceived=${downloaded.length} pagesReceived=${page - 1}',
        );
        return true;
      }());
      return cached(scope: scope);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<
    ({
      DateTime date,
      int submitted,
      int pending,
      List<String> completedInspectionIds,
      List<String> pendingInspectionIds,
    })
  >
  todayStats() async {
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/profile/today-stats',
      );
      final data = response.data ?? const {};
      return (
        date: DateTime.parse('${data['date']}').toLocal(),
        submitted: (data['completed'] as num?)?.toInt() ?? 0,
        pending: (data['pending'] as num?)?.toInt() ?? 0,
        completedInspectionIds:
            (data['completedInspectionIds'] as List? ?? const [])
                .map((value) => '$value')
                .toList(growable: false),
        pendingInspectionIds:
            (data['pendingInspectionIds'] as List? ?? const [])
                .map((value) => '$value')
                .toList(growable: false),
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
      _memoryCache.clear();
      return item;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
