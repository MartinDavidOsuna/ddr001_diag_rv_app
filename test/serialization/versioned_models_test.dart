import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/domain/integrity/operation_journal.dart';
import 'package:ddr001diag/domain/network/wifi_technical_assessment.dart';
import 'package:ddr001diag/domain/sync/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final utc = DateTime.utc(2026, 7, 15, 18, 30);

  test('VersionedJsonCodec lee envoltura nueva y documento heredado', () {
    final encoded = VersionedJsonCodec.encode(
      schemaVersion: 4,
      payload: {'status': 'inProgress', 'hydrantId': 'h-1'},
    );
    final modern = VersionedJsonCodec.decode(encoded);
    final legacy = VersionedJsonCodec.decode(
      '{"status":"draft","hydrantId":"legacy"}',
    );

    expect(modern.schemaVersion, 4);
    expect(modern.payload['status'], 'inProgress');
    expect(legacy.schemaVersion, 1);
    expect(legacy.payload['hydrantId'], 'legacy');
  });

  test('journal conserva enums string, fases y UTC en round-trip', () {
    final source = OperationJournalEntry(
      operationId: 'op-1',
      operationType: JournalOperationType.createVisualAndFunctional,
      entityIds: const ['rv-1', 'rf-1'],
      documentWrites: const ['rv-1', 'rf-1'],
      status: JournalStatus.needsRecovery,
      preparedAt: utc,
      needsRecoveryAt: utc.add(const Duration(seconds: 1)),
      lastError: 'interrumpido',
      recoveryAttempts: 2,
      actor: 'user-1',
      deviceId: 'device-1',
      correlationId: 'corr-1',
    );
    final restored = OperationJournalEntry.fromJson(source.toJson());

    expect(source.toJson()['operationType'], 'createVisualAndFunctional');
    expect(restored.operationType, source.operationType);
    expect(restored.status, JournalStatus.needsRecovery);
    expect(restored.preparedAt, utc);
    expect(restored.entityIds, source.entityIds);
  });

  test('SyncQueueItem aplica defaults seguros a documento heredado', () {
    final item = SyncQueueItem.fromJson({
      'id': 'queue-1',
      'entityType': 'functionalInspection',
      'entityId': 'rf-1',
      'createdAt': utc.toIso8601String(),
      'updatedAt': utc.toIso8601String(),
      'status': 'valorDesconocido',
    });

    expect(item.status, SyncQueueStatus.pending);
    expect(item.operation, 'upsert');
    expect(item.revision, 1);
    expect(item.idempotencyKey, 'functionalInspection:rf-1');
    expect(item.toJson()['status'], 'pending');
  });

  test('Wi-Fi distingue sin responder, No verificado y No aplica', () {
    final source = WifiTechnicalAssessment(
      wifiNearbyAnswer: TechnicalAssessmentAnswer.notVerified,
      wifiConnectionPossibleAnswer: TechnicalAssessmentAnswer.notApplicable,
      assessedAt: utc,
      comments: '  observación  ',
      schemaVersion: 2,
    );
    final restored = WifiTechnicalAssessment.fromJson(source.toJson());

    expect(restored.wifiNearbyAnswer, TechnicalAssessmentAnswer.notVerified);
    expect(
      restored.wifiConnectionPossibleAnswer,
      TechnicalAssessmentAnswer.notApplicable,
    );
    expect(restored.wifiSignalAdequateAnswer, isNull);
    expect(restored.comments, 'observación');
    expect(restored.assessedAt, utc);
  });
}
