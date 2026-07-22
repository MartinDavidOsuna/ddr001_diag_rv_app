import 'package:ddr001diag/domain/functional/functional_collection_models.dart';
import 'package:ddr001diag/domain/functional/functional_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 15);

  test('ValveRecord conserva UUID y relaciones independientes', () {
    final source = ValveRecord(
      id: 'uuid-valve-1',
      inspectionId: 'rf-1',
      order: 3,
      label: 'V3',
      type: 'mariposa',
      testIds: const ['test-a', 'test-b'],
      photoIds: const ['photo-a'],
      seriesIds: const ['series-a'],
      instrumentIds: const ['instrument-a'],
      createdAt: now,
      updatedAt: now,
    );
    final restored = ValveRecord.fromJson(source.toJson());
    expect(restored.id, 'uuid-valve-1');
    expect(restored.label, 'V3');
    expect(restored.testIds, ['test-a', 'test-b']);
    expect(restored.seriesIds, ['series-a']);
  });

  test('ReducerRun conserva aceptación e invalidación sin borrar historial', () {
    final source = ReducerRun(
      reducerRunId: 'uuid-run-1',
      reducerId: 'reducer-1',
      inspectionId: 'rf-1',
      order: 2,
      conditionKey: '0-1:L/s',
      flowRangeMin: 0,
      flowRangeMax: 1,
      accepted: true,
      invalidatedAt: now,
      invalidatedBy: 'supervisor',
      invalidationReason: 'Lectura inestable',
      createdAt: now,
      updatedAt: now,
    );
    final restored = ReducerRun.fromJson(source.toJson());
    expect(restored.reducerRunId, source.reducerRunId);
    expect(restored.accepted, isTrue);
    expect(restored.valid, isFalse);
    expect(restored.invalidationReason, 'Lectura inestable');
  });

  test('AlarmAttemptRecord conserva intento y latencia independiente', () {
    final source = AlarmAttemptRecord(
      id: 'uuid-alarm-2',
      inspectionId: 'rf-1',
      alarmType: 'fuga',
      attemptNumber: 2,
      generated: true,
      detectedLocally: true,
      reported: true,
      latencyMs: 450,
      result: 'approved',
      createdAt: now,
      updatedAt: now,
    );
    final restored = AlarmAttemptRecord.fromJson(source.toJson());
    expect(restored.id, 'uuid-alarm-2');
    expect(restored.attemptNumber, 2);
    expect(restored.latencyMs, 450);
  });

  test('InstrumentRecord lee brand/model heredados como texto libre', () {
    final restored = InstrumentRecord.fromJson({
      'id': 'instrument-legacy',
      'inspectionId': 'rf-1',
      'type': 'flowMeter',
      'brand': 'Marca Capturada',
      'model': 'Modelo Libre',
      'serialNumber': 'SN-ABC',
      'calibrationStatus': 'valid',
    });

    expect(restored.brandText, 'Marca Capturada');
    expect(restored.modelText, 'Modelo Libre');
    expect(restored.serialNumber, 'SN-ABC');
    expect(restored.toJson()['brandText'], 'Marca Capturada');
    expect(restored.toJson()['brand'], 'Marca Capturada');
  });

  test('snapshot conserva los datos históricos capturados', () {
    final snapshot = InstrumentSnapshot(
      instrumentId: 'instrument-1',
      type: 'flowMeter',
      assetCode: 'ACT-1',
      brandText: 'Libre',
      modelText: 'M1',
      serialNumber: 'SN1',
      measurementRange: '0-10',
      unit: 'L/s',
      accuracyClass: '1',
      calibrationStatus: 'valid',
      calibrationCertificate: 'CERT-1',
      condition: 'good',
      capturedAt: now,
    );
    final json = snapshot.toJson();
    expect(json['brandText'], 'Libre');
    expect(json['capturedAt'], '2026-07-15T00:00:00.000Z');
    expect(json['schemaVersion'], 1);
  });
}
