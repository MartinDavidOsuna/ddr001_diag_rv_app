import 'dart:io';

import 'package:ddr001diag/core/security/local_data_scope.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:ddr001diag/qa/qa_bootstrap_lab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qa-bootstrap-lab-');
    Hive.init(root.path);
    for (final name in {
      ...qaObservedBootstrapBoxes,
      ...qaBootstrapSupportBoxes,
      'sync_queue',
      'qa_fixture_runtime_v1',
    }) {
      await Hive.openBox<String>(name);
    }
  });

  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('ejecuta pipeline compartido y bootstraps 2/3 son no-op', () async {
    final visual =
        VisualInspectionRepository(
          documents: Hive.box<String>('visual_inspections_v1'),
          index: Hive.box<String>('active_inspection_index_v1'),
        )..setAccessScope(
          const LocalDataScope(
            environment: 'qa',
            accountId: 'qa-fixtures',
            userId: 'qa-user',
            brigadeId: 'qa-brigade',
            role: 'field',
          ),
        );
    final lab = QaBootstrapLab(
      visualRepository: visual,
      drafts: RvDraftRepository(visual),
      runtimeBox: Hive.box<String>('qa_fixture_runtime_v1'),
    );
    await lab.createLegacyRecoveryWithoutFingerprint();

    final first = await lab.run('bootstrap-1');
    final second = await lab.run('bootstrap-2');
    final third = await lab.run('bootstrap-3');

    expect(first.totalWrites, greaterThan(0));
    expect(second.totalWrites, 0);
    expect(third.totalWrites, 0);
    expect(second.fingerprintBefore, second.fingerprintAfter);
    expect(third.fingerprintBefore, third.fingerprintAfter);
    expect(second.recoveryRunId, isNotEmpty);
    expect(
      Hive.box<String>('qa_fixture_runtime_v1').keys,
      containsAll([
        'bootstrapReport:bootstrap-1',
        'bootstrapReport:bootstrap-2',
        'bootstrapReport:bootstrap-3',
      ]),
    );
  });

  test(
    'dos bootstraps concurrentes se serializan sin duplicar trabajo',
    () async {
      final visual =
          VisualInspectionRepository(
            documents: Hive.box<String>('visual_inspections_v1'),
            index: Hive.box<String>('active_inspection_index_v1'),
          )..setAccessScope(
            const LocalDataScope(
              environment: 'qa',
              accountId: 'qa-fixtures',
              userId: 'qa-user',
              brigadeId: 'qa-brigade',
              role: 'field',
            ),
          );
      final lab = QaBootstrapLab(
        visualRepository: visual,
        drafts: RvDraftRepository(visual),
        runtimeBox: Hive.box<String>('qa_fixture_runtime_v1'),
      );
      await lab.createLegacyRecoveryWithoutFingerprint();

      final reports = await Future.wait([
        lab.run('concurrent-a'),
        lab.run('concurrent-b'),
      ]);
      final next = await lab.run('after-concurrent');

      expect(reports.where((report) => report.totalWrites > 0), hasLength(1));
      expect(reports.where((report) => report.totalWrites == 0), hasLength(1));
      expect(next.totalWrites, 0);
      expect(next.fingerprintBefore, next.fingerprintAfter);
      expect(Hive.box<String>('rv_recovery_snapshots_v1'), hasLength(1));
    },
  );

  test(
    'observador habilitado o deshabilitado no cambia estado funcional',
    () async {
      final visual =
          VisualInspectionRepository(
            documents: Hive.box<String>('visual_inspections_v1'),
            index: Hive.box<String>('active_inspection_index_v1'),
          )..setAccessScope(
            const LocalDataScope(
              environment: 'qa',
              accountId: 'qa-fixtures',
              userId: 'qa-user',
              brigadeId: 'qa-brigade',
              role: 'field',
            ),
          );
      final observed = QaBootstrapLab(
        visualRepository: visual,
        drafts: RvDraftRepository(visual),
        runtimeBox: Hive.box<String>('qa_fixture_runtime_v1'),
      );
      await observed.createLegacyRecoveryWithoutFingerprint();
      await observed.run('converge');
      final boxes = {
        for (final name in qaObservedBootstrapBoxes)
          name: Hive.box<String>(name),
      };
      final before = {
        for (final name in qaFunctionalBootstrapBoxes)
          name: Map<Object, String>.from(boxes[name]!.toMap()),
      };

      final observedNoop = await observed.run('observed-noop');
      final unobservedNoop = await QaBootstrapLab(
        visualRepository: visual,
        drafts: RvDraftRepository(visual),
        runtimeBox: Hive.box<String>('qa_fixture_runtime_v1'),
        observeWrites: false,
      ).run('unobserved-noop');

      expect(observedNoop.totalWrites, 0);
      expect(unobservedNoop.totalWrites, 0);
      expect(observedNoop.fingerprintAfter, unobservedNoop.fingerprintAfter);
      for (final entry in before.entries) {
        expect(boxes[entry.key]!.toMap(), entry.value, reason: entry.key);
      }
    },
  );
}
