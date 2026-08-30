import 'dart:convert';

import 'package:ddr001diag/data/local/media_work_item_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lee string legacy y escribe JSON versionado', () {
    final item = MediaWorkItemCodec.decode('photo-1', 'pendingUpload');
    expect(item.status, 'pendingUpload');
    expect(item.legacyRaw, 'pendingUpload');
    final json = jsonDecode(MediaWorkItemCodec.encode(item)) as Map;
    expect(json['schemaVersion'], 2);
    expect(json['status'], 'pendingUpload');
  });

  test('lee JSON actual sin perder identidad', () {
    final item = MediaWorkItemCodec.decode(
      'key',
      '{"schemaVersion":2,"photoId":"photo-2","status":"verify"}',
    );
    expect(item.photoId, 'photo-2');
    expect(item.status, 'verify');
    expect(item.schemaVersion, 2);
  });

  test('FormatException conserva el valor como trabajo recuperable', () {
    const raw = '{json truncado';
    final item = MediaWorkItemCodec.decode('photo-3', raw);
    expect(item.photoId, 'photo-3');
    expect(item.status, raw);
    expect(item.legacyRaw, raw);
    expect(MediaWorkItemCodec.encode(item), contains('json truncado'));
  });

  test('updatedAt aislado no crea transición operativa', () {
    const raw =
        '{"schemaVersion":2,"kind":"mediaWorkItem",'
        '"photoId":"PHOTO-1","inspectionId":"REVIEW-1",'
        '"slotCode":"front","status":"verify",'
        '"updatedAt":"2026-08-01T00:00:00Z"}';

    expect(
      MediaWorkItemCodec.reconcilePending(
        'photo-1',
        raw,
        photoId: 'photo-1',
        inspectionId: 'review-1',
        slotCode: 'front',
        status: 'verify',
      ),
      isNull,
    );
  });

  test('retry backoff error lease y dependencias se preservan', () {
    const raw =
        '{"schemaVersion":2,"kind":"mediaWorkItem",'
        '"photoId":"photo-1","inspectionId":"review-1",'
        '"slotCode":"front","status":"pendingUpload","attempts":4,'
        '"nextRetryAt":"2026-08-30T00:00:00Z","lastError":"timeout",'
        '"leaseOwner":"worker-a","dependencies":["normalize"],'
        '"updatedAt":"2026-08-01T00:00:00Z"}';

    final changed = MediaWorkItemCodec.reconcilePending(
      'photo-1',
      raw,
      photoId: 'photo-1',
      inspectionId: 'review-1',
      slotCode: 'front',
      status: 'verify',
    );
    final decoded = jsonDecode(changed!) as Map;

    expect(decoded['status'], 'verify');
    expect(decoded['attempts'], 4);
    expect(decoded['nextRetryAt'], '2026-08-30T00:00:00Z');
    expect(decoded['lastError'], 'timeout');
    expect(decoded['leaseOwner'], 'worker-a');
    expect(decoded['dependencies'], ['normalize']);
    expect(decoded['updatedAt'], isNot('2026-08-01T00:00:00Z'));
  });

  test('schema futuro no se degrada ni sobrescribe', () {
    const raw =
        '{"schemaVersion":3,"kind":"mediaWorkItem",'
        '"photoId":"photo-1","status":"futureWorkerState",'
        '"futureMarker":"must-preserve"}';
    expect(
      MediaWorkItemCodec.reconcilePending(
        'photo-1',
        raw,
        photoId: 'photo-1',
        inspectionId: 'review-1',
        slotCode: 'front',
        status: 'verify',
      ),
      isNull,
    );
  });
}
