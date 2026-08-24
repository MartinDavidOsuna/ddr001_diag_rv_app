import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/home/rv_work_dashboard.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 7);
  final checklist = DynamicChecklist(
    id: 'checklist',
    code: 'RV',
    version: 1,
    title: 'RV',
    etag: 'etag',
    cachedAt: now,
    sections: const [],
  );

  Hydrant hydrant(
    String id, {
    InspectionStatus status = InspectionStatus.pending,
  }) => Hydrant(
    id: id,
    code: id,
    locality: '',
    parcel: '',
    priority: PriorityLevel.medium,
    access: AccessType.vehicle,
    syncStatus: SyncStatus.synced,
    f02a: InspectionSummary(
      type: InspectionType.f02A,
      status: status,
      progress: 0,
    ),
    f02b: const InspectionSummary(
      type: InspectionType.f02B,
      status: InspectionStatus.notRequired,
      progress: 0,
    ),
    latitude: 0,
    longitude: 0,
  );

  RvDraft draft(
    String id,
    String hydrantId,
    RvLocalStatus status, {
    int minute = 0,
  }) => RvDraft(
    clientInspectionId: id,
    hydrantId: hydrantId,
    accountNumber: hydrantId,
    fieldSessionId: 'user',
    checklistId: checklist.id,
    checklistVersion: checklist.version,
    checklistSnapshot: checklist.toJson(),
    createdAt: now,
    updatedAt: now.add(Duration(minutes: minute)),
    localStatus: status,
  );

  test('counts each hydrant once using its newest active draft', () {
    final grouped = RvWorkDashboardProjection.byHydrant(
      drafts: [
        draft('old', 'h1', RvLocalStatus.submitted),
        draft('new', 'h1', RvLocalStatus.pendingAnswers, minute: 1),
      ],
      hydrants: [hydrant('h1')],
    );
    expect(grouped[RvWorkGroup.pendingSync], {'h1'});
    expect(grouped.values.expand((ids) => ids).length, 1);
  });

  test('does not count assigned hydrants without work', () {
    final grouped = RvWorkDashboardProjection.byHydrant(
      drafts: const [],
      hydrants: [hydrant('untouched')],
    );
    expect(grouped.values.expand((ids) => ids), isEmpty);
  });

  test('a remote completed hydrant remains visible as submitted', () {
    final grouped = RvWorkDashboardProjection.byHydrant(
      drafts: const [],
      hydrants: [hydrant('done', status: InspectionStatus.completed)],
    );
    expect(grouped[RvWorkGroup.submitted], {'done'});
  });

  test(
    'a submitted local report remains in personal work after assignment removal',
    () {
      final completed = hydrant('1001', status: InspectionStatus.completed);
      final visible = RvWorkDashboardProjection.personalWorkHydrants(
        assigned: const [],
        catalog: [
          completed,
          hydrant('reviewed-by-other', status: InspectionStatus.completed),
        ],
        drafts: [draft('sent', '1001', RvLocalStatus.submitted)],
      );

      expect(visible.map((item) => item.id), ['1001']);
      final grouped = RvWorkDashboardProjection.byHydrant(
        drafts: [draft('sent', '1001', RvLocalStatus.submitted)],
        hydrants: visible,
      );
      expect(grouped[RvWorkGroup.submitted], {'1001'});
      expect(
        RvWorkDashboardProjection.recent(
          drafts: [draft('sent', '1001', RvLocalStatus.submitted)],
          hydrants: visible,
        ).map((item) => item.id),
        ['1001'],
      );
    },
  );

  test('an additional local review remains pending over an official report', () {
    final grouped = RvWorkDashboardProjection.byHydrant(
      drafts: [draft('additional', 'done', RvLocalStatus.pendingAnswers)],
      hydrants: [hydrant('done', status: InspectionStatus.completed)],
    );
    expect(grouped[RvWorkGroup.submitted], isEmpty);
    expect(grouped[RvWorkGroup.pendingSync], {'done'});
  });

  test('authorized version work remains pending over an official report', () {
    final base = draft('version', 'done', RvLocalStatus.pendingVersion);
    final version = RvDraft.fromJson({
      ...base.toJson(),
      'hasPendingChanges': true,
      'baseVersionId': 'official-version',
    });
    final grouped = RvWorkDashboardProjection.byHydrant(
      drafts: [version],
      hydrants: [hydrant('done', status: InspectionStatus.completed)],
    );
    expect(grouped[RvWorkGroup.pendingSync], {'done'});
  });

  test('recent reviews exclude untouched and deleted local hydrants', () {
    final local = hydrant('local');
    final untouched = hydrant('untouched');
    final remote = hydrant('remote', status: InspectionStatus.completed);

    expect(
      RvWorkDashboardProjection.recent(
        drafts: [draft('draft', 'local', RvLocalStatus.pendingAnswers)],
        hydrants: [local, untouched, remote],
      ).map((item) => item.id),
      ['local', 'remote'],
    );
    expect(
      RvWorkDashboardProjection.recent(
        drafts: const [],
        hydrants: [local, untouched, remote],
      ).map((item) => item.id),
      ['remote'],
    );
  });
}
