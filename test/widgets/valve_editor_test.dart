import 'package:ddr001diag/domain/functional/functional_collection_models.dart';
import 'package:ddr001diag/features/functional/widgets/valve_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final original = ValveRecord(
    id: 'valve-uuid-original',
    inspectionId: 'rf-1',
    order: 1,
    label: 'V1',
    type: 'compuerta',
    diameter: '4 in',
    initialPosition: 'cerrada',
    configuration: const {'notes': 'configuración base'},
    testIds: const ['test-1'],
    photoIds: const ['photo-1'],
    seriesIds: const ['series-1'],
    instrumentIds: const ['instrument-1'],
    result: 'aprobado',
    createdAt: DateTime.utc(2026, 7, 15),
    updatedAt: DateTime.utc(2026, 7, 15),
  );

  testWidgets('duplicar copia configuración pero no evidencia ni resultados', (
    tester,
  ) async {
    ValveRecord? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await ValveEditor.show(
                context,
                inspectionId: 'rf-1',
                suggestedOrder: 2,
                existing: original,
                duplicate: true,
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicar configuración'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result?.id, isNot(original.id));
    expect(result?.order, 2);
    expect(result?.type, original.type);
    expect(result?.diameter, original.diameter);
    expect(result?.testIds, isEmpty);
    expect(result?.photoIds, isEmpty);
    expect(result?.seriesIds, isEmpty);
    expect(result?.instrumentIds, isEmpty);
    expect(result?.result, isEmpty);
  });

  testWidgets('cancelar no produce cambios', (tester) async {
    ValveRecord? result = original;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await ValveEditor.show(
                context,
                inspectionId: 'rf-1',
                suggestedOrder: 1,
                existing: original,
              );
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Cambio');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
