import 'package:ddr001diag/features/checklist/presentation/dynamic_checklist_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paso 1 coloca navegación después de todo el contenido', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RvStepLayout(
            currentStep: 0,
            totalFormSteps: 9,
            content: Column(
              children: [
                Text('Contenido paso 1'),
                Text('Último control paso 1'),
              ],
            ),
            onPrevious: null,
            onNext: _noop,
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('step-navigation'))).dy,
      greaterThan(tester.getBottomLeft(find.text('Último control paso 1')).dy),
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Anterior'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('paso 2 coloca navegación después del panel fijo', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RvStepLayout(
            currentStep: 1,
            totalFormSteps: 9,
            content: Column(
              children: [
                Text('Preguntas gabinete'),
                Text('Panel fotográfico fijo'),
              ],
            ),
            onPrevious: _noop,
            onNext: _noop,
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('step-navigation'))).dy,
      greaterThan(tester.getBottomLeft(find.text('Panel fotográfico fijo')).dy),
    );
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('al sustituir contenido solo queda el paso activo', (
    tester,
  ) async {
    final step = ValueNotifier(0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: step,
            builder: (_, value, _) => RvStepLayout(
              currentStep: value,
              totalFormSteps: 9,
              content: KeyedSubtree(
                key: ValueKey('step-$value'),
                child: Text(
                  value == 0 ? 'Contenido paso 1' : 'Contenido paso 2',
                ),
              ),
              onPrevious: value == 0 ? null : () => step.value--,
              onNext: value == 1 ? null : () => step.value++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Contenido paso 1'), findsOneWidget);
    expect(find.text('Contenido paso 2'), findsNothing);
    await tester.tap(find.text('Siguiente'));
    await tester.pump();
    expect(find.text('Contenido paso 1'), findsNothing);
    expect(find.text('Contenido paso 2'), findsOneWidget);
    await tester.tap(find.text('Anterior'));
    await tester.pump();
    expect(find.text('Contenido paso 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-navigation')), findsOneWidget);
  });
}

void _noop() {}
