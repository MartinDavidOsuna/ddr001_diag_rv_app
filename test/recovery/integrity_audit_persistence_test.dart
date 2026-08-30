import 'dart:convert';

import 'package:ddr001diag/data/local/integrity_audit_service.dart';
import 'package:ddr001diag/core/persistence/versioned_json_codec.dart';
import 'package:ddr001diag/domain/integrity/integrity_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  late HiveTestEnvironment environment;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open(boxes: ['integrity_audit_reports_v1']);
  });

  tearDown(() => environment.close());

  IntegrityAuditReport report(
    String id,
    DateTime timestamp, {
    bool issue = true,
  }) {
    return IntegrityAuditReport(
      id: id,
      startedAt: timestamp,
      completedAt: timestamp.add(const Duration(milliseconds: 1)),
      issues: issue
          ? [
              IntegrityIssue(
                id: 'volatile-$id',
                type: IntegrityIssueType.photoWithoutFile,
                severity: IntegritySeverity.high,
                entityType: 'photo',
                entityId: 'photo-1',
                userMessage: 'Fotografía faltante.',
                technicalMessage: 'missing',
                recommendedAction: RecoveryAction.markMissingLocal,
              ),
            ]
          : const [],
    );
  }

  test('auditoría equivalente no persiste IDs ni timestamps nuevos', () async {
    final box = Hive.box<String>('integrity_audit_reports_v1');
    const service = IntegrityAuditService();
    expect(
      await service.persistIfChanged(
        box,
        report('first', DateTime.utc(2026, 8, 28)),
        stateFingerprint: 'state-a',
      ),
      isTrue,
    );
    final before = Map<Object, String>.from(box.toMap());
    final events = <BoxEvent>[];
    final subscription = box.watch().listen(events.add);

    final changed = await service.persistIfChanged(
      box,
      report('second', DateTime.utc(2026, 8, 29)),
      stateFingerprint: 'state-a',
    );
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(changed, isFalse);
    expect(events, isEmpty);
    expect(box.toMap(), before);
  });

  test('auditoría materialmente distinta sí se conserva', () async {
    final box = Hive.box<String>('integrity_audit_reports_v1');
    const service = IntegrityAuditService();
    await service.persistIfChanged(
      box,
      report('first', DateTime.utc(2026, 8, 28)),
      stateFingerprint: 'state-a',
    );

    expect(
      await service.persistIfChanged(
        box,
        report('resolved', DateTime.utc(2026, 8, 29), issue: false),
        stateFingerprint: 'state-b',
      ),
      isTrue,
    );
    expect(box, hasLength(2));
  });

  test('incidencia resuelta y reaparecida conserva tres auditorías', () async {
    final box = Hive.box<String>('integrity_audit_reports_v1');
    const service = IntegrityAuditService();
    await service.persistIfChanged(
      box,
      report('first', DateTime.utc(2026, 8, 28)),
      stateFingerprint: 'missing-file-a',
    );
    await service.persistIfChanged(
      box,
      report('resolved', DateTime.utc(2026, 8, 29), issue: false),
      stateFingerprint: 'file-present',
    );
    await service.persistIfChanged(
      box,
      report('reappeared', DateTime.utc(2026, 8, 30)),
      stateFingerprint: 'missing-file-a-again',
    );

    expect(box, hasLength(3));
    expect(box.keys, containsAll(['first', 'resolved', 'reappeared']));
  });

  test('mismas incidencias con estado material distinto se auditan', () async {
    final box = Hive.box<String>('integrity_audit_reports_v1');
    const service = IntegrityAuditService();
    await service.persistIfChanged(
      box,
      report('first', DateTime.utc(2026, 8, 28)),
      stateFingerprint: 'photo-hash-a-size-10',
    );

    expect(
      await service.persistIfChanged(
        box,
        report('changed', DateTime.utc(2026, 8, 29)),
        stateFingerprint: 'photo-hash-b-size-11',
      ),
      isTrue,
    );
    expect(box, hasLength(2));
  });

  test(
    'selecciona auditoría más reciente por fecha, no por orden de clave',
    () async {
      final box = Hive.box<String>('integrity_audit_reports_v1');
      const service = IntegrityAuditService();
      await service.persistIfChanged(
        box,
        report('zzz-old', DateTime.utc(2026, 8, 28)),
        stateFingerprint: 'missing-file',
      );
      await service.persistIfChanged(
        box,
        report('aaa-newest', DateTime.utc(2026, 8, 29), issue: false),
        stateFingerprint: 'file-present',
      );
      final before = Map<Object, String>.from(box.toMap());

      expect(
        await service.persistIfChanged(
          box,
          report('equivalent', DateTime.utc(2026, 8, 30), issue: false),
          stateFingerprint: 'file-present',
        ),
        isFalse,
      );
      expect(box.toMap(), before);
    },
  );

  test('desempata fechas iguales por id y no por orden Hive', () async {
    final box = Hive.box<String>('integrity_audit_reports_v1');
    const service = IntegrityAuditService();
    final timestamp = DateTime.utc(2026, 8, 29);
    final olderId = report('aaa', timestamp, issue: true);
    final latestId = report('zzz', timestamp, issue: false);
    await box.put(
      'storage-z-first',
      jsonEncode({...latestId.toJson(), 'stateFingerprint': 'resolved'}),
    );
    await box.put(
      'storage-a-last',
      jsonEncode({...olderId.toJson(), 'stateFingerprint': 'missing'}),
    );

    expect(
      await service.persistIfChanged(
        box,
        report('next', timestamp.add(const Duration(days: 1)), issue: false),
        stateFingerprint: 'resolved',
      ),
      isFalse,
    );
  });

  test('auditoría legacy sin completedAt usa startedAt', () async {
    final box = Hive.box<String>('integrity_audit_reports_v1');
    const service = IntegrityAuditService();
    final old = report('old-complete', DateTime.utc(2026, 8, 28));
    final legacy = report(
      'legacy-new',
      DateTime.utc(2026, 8, 29),
      issue: false,
    ).toJson()..remove('completedAt');
    await box.put(
      'newer-storage-first',
      jsonEncode({...legacy, 'stateFingerprint': 'resolved'}),
    );
    await box.put(
      'older-storage-last',
      jsonEncode({...old.toJson(), 'stateFingerprint': 'missing'}),
    );

    expect(
      await service.persistIfChanged(
        box,
        report('next', DateTime.utc(2026, 8, 30), issue: false),
        stateFingerprint: 'resolved',
      ),
      isFalse,
    );
  });

  test('fechas inválidas tienen desempate estable por id y clave', () async {
    final box = Hive.box<String>('integrity_audit_reports_v1');
    const service = IntegrityAuditService();
    Map<String, dynamic> raw(String id, bool issue, String fingerprint) => {
      ...report(id, DateTime.utc(2026), issue: issue).toJson(),
      'startedAt': 'invalid',
      'completedAt': 'invalid',
      'stateFingerprint': fingerprint,
    };
    await box.put('z-storage', jsonEncode(raw('zzz', false, 'resolved')));
    await box.put('a-storage', jsonEncode(raw('aaa', true, 'missing')));

    expect(
      await service.persistIfChanged(
        box,
        report('next', DateTime.utc(2026, 8, 30), issue: false),
        stateFingerprint: 'resolved',
      ),
      isFalse,
    );
  });

  test('dos scopes del mismo hidrante se auditan por documento', () async {
    await environment.close();
    environment = HiveTestEnvironment();
    await environment.open();
    final documents = Hive.box<String>('visual_inspections_v1');
    final index = Hive.box<String>('active_inspection_index_v1');
    for (final user in ['user-a', 'user-b']) {
      await documents.put(
        'inspection-$user',
        VersionedJsonCodec.encode(
          schemaVersion: 1,
          payload: {
            'id': 'inspection-$user',
            'hydrantId': 'shared-hydrant',
            'status': 'inProgress',
            'createdBy': user,
            'dataScope': {
              'environment': 'qa',
              'accountId': 'fixtures',
              'ownerUserId': user,
            },
          },
        ),
      );
    }
    await index.put(
      'qa/fixtures/user-a/shared-hydrant/f02A',
      'inspection-user-a',
    );

    final issues = const IntegrityAuditService()
        .runLightweight()
        .issues
        .where(
          (issue) =>
              issue.type == IntegrityIssueType.activeDocumentWithoutIndex,
        )
        .toList();
    expect(issues, hasLength(1));
    expect(issues.single.entityId, 'inspection-user-b');
    expect(issues.single.recommendedAction, RecoveryAction.recreateIndex);
  });

  test('auditor usa fallback no vacío y hydrant canonicalizado', () async {
    await environment.close();
    environment = HiveTestEnvironment();
    await environment.open();
    await Hive.box<String>('visual_inspections_v1').put(
      'inspection-canonical',
      VersionedJsonCodec.encode(
        schemaVersion: 1,
        payload: {
          'id': 'inspection-canonical',
          'hydrantId': ' A+B/01 ',
          'status': 'inProgress',
          'createdBy': ' CREATED-1 ',
          'inspectorId': 'INSPECTOR-1',
          'dataScope': {
            'environment': ' Production ',
            'accountId': ' DDR 001 ',
            'ownerUserId': '   ',
          },
        },
      ),
    );
    await Hive.box<String>('active_inspection_index_v1').put(
      'production/ddr%20001/created-1/a%2Bb%2F01/f02A',
      'inspection-canonical',
    );

    final missingIndexIssues = const IntegrityAuditService()
        .runLightweight()
        .issues
        .where(
          (issue) =>
              issue.type == IntegrityIssueType.activeDocumentWithoutIndex,
        );
    expect(missingIndexIssues, isEmpty);
  });
}
