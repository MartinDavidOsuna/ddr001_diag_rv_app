import 'package:ddr001diag/data/local/sync_queue_repository.dart';
import 'package:ddr001diag/domain/sync/sync_queue_item.dart';

class FakeSyncTransport implements SyncTransport {
  final sent = <SyncQueueItem>[];
  Object? error;

  @override
  Future<void> send(SyncQueueItem item) async {
    if (error case final Object failure) throw failure;
    sent.add(item);
  }
}
