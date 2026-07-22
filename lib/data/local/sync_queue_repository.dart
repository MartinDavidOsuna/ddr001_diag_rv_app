import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../domain/sync/sync_queue_item.dart';

abstract interface class SyncTransport {
  Future<void> send(SyncQueueItem item);
}

class SyncQueueRepository {
  const SyncQueueRepository(this.box);
  final Box<String> box;

  Future<void> save(SyncQueueItem item) =>
      box.put(item.id, jsonEncode(item.toJson()));

  List<SyncQueueItem> all() {
    final values = <SyncQueueItem>[];
    for (final raw in box.values) {
      try {
        values.add(
          SyncQueueItem.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          ),
        );
      } on Object {
        // Legacy values remain in the box and are surfaced by integrity audit.
      }
    }
    return values;
  }

  int get unreadableCount {
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
