import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection.dart';
import 'package:ddr001diag/features/visual_report/data/visual_report_compatibility_adapter.dart';
import 'package:ddr001diag/features/visual_report/domain/visual_component_models.dart';
import 'package:ddr001diag/features/visual_report/presentation/steps/visual_components_list_step_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

VisualInspection _projected() {
  final now = DateTime.utc(2026, 7, 16);
  return const VisualReportCompatibilityAdapter().project(
    VisualInspection(
      id: 'rv-ui',
      hydrantId: 'h-1',
      source: HydrantSource.assigned,
      startedAt: now,
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Widget _app({
  required VisualComponentsSection section,
  bool readOnly = false,
  double textScale = 1,
  int initialIndex = 0,
  Future<void> Function(List<VisualComponentInspection>)? onChanged,
}) {
  final inspection = _projected();
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: VisualComponentsListStepPage(
          configuration: inspection.hydrantConfiguration!,
          components: inspection.componentInspections,
          victaulicGroup: inspection.victaulicGroupInspection,
          section: section,
          flowMeterComplete: true,
          flowMeterConfirmed: false,
          initialIndex: initialIndex,
          readOnly: readOnly,
          actorId: 'inspector',
          onChanged: onChanged ?? (_) async {},
          onVictaulicChanged: (_) async {},
          onComponentConfirmed: (_) async {},
          onFlowMeterConfirmed: () async {},
          onIndexChanged: (_) async {},
          onStepCompleted: () async {},
          onPreviousStep: () async {},
          onEditFlowMeter: () {},
          onCapturePhoto: (_, _) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('defaults favorables aparecen sin marcar revisado', (tester) async {
    await tester.pumpWidget(
      _app(section: VisualComponentsSection.publicNetwork),
    );
    expect(find.text('Válvula de servicio 1'), findsOneWidget);
    expect(find.text('Valores sugeridos — confirme la revisión.'), findsOneWidget);
    expect(find.text('Sin confirmar'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Sí'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Bueno'), findsOneWidget);
  });

  testWidgets('abrir no persiste ni confirma', (tester) async {
    var writes = 0;
    await tester.pumpWidget(_app(
      section: VisualComponentsSection.publicNetwork,
      onChanged: (_) async {
        writes++;
      },
    ));
    await tester.pump();
    expect(writes, 0);
    expect(find.text('Sin confirmar'), findsOneWidget);
  });

  testWidgets('confirmar establece revisión explícita y avanza', (tester) async {
    VisualComponentInspection? saved;
    await tester.pumpWidget(_app(
      section: VisualComponentsSection.publicNetwork,
      onChanged: (values) async {
        saved = values.first;
      },
    ));
    final confirmButton = find.text('Confirmar componente y continuar');
    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();
    expect(saved?.explicitlyConfirmed, isTrue);
    expect(saved?.reviewedAt, isNotNull);
    expect(find.text('Medidor de caudal'), findsOneWidget);
  });

  testWidgets('índice abre el componente seleccionado', (tester) async {
    await tester.pumpWidget(
      _app(section: VisualComponentsSection.publicNetwork),
    );
    final indexButton = find.text('Ver índice de componentes');
    await tester.ensureVisible(indexButton);
    await tester.tap(indexButton);
    await tester.pumpAndSettle();
    final airValve = find.text('Válvula de aire');
    await tester.scrollUntilVisible(
      airValve,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(airValve);
    await tester.pumpAndSettle();
    expect(find.text('Válvula de aire'), findsOneWidget);
  });

  testWidgets('modo lectura no ofrece confirmación editable', (tester) async {
    await tester.pumpWidget(_app(
      section: VisualComponentsSection.publicNetwork,
      readOnly: true,
    ));
    expect(find.text('Confirmar componente y continuar'), findsNothing);
    expect(find.text('Siguiente'), findsOneWidget);
  });

  testWidgets('texto a 2x conserva encabezado y target principal', (tester) async {
    await tester.pumpWidget(_app(
      section: VisualComponentsSection.privateNetwork,
      textScale: 2,
    ));
    expect(tester.takeException(), isNull);
    final button = find.text('Confirmar componente y continuar');
    expect(button, findsOneWidget);
    expect(tester.getSize(find.ancestor(of: button, matching: find.byType(FilledButton))).height, greaterThanOrEqualTo(48));
  });
}
