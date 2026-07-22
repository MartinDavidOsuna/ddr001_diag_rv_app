import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

class QuarantineRecord {
  const QuarantineRecord({
    required this.id,
    required this.sourceBox,
    required this.sourceKey,
    required this.originalDocument,
    required this.quarantinedAt,
    required this.errorType,
    required this.technicalMessage,
    required this.contentHash,
    this.recoverable = false,
    this.status = 'pendingReview',
    this.actions = const [],
    this.schemaVersion = 1,
  });
  final String id, sourceBox, sourceKey, originalDocument, errorType;
  final String technicalMessage, contentHash, status;
  final DateTime quarantinedAt;
  final bool recoverable;
  final List<String> actions;
  final int schemaVersion;
  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceBox': sourceBox,
    'sourceKey': sourceKey,
    'originalDocument': originalDocument,
    'quarantinedAt': quarantinedAt.toUtc().toIso8601String(),
    'errorType': errorType,
    'technicalMessage': technicalMessage,
    'contentHash': contentHash,
    'recoverable': recoverable,
    'status': status,
    'actions': actions,
    'schemaVersion': schemaVersion,
  };
}

class QuarantineRepository {
  const QuarantineRepository(this.box);
  final Box<String> box;

  Future<QuarantineRecord> preserve({
    required String sourceBox,
    required String sourceKey,
    required String originalDocument,
    required String errorType,
    required String technicalMessage,
    bool recoverable = false,
  }) async {
    final record = QuarantineRecord(
      id: const Uuid().v4(),
      sourceBox: sourceBox,
      sourceKey: sourceKey,
      originalDocument: originalDocument,
      quarantinedAt: DateTime.now().toUtc(),
      errorType: errorType,
      technicalMessage: technicalMessage,
      contentHash: sha256.convert(utf8.encode(originalDocument)).toString(),
      recoverable: recoverable,
    );
    await box.put(record.id, jsonEncode(record.toJson()));
    return record;
  }
}
