import 'dart:async';

import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_review_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('confirmación de envío completo', () {
    test('el envío completo muestra el diálogo una sola vez', () {
      final gate = RvSubmissionCompletionGate();
      final submitted = _draft(
        localStatus: RvLocalStatus.submitted,
        remoteStatus: 'submitted',
      );
      expect(gate.consumeIfComplete(submitted), isTrue);
      expect(gate.consumeIfComplete(submitted), isFalse);
    });

    test('un envío parcial no muestra el diálogo', () {
      final gate = RvSubmissionCompletionGate();
      expect(
        gate.consumeIfComplete(
          _draft(
            localStatus: RvLocalStatus.pendingPhotos,
            remoteStatus: 'in_progress',
          ),
        ),
        isFalse,
      );
    });

    testWidgets('Aceptar regresa a Inicio y limpia el stack', (tester) async {
      final router = GoRouter(
        initialLocation: '/review',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('Inicio')),
          ),
          GoRoute(
            path: '/review',
            builder: (context, _) => Scaffold(
              body: FilledButton(
                onPressed: () =>
                    RvReviewNavigation.showSubmissionSuccessAndReturnHome(
                      context,
                    ),
                child: const Text('Completar'),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('Completar'));
      await tester.pump();
      expect(find.text('Inspección enviada'), findsOneWidget);
      expect(
        find.text('La inspección se sincronizó y envió correctamente.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(find.text('Inicio'), findsOneWidget);
      expect(router.canPop(), isFalse);
    });
  });

  group('Atrás y salida', () {
    testWidgets('Atrás en el paso 5 lleva al paso 4', (tester) async {
      await tester.pumpWidget(const _NavigationHarness(initialStep: 4));
      await tester.tap(find.byKey(const ValueKey('previous')));
      await tester.pump();
      expect(find.text('Paso 4'), findsOneWidget);
    });

    testWidgets('Atrás en el paso 1 solicita confirmación', (tester) async {
      await tester.pumpWidget(const _ExitHarness());
      await tester.tap(find.byKey(const ValueKey('request-exit')));
      await tester.pump();
      expect(find.text('¿Salir de la revisión?'), findsOneWidget);
    });

    testWidgets('Cancelar salida conserva el paso 1', (tester) async {
      await tester.pumpWidget(const _ExitHarness());
      await tester.tap(find.byKey(const ValueKey('request-exit')));
      await tester.pump();
      await tester.tap(find.text('Continuar revisión'));
      await tester.pump();
      expect(find.text('Paso 1'), findsOneWidget);
    });

    testWidgets('Confirmar salida abandona sin borrar el borrador', (
      tester,
    ) async {
      await tester.pumpWidget(const _ExitHarness());
      await tester.tap(find.byKey(const ValueKey('request-exit')));
      await tester.pump();
      await tester.tap(find.text('Salir'));
      await tester.pump();
      expect(find.text('Borrador conservado'), findsOneWidget);
    });

    testWidgets('el botón físico Atrás respeta las mismas reglas', (
      tester,
    ) async {
      await tester.pumpWidget(const _ExitHarness());
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('¿Salir de la revisión?'), findsOneWidget);
    });
  });

  group('swipe horizontal', () {
    testWidgets('swipe izquierdo en paso 3 avanza al paso 4', (tester) async {
      await tester.pumpWidget(const _NavigationHarness(initialStep: 2));
      await tester.drag(
        find.byKey(const ValueKey('swipe-area')),
        const Offset(-220, 0),
      );
      await tester.pump();
      expect(find.text('Paso 4'), findsOneWidget);
    });

    testWidgets('swipe derecho en paso 3 vuelve al paso 2', (tester) async {
      await tester.pumpWidget(const _NavigationHarness(initialStep: 2));
      await tester.drag(
        find.byKey(const ValueKey('swipe-area')),
        const Offset(220, 0),
      );
      await tester.pump();
      expect(find.text('Paso 2'), findsOneWidget);
    });

    testWidgets('swipe derecho desde paso 1 solicita confirmación', (
      tester,
    ) async {
      await tester.pumpWidget(const _NavigationHarness(initialStep: 0));
      await tester.drag(
        find.byKey(const ValueKey('swipe-area')),
        const Offset(220, 0),
      );
      await tester.pump();
      expect(find.text('Salida solicitada'), findsOneWidget);
    });

    testWidgets('scroll vertical no cambia de paso', (tester) async {
      await tester.pumpWidget(const _NavigationHarness(initialStep: 2));
      await tester.drag(
        find.byKey(const ValueKey('swipe-area')),
        const Offset(0, -220),
      );
      await tester.pump();
      expect(find.text('Paso 3'), findsOneWidget);
    });

    testWidgets('el gesto del paso 9 no salta validaciones', (tester) async {
      await tester.pumpWidget(
        const _NavigationHarness(initialStep: 8, valid: false),
      );
      await tester.drag(
        find.byKey(const ValueKey('swipe-area')),
        const Offset(-220, 0),
      );
      await tester.pump();
      expect(find.text('Validación pendiente'), findsOneWidget);
      expect(find.text('Resumen'), findsNothing);
    });

    testWidgets('el resumen concluido no responde a navegación lateral', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              key: ValueKey('summary'),
              child: Text('Resumen concluido'),
            ),
          ),
        ),
      );
      await tester.drag(
        find.byKey(const ValueKey('summary')),
        const Offset(-220, 0),
      );
      expect(find.text('Resumen concluido'), findsOneWidget);
      expect(find.byType(RvSwipeNavigationDetector), findsNothing);
    });

    testWidgets('un gesto produce como máximo una navegación', (tester) async {
      final release = Completer<void>();
      var navigations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RvSwipeNavigationDetector(
            onNext: () async {
              navigations++;
              await release.future;
            },
            onPrevious: () async {},
            child: const ColoredBox(
              color: Colors.white,
              child: SizedBox.expand(key: ValueKey('locked-area')),
            ),
          ),
        ),
      );
      final detector = find.byKey(const ValueKey('rv-horizontal-navigation'));
      await tester.drag(detector, const Offset(-220, 0));
      await tester.pump();
      await tester.drag(detector, const Offset(-220, 0));
      expect(navigations, 1);
      release.complete();
    });
  });
}

RvDraft _draft({
  required RvLocalStatus localStatus,
  required String remoteStatus,
}) {
  final now = DateTime.utc(2026, 7, 27);
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
    clientInspectionId: 'client',
    hydrantId: 'hydrant',
    accountNumber: 'account',
    fieldSessionId: 'session',
    checklistId: checklist.id,
    checklistVersion: checklist.version,
    checklistSnapshot: checklist.toJson(),
    createdAt: now,
    updatedAt: now,
    localStatus: localStatus,
    remoteStatus: remoteStatus,
  );
}

class _NavigationHarness extends StatefulWidget {
  const _NavigationHarness({required this.initialStep, this.valid = true});
  final int initialStep;
  final bool valid;

  @override
  State<_NavigationHarness> createState() => _NavigationHarnessState();
}

class _NavigationHarnessState extends State<_NavigationHarness> {
  late int step = widget.initialStep;
  bool exitRequested = false;
  bool summary = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          if (exitRequested) const Text('Salida solicitada'),
          if (summary) const Text('Resumen'),
          if (!widget.valid) const Text('Validación pendiente'),
          Expanded(
            child: RvSwipeNavigationDetector(
              onNext: () async {
                if (step == 8) {
                  if (widget.valid) setState(() => summary = true);
                  return;
                }
                setState(() => step++);
              },
              onPrevious: () async {
                if (step == 0) {
                  setState(() => exitRequested = true);
                } else {
                  setState(() => step--);
                }
              },
              child: SizedBox.expand(
                key: const ValueKey('swipe-area'),
                child: Center(child: Text('Paso ${step + 1}')),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('previous'),
            onPressed: step == 0 ? null : () => setState(() => step--),
            icon: const Icon(Icons.arrow_back),
          ),
        ],
      ),
    ),
  );
}

class _ExitHarness extends StatefulWidget {
  const _ExitHarness();

  @override
  State<_ExitHarness> createState() => _ExitHarnessState();
}

class _ExitHarnessState extends State<_ExitHarness> {
  bool exited = false;

  Future<void> _request(BuildContext dialogContext) async {
    if (await RvReviewNavigation.requestExitReview(dialogContext)) {
      setState(() => exited = true);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Builder(
      builder: (context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _request(context);
        },
        child: Scaffold(
          body: exited
              ? const Text('Borrador conservado')
              : Column(
                  children: [
                    const Text('Paso 1'),
                    FilledButton(
                      key: const ValueKey('request-exit'),
                      onPressed: () => _request(context),
                      child: const Text('Atrás'),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
