import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

enum SyncReceiptOutcome {
  success,
  retryableError,
  conflict,
  remoteAlreadyApplied,
  reconciledByRead,
}

class SyncReceipt {
  const SyncReceipt({
    required this.id,
    required this.clientInspectionId,
    required this.operation,
    required this.outcome,
    required this.timestampUtc,
    required this.beforeLocalState,
    required this.afterLocalState,
    this.serverInspectionId,
    this.mediaId,
    this.httpStatus,
    this.requestId,
    this.idempotencyKey,
    this.remoteState,
    this.responseClassification,
    this.attempt = 1,
    this.schemaVersion = 1,
  });

  final String id;
  final String clientInspectionId;
  final String? serverInspectionId;
  final String? mediaId;
  final String operation;
  final SyncReceiptOutcome outcome;
  final int? httpStatus;
  final String? requestId;
  final DateTime timestampUtc;
  final int attempt;
  final String? idempotencyKey;
  final String beforeLocalState;
  final String afterLocalState;
  final String? remoteState;
  final String? responseClassification;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'clientInspectionId': clientInspectionId.toLowerCase(),
    'serverInspectionId': serverInspectionId,
    'mediaId': mediaId,
    'operation': operation,
    'outcome': outcome.name,
    'httpStatus': httpStatus,
    'requestId': requestId,
    'timestampUtc': timestampUtc.toUtc().toIso8601String(),
    'attempt': attempt,
    'idempotencyKey': idempotencyKey,
    'beforeLocalState': beforeLocalState,
    'afterLocalState': afterLocalState,
    'remoteState': remoteState,
    'responseClassification': responseClassification,
  };

  factory SyncReceipt.fromJson(Map<String, dynamic> json) => SyncReceipt(
    id: '${json['id']}',
    clientInspectionId: '${json['clientInspectionId']}',
    serverInspectionId: json['serverInspectionId']?.toString(),
    mediaId: json['mediaId']?.toString(),
    operation: '${json['operation']}',
    outcome: SyncReceiptOutcome.values.firstWhere(
      (value) => value.name == json['outcome'],
      orElse: () => SyncReceiptOutcome.retryableError,
    ),
    httpStatus: (json['httpStatus'] as num?)?.toInt(),
    requestId: json['requestId']?.toString(),
    timestampUtc: DateTime.parse('${json['timestampUtc']}').toUtc(),
    attempt: (json['attempt'] as num?)?.toInt() ?? 1,
    idempotencyKey: json['idempotencyKey']?.toString(),
    beforeLocalState: '${json['beforeLocalState']}',
    afterLocalState: '${json['afterLocalState']}',
    remoteState: json['remoteState']?.toString(),
    responseClassification: json['responseClassification']?.toString(),
    schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
  );
}

class SyncReceiptRepository {
  SyncReceiptRepository(this.box);

  static const maxPerEntity = 50;
  static const maxTotal = 2000;
  final Box<String> box;

  List<SyncReceipt> all() {
    final values = <SyncReceipt>[];
    for (final raw in box.values) {
      try {
        values.add(
          SyncReceipt.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          ),
        );
      } on Object {
        // Unknown future/corrupt rows remain untouched for forensic recovery.
      }
    }
    values.sort((a, b) => a.timestampUtc.compareTo(b.timestampUtc));
    return values;
  }

  Future<SyncReceipt> record({
    required String clientInspectionId,
    required String operation,
    required SyncReceiptOutcome outcome,
    required String beforeLocalState,
    required String afterLocalState,
    String? serverInspectionId,
    String? mediaId,
    int? httpStatus,
    String? requestId,
    String? idempotencyKey,
    String? remoteState,
    String? responseClassification,
    int attempt = 1,
    DateTime? timestampUtc,
  }) async {
    final normalizedId = clientInspectionId.trim().toLowerCase();
    final existing = all().where(
      (receipt) =>
          receipt.clientInspectionId.toLowerCase() == normalizedId &&
          receipt.operation == operation &&
          receipt.outcome == outcome &&
          receipt.serverInspectionId?.toLowerCase() ==
              serverInspectionId?.toLowerCase() &&
          receipt.mediaId?.toLowerCase() == mediaId?.toLowerCase() &&
          receipt.idempotencyKey == idempotencyKey &&
          receipt.remoteState == remoteState &&
          receipt.afterLocalState == afterLocalState,
    );
    if (existing.isNotEmpty &&
        const {
          SyncReceiptOutcome.reconciledByRead,
          SyncReceiptOutcome.remoteAlreadyApplied,
        }.contains(outcome)) {
      return existing.last;
    }
    final now = (timestampUtc ?? DateTime.now()).toUtc();
    final receipt = SyncReceipt(
      id: const Uuid().v4(),
      clientInspectionId: normalizedId,
      serverInspectionId: serverInspectionId,
      mediaId: mediaId,
      operation: operation,
      outcome: outcome,
      httpStatus: httpStatus,
      requestId: requestId,
      timestampUtc: now,
      attempt: attempt,
      idempotencyKey: idempotencyKey,
      beforeLocalState: beforeLocalState,
      afterLocalState: afterLocalState,
      remoteState: remoteState,
      responseClassification: responseClassification,
    );
    await box.put(receipt.id, jsonEncode(receipt.toJson()));
    await _enforceRetention(normalizedId);
    return receipt;
  }

  Future<void> _enforceRetention(String entityId) async {
    final values = all();
    final entity = values
        .where((value) => value.clientInspectionId == entityId)
        .toList();
    for (final receipt in entity.take(
      entity.length > maxPerEntity ? entity.length - maxPerEntity : 0,
    )) {
      await box.delete(receipt.id);
    }
    final remaining = all();
    for (final receipt in remaining.take(
      remaining.length > maxTotal ? remaining.length - maxTotal : 0,
    )) {
      await box.delete(receipt.id);
    }
  }
}
