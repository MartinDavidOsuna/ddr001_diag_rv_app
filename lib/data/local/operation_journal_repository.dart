import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../domain/integrity/operation_journal.dart';

class OperationJournalRepository {
  const OperationJournalRepository(this.box);
  final Box<String> box;

  Future<void> save(OperationJournalEntry value) =>
      box.put(value.operationId, jsonEncode(value.toJson()));

  OperationJournalEntry? find(String id) {
    final raw = box.get(id);
    if (raw == null) return null;
    return OperationJournalEntry.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  List<OperationJournalEntry> pending() {
    final values = <OperationJournalEntry>[];
    for (final raw in box.values) {
      try {
        final value = OperationJournalEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (value.status != JournalStatus.committed &&
            value.status != JournalStatus.quarantined) {
          values.add(value);
        }
      } on Object {
        // IntegrityAuditService will quarantine unreadable journal entries.
      }
    }
    return values;
  }
}
