import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../domain/sync/sync_queue_item.dart';
import '../../core/security/local_data_scope.dart';

abstract interface class SyncTransport {
  Future<void> send(SyncQueueItem item);
}

class SyncQueueRepository {
  SyncQueueRepository(this.box);
  final Box<String> box;
  LocalDataScope? _scope;
  bool _scopeConfigured = false;

  void setAccessScope(LocalDataScope? scope) {
    _scope = scope;
    _scopeConfigured = true;
  }

  bool isAccessible(SyncQueueItem item) {
    if (!_scopeConfigured) return true;
    final scope = _scope;
    if (scope == null || !scope.isUsable) return false;
    return item.ownerUserId == scope.userId &&
        item.accountId == scope.accountId &&
        item.environment == scope.environment;
  }

  Future<void> save(SyncQueueItem item) =>
      box.put(item.id, jsonEncode(item.toJson()));

  Future<void> markSynced(String id) async {
    final raw = box.get(id);
    if (raw == null) return;
    final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    value['status'] = SyncQueueStatus.synced.name;
    value['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    value['lastError'] = null;
    await box.put(id, jsonEncode(value));
  }

  Future<void> delete(String id) => box.delete(id);

  List<SyncQueueItem> all() {
    final values = <SyncQueueItem>[];
    for (final raw in box.values) {
      try {
        final item = SyncQueueItem.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (isAccessible(item)) values.add(item);
      } on Object {
        // Legacy values remain in the box and are surfaced by integrity audit.
      }
    }
    return values;
  }

  int get unreadableCount {
    if (_scopeConfigured) return 0;
    var count = 0;
    for (final raw in box.values) {
      try {
        SyncQueueItem.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } on Object {
        count++;
      }
    }
    return count;
  }

  bool get allSynchronized =>
      all().every((item) => item.status == SyncQueueStatus.synced);

  List<SyncQueueItem> ready() {
    final items = all();
    final syncedIds = {
      for (final item in items)
        if (item.status == SyncQueueStatus.synced) item.id,
    };
    return items
        .where(
          (item) =>
              item.status == SyncQueueStatus.pending &&
              item.dependencyIds.every(syncedIds.contains),
        )
        .toList();
  }
}
