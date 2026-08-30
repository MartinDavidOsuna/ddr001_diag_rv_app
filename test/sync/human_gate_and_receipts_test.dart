import 'dart:convert';

import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/inspections/data/inspection_remote_repository.dart';
import 'package:ddr001diag/features/inspections/data/inspection_sync_coordinator.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:ddr001diag/features/inspections/data/sync_receipt_repository.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_human_gate_policy.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/foundation_fakes.dart';
import '../helpers/hive_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HiveTestEnvironment environment;

  setUp(() async {
    environment = HiveTestEnvironment();
    await environment.open();
  });

  tearDown(() => environment.close());

  group('human gate remoto', () {
    test('captura incompleta bloquea bootstrap, sync all y restart', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse('{"inspectionId":"server-1"}', 201),
      );
      final coordinator = _coordinator(adapter);
      final initial = _draft();

      for (var run = 0; run < 3; run++) {
        final restored = RvDraft.fromJson(initial.toJson());
        final result = await coordinator.synchronize(
          restored,
          submit: run == 1,
          forceRetry: true,
        );
        expect(result.serverInspectionId, isNull);
      }

      expect(adapter.requests, isEmpty);
      expect(
        const RvHumanGatePolicy().evaluate(initial).wireReason,
        'capture_incomplete_requires_technician',
      );
    });

    test('conflicto contractual bloquea toda escritura remota', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse('{"inspectionId":"server-1"}', 200),
      );
      final conflicted = _draft().copyWith(
        serverInspectionId: 'server-1',
        localStatus: RvLocalStatus.conflict,
        remoteStatus: 'conflict',
        conflictId: 'conflict-1',
      );

      final result = await _coordinator(
        adapter,
      ).synchronize(conflicted, submit: true, forceRetry: true);

      expect(result, same(conflicted));
      expect(adapter.requests, isEmpty);
      expect(
        const RvHumanGatePolicy().evaluate(conflicted).wireReason,
        'contract_conflict_requires_action',
      );
    });

    test('human-gated permite sólo reconciliación GET con receipt', () async {
      final adapter = FakeHttpAdapter((request) async {
        expect(request.method, 'GET');
        return jsonResponse(
          '{"inspectionId":"server-1","status":"submitted"}',
          200,
          headers: const {
            'x-request-id': ['read-request'],
          },
        );
      });
      final coordinator = _coordinator(adapter);
      final incomplete = _draft().copyWith(serverInspectionId: 'server-1');

      final reconciled = await coordinator.reconcileInspectionStateReadOnly(
        incomplete,
      );

      expect(reconciled.localStatus, incomplete.localStatus);
      expect(reconciled.submitStatus, incomplete.submitStatus);
      expect(adapter.requests, hasLength(1));
      final receipt = SyncReceiptRepository(
        Hive.box<String>('rv_sync_receipts_v1'),
      ).all().single;
      expect(receipt.outcome, SyncReceiptOutcome.reconciledByRead);
      expect(receipt.remoteState, 'submitted');
      expect(
        receipt.responseClassification,
        'capture_incomplete_requires_technician',
      );
      expect(receipt.httpStatus, 200);
      expect(receipt.requestId, 'read-request');
    });

    test('confirmación humana nunca omite evidencia faltante', () {
      final incomplete = _draft().copyWith(
        remoteMutationAuthorization: RvDraft.technicianSubmitAuthorization,
        remoteMutationAuthorizedAt: DateTime.utc(2026, 8, 29),
      );

      expect(
        const RvHumanGatePolicy().evaluate(incomplete).blocksRemoteMutation,
        isTrue,
      );
    });

    test('razón de bloqueo es aditiva y durable', () {
      final restored = RvDraft.fromJson(
        _draft()
            .copyWith(
              remoteMutationBlockReason:
                  'capture_incomplete_requires_technician',
            )
            .toJson(),
      );

      expect(
        restored.remoteMutationBlockReason,
        'capture_incomplete_requires_technician',
      );
      expect(
        restored
            .copyWith(clearRemoteMutationBlockReason: true)
            .remoteMutationBlockReason,
        isNull,
      );
    });

    test('confirmación humana persistida libera una revisión completa', () {
      final authorized = _completeDraft().copyWith(
        remoteMutationBlockReason: 'capture_incomplete_requires_technician',
        remoteMutationAuthorization: RvDraft.technicianSubmitAuthorization,
        remoteMutationAuthorizedAt: DateTime.utc(2026, 8, 29),
      );
      final restored = RvDraft.fromJson(authorized.toJson());

      expect(
        const RvHumanGatePolicy().evaluate(restored).blocksRemoteMutation,
        isFalse,
      );
      expect(
        restored.remoteMutationAuthorization,
        RvDraft.technicianSubmitAuthorization,
      );
    });

    test(
      'completar evidencia no libera un gate previo sin confirmación humana',
      () {
        final corrected = RvDraft.fromJson(
          _completeDraft()
              .copyWith(
                remoteMutationBlockReason:
                    'capture_incomplete_requires_technician',
              )
              .toJson(),
        );

        final decision = const RvHumanGatePolicy().evaluate(corrected);
        expect(decision.blocksRemoteMutation, isTrue);
        expect(decision.wireReason, 'capture_incomplete_requires_technician');
      },
    );
  });

  group('receipts por entidad', () {
    test(
      'persiste éxito sanitizado y deduplica reconciliación por GET',
      () async {
        final repository = SyncReceiptRepository(
          Hive.box<String>('rv_sync_receipts_v1'),
        );
        await repository.record(
          clientInspectionId: 'CLIENT-A',
          serverInspectionId: 'SERVER-A',
          operation: 'create_inspection',
          outcome: SyncReceiptOutcome.success,
          httpStatus: 201,
          requestId: 'request-safe',
          idempotencyKey: 'inspection-client-a',
          beforeLocalState: 'pendingCreate',
          afterLocalState: 'created',
          remoteState: 'in_progress',
          responseClassification: 'remote_created',
        );
        for (var i = 0; i < 2; i++) {
          await repository.record(
            clientInspectionId: 'client-a',
            serverInspectionId: 'server-a',
            operation: 'inspection_read_reconcile',
            outcome: SyncReceiptOutcome.reconciledByRead,
            httpStatus: 200,
            beforeLocalState: 'submitted',
            afterLocalState: 'submitted',
            remoteState: 'submitted',
            responseClassification: 'remote_terminal_state_confirmed',
          );
        }

        final receipts = repository.all();
        expect(receipts, hasLength(2));
        expect(receipts.first.httpStatus, 201);
        expect(receipts.first.requestId, 'request-safe');
        expect(jsonEncode(receipts.first.toJson()), isNot(contains('Bearer')));
      },
    );

    test('timeout y 5xx nunca se convierten en SUCCESS', () async {
      final repository = SyncReceiptRepository(
        Hive.box<String>('rv_sync_receipts_v1'),
      );
      for (final status in [null, 503]) {
        await repository.record(
          clientInspectionId: 'client-error',
          operation: 'submit_inspection',
          outcome: SyncReceiptOutcome.retryableError,
          httpStatus: status,
          beforeLocalState: 'submitPending',
          afterLocalState: 'syncError',
          responseClassification: status == null ? 'timeout' : 'serverError',
        );
      }
      expect(
        repository.all().where(
          (receipt) => receipt.outcome == SyncReceiptOutcome.success,
        ),
        isEmpty,
      );
    });

    test('retención queda acotada y no toca otras cajas', () async {
      final repository = SyncReceiptRepository(
        Hive.box<String>('rv_sync_receipts_v1'),
      );
      await Hive.box<String>('inspection_photos_v1').put('photo', 'evidence');
      for (var i = 0; i < SyncReceiptRepository.maxPerEntity + 5; i++) {
        await repository.record(
          clientInspectionId: 'client-retention',
          operation: 'attempt-$i',
          outcome: SyncReceiptOutcome.success,
          beforeLocalState: 'pending',
          afterLocalState: 'synced',
        );
      }
      expect(repository.all(), hasLength(SyncReceiptRepository.maxPerEntity));
      expect(Hive.box<String>('inspection_photos_v1').get('photo'), 'evidence');
    });

    test('repositorio remoto conserva status y request ID positivos', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(
          '{"inspectionId":"server-1","status":"in_progress"}',
          201,
          headers: const {
            'x-request-id': ['request-201'],
          },
        ),
      );
      final remote = _remote(adapter);

      final created = await remote.create(_draft());

      expect(created.evidence?.statusCode, 201);
      expect(created.evidence?.requestId, 'request-201');
      expect(created.evidence?.logicalEndpoint, '/inspections');
    });

    test('204 se conserva como evidencia positiva', () async {
      final adapter = FakeHttpAdapter(
        (_) async => jsonResponse(
          '',
          204,
          headers: const {
            'x-request-id': ['request-204'],
          },
        ),
      );

      final evidence = await _remote(adapter).saveAnswers('server-1', const [
        {'questionId': 'question-1', 'value': 'answer'},
      ], 'answers-client-a');

      expect(evidence?.statusCode, 204);
      expect(evidence?.requestId, 'request-204');
      expect(evidence?.method, 'PUT');
    });

    test('UUID mixed-case identifica la misma entidad al deduplicar', () async {
      final repository = SyncReceiptRepository(
        Hive.box<String>('rv_sync_receipts_v1'),
      );
      for (final id in ['CLIENT-A', 'client-a']) {
        await repository.record(
          clientInspectionId: id,
          serverInspectionId: 'SERVER-A',
          operation: 'inspection_read_reconcile',
          outcome: SyncReceiptOutcome.reconciledByRead,
          httpStatus: 200,
          beforeLocalState: 'submitted',
          afterLocalState: 'submitted',
          remoteState: 'submitted',
          responseClassification: 'remote_terminal_state_confirmed',
        );
      }

      expect(repository.all(), hasLength(1));
      expect(repository.all().single.clientInspectionId, 'client-a');
    });

    test(
      'crash tras éxito remoto converge por lectura sin inventar POST exitoso',
      () async {
        // La primera instancia representa el proceso que murió después de que
        // el servidor aplicó la operación pero antes de persistir el receipt.
        expect(
          SyncReceiptRepository(Hive.box<String>('rv_sync_receipts_v1')).all(),
          isEmpty,
        );
        final adapter = FakeHttpAdapter(
          (_) async => jsonResponse(
            '{"inspectionId":"server-1","status":"in_progress"}',
            200,
            headers: const {
              'x-request-id': ['recovery-read'],
            },
          ),
        );
        final restored = _draft().copyWith(
          serverInspectionId: 'server-1',
          localStatus: RvLocalStatus.submitPending,
          submitStatus: RvPartStatus.pending,
        );

        final result = await _coordinator(
          adapter,
        ).reconcileInspectionStateReadOnly(RvDraft.fromJson(restored.toJson()));

        expect(result.localStatus, RvLocalStatus.submitPending);
        final receipts = SyncReceiptRepository(
          Hive.box<String>('rv_sync_receipts_v1'),
        ).all();
        expect(receipts, hasLength(1));
        expect(receipts.single.outcome, SyncReceiptOutcome.reconciledByRead);
        expect(receipts.single.httpStatus, 200);
        expect(receipts.single.remoteState, 'in_progress');
        expect(receipts.single.requestId, 'recovery-read');
        expect(
          receipts.where(
            (receipt) => receipt.outcome == SyncReceiptOutcome.success,
          ),
          isEmpty,
        );
      },
    );
  });
}

InspectionSyncCoordinator _coordinator(FakeHttpAdapter adapter) {
  final visual = VisualInspectionRepository(
    documents: Hive.box<String>('visual_inspections_v1'),
    index: Hive.box<String>('active_inspection_index_v1'),
  );
  return InspectionSyncCoordinator(
    drafts: RvDraftRepository(visual),
    remote: _remote(adapter),
    photoBox: Hive.box<String>('inspection_photos_v1'),
    mediaQueue: Hive.box<String>('media_sync_queue'),
    receipts: SyncReceiptRepository(Hive.box<String>('rv_sync_receipts_v1')),
  );
}

InspectionRemoteRepository _remote(FakeHttpAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return InspectionRemoteRepository(
    ApiClient(
      config: AppConfig.fromEnvironment(
        environmentOverride: 'development',
        apiBaseUrlOverride: 'https://example.test/api/v1',
      ),
      sessionStorage: MemorySessionStorage(),
      dio: dio,
    ),
  );
}

RvDraft _draft() {
  final checklist = DynamicChecklist(
    id: 'checklist',
    code: 'RV',
    version: 1,
    title: 'RV',
    etag: 'etag',
    cachedAt: DateTime.utc(2026, 8, 29),
    sections: const [
      ChecklistSectionDefinition(
        id: 'section',
        code: 'GENERAL',
        title: 'General',
        order: 1,
        items: [
          ChecklistItemDefinition(
            id: 'required',
            code: 'REQUIRED',
            label: 'Requerida',
            type: 'text',
            required: true,
            order: 1,
          ),
        ],
      ),
    ],
  );
  return RvDraft(
    clientInspectionId: 'client-a',
    hydrantId: 'hydrant-a',
    accountNumber: 'qa-account',
    fieldSessionId: 'user-a',
    checklistId: checklist.id,
    checklistVersion: checklist.version,
    checklistSnapshot: checklist.toJson(),
    createdAt: DateTime.utc(2026, 8, 29),
    updatedAt: DateTime.utc(2026, 8, 29),
  );
}

RvDraft _completeDraft() {
  final now = DateTime.utc(2026, 8, 29);
  return _draft().copyWith(
    answers: {
      'required': RvAnswer(
        questionId: 'required',
        sectionId: 'section',
        answerType: 'text',
        value: 'synthetic answer',
        updatedAt: now,
      ),
    },
    photos: {
      for (final slot in requiredRvPhotoSlots)
        slot: [
          RvPhotoReference(
            photoId: 'photo-$slot',
            slotCode: slot,
            status: RvPhotoUploadStatus.pending,
          ),
        ],
    },
    location: RvLocationSample(
      latitude: 19,
      longitude: -99,
      source: 'synthetic',
      capturedAt: now,
    ),
    signal: RvSignalSample(
      generation: 'offline',
      connected: false,
      capturedAt: now,
    ),
  );
}
