import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/home/all_reviews_page.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Todas mis revisiones no colapsa trabajos del mismo hidrante', (
    tester,
  ) async {
    final first = _draft('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    final second = _draft('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllReviewsList(
            drafts: [first, second],
            visibleHydrantIds: const {'hydrant-1'},
          ),
        ),
      ),
    );

    expect(find.text('Cuenta 1011'), findsNWidgets(2));
    expect(find.textContaining('Revisión aaaaaaaa'), findsOneWidget);
    expect(find.textContaining('Revisión bbbbbbbb'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
  });

  testWidgets('un trabajo fuera del catálogo sigue visible y se puede abrir', (
    tester,
  ) async {
    RvDraft? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllReviewsList(
            drafts: [_draft('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')],
            visibleHydrantIds: const {},
            onOpen: (draft) => opened = draft,
          ),
        ),
      ),
    );

    expect(find.textContaining('fuera del catálogo actual'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    expect(opened?.clientInspectionId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  });

  testWidgets(
    'historial navega por clientInspectionId sin depender del hidrante master',
    (tester) async {
      final historical = _draft('fbe58619-d848-4150-be02-15f496d2d566')
          .copyWith(
            localStatus: RvLocalStatus.submitted,
            remoteStatus: 'submitted',
          );
      String? destination;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllReviewsList(
              drafts: [historical],
              visibleHydrantIds: const {'hydrant-1'},
              onOpen: (draft) => destination = historyReviewLocation(draft),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(ValueKey('review-${historical.clientInspectionId}')),
      );

      expect(destination, '/reviews/fbe58619-d848-4150-be02-15f496d2d566');
      expect(destination, isNot(contains('/hydrants/')));
      expect(find.text('Cuenta 1011'), findsOneWidget);
      expect(find.textContaining('Historial · solo lectura'), findsOneWidget);
    },
  );

  testWidgets('27 revisiones conservan identidad independiente y lista lazy', (
    tester,
  ) async {
    final drafts = List.generate(
      27,
      (index) => _draft('review-${index.toString().padLeft(4, '0')}'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AllReviewsList(
            drafts: drafts,
            visibleHydrantIds: const {'hydrant-1'},
          ),
        ),
      ),
    );

    expect(find.byType(ListView), findsOneWidget);
    expect(find.byKey(const ValueKey('review-review-0000')), findsOneWidget);
    expect(find.byType(Card).evaluate().length, lessThan(27));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('review-review-0026')),
      400,
    );
    expect(find.byKey(const ValueKey('review-review-0026')), findsOneWidget);
  });

  testWidgets('un error inesperado muestra recuperación en vez de blanco', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RvSummaryErrorView(hydrantId: 'synthetic-hydrant-2392'),
      ),
    );

    expect(find.text('No fue posible mostrar esta revisión.'), findsOneWidget);
    expect(
      find.textContaining('información local permanece guardada'),
      findsOneWidget,
    );
    expect(find.text('Volver'), findsOneWidget);
    expect(find.text('Abrir desde Hidrantes'), findsOneWidget);
  });

  testWidgets(
    'cierre inactivo permanece visible y no parece finalizado normal',
    (tester) async {
      final draft = _draft('inactive-review').copyWith(
        localStatus: RvLocalStatus.inactive,
        inactiveClosure: RvInactiveClosure(
          reasonCode: noHydrantAtLocationReasonCode,
          comment: 'No existe hidrante en esta ubicación.',
          location: RvLocationSample(
            latitude: 0,
            longitude: 0,
            source: 'qa',
            capturedAt: DateTime.utc(2026, 8, 28),
          ),
          closedAt: DateTime.utc(2026, 8, 28),
          closedByUserId: 'qa-user',
          closedByName: 'Técnico QA',
          brigadeId: 'qa-brigade',
          deviceId: 'qa-device',
          photoIds: const ['qa-photo'],
          idempotencyKey: 'inactive-inactive-review',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllReviewsList(
              drafts: [draft],
              visibleHydrantIds: const {'hydrant-1'},
            ),
          ),
        ),
      );

      expect(
        find.textContaining('Inactivo · pendiente de contrato'),
        findsOneWidget,
      );
      expect(find.textContaining('Historial · solo lectura'), findsNothing);
    },
  );

  testWidgets('el límite de fallo captura excepción y conserva navegación', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RvSummaryFailureBoundary(
          hydrantId: 'synthetic-hydrant-2392',
          clientInspectionId: 'synthetic-conflict-409',
          builder: (_) => throw StateError('synthetic summary failure'),
        ),
      ),
    );

    final reported = tester.takeException();
    expect(reported, isA<StateError>());
    expect('$reported', isNot(contains('synthetic summary failure')));
    expect(find.text('No fue posible mostrar esta revisión.'), findsOneWidget);
    expect(find.text('Abrir desde Hidrantes'), findsOneWidget);
  });
}

RvDraft _draft(String id) {
  final now = DateTime.utc(2026, 8, 28);
  final checklist = DynamicChecklist(
    id: 'checklist',
    code: 'RV',
    version: 1,
    title: 'RV',
    etag: 'etag',
    cachedAt: now,
    sections: const [],
  );
  return RvDraft(
    clientInspectionId: id,
    hydrantId: 'hydrant-1',
    accountNumber: '1011',
    fieldSessionId: 'user',
    checklistId: checklist.id,
    checklistVersion: checklist.version,
    checklistSnapshot: checklist.toJson(),
    createdAt: now,
    updatedAt: now,
    localStatus: RvLocalStatus.pendingAnswers,
  );
}
