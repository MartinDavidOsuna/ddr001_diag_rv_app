import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection_step_validator.dart';
import 'package:ddr001diag/features/visual_report/data/visual_report_compatibility_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

VisualInspection _inspection({
  int step = 1,
  int flowVersion = 1,
  InspectionStatus status = InspectionStatus.inProgress,
}) {
  final now = DateTime.utc(2026, 7, 16);
  return VisualInspection(
    id: 'rv-legacy',
    hydrantId: 'hydrant-1',
    source: HydrantSource.assigned,
    status: status,
    currentStep: step,
    visualFlowVersion: flowVersion,
    startedAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const adapter = VisualReportCompatibilityAdapter();

  test('REPORTE VISUAL usa nueve pasos para el progreso', () {
    expect(_inspection(step: 1, flowVersion: 2).progress, closeTo(1 / 9, 0.0001));
    expect(_inspection(step: 9, flowVersion: 2).progress, 1);
  });

  for (final entry in const {6: 7, 7: 8, 8: 9}.entries) {
    test('borrador legacy paso ${entry.key} abre en ${entry.value}', () {
      final projected = adapter.project(_inspection(step: entry.key));
      expect(projected.currentStep, entry.value);
      expect(projected.visualFlowVersion, 2);
    });
  }

  test('adaptación del flujo es idempotente', () {
    final once = adapter.project(_inspection(step: 6));
    final twice = adapter.project(once);
    expect(twice.currentStep, 7);
    expect(twice.visualFlowVersion, 2);
  });

  test('reporte finalizado legacy conserva paso y versión al proyectarse', () {
    final source = _inspection(step: 8, status: InspectionStatus.completed);
    final projected = adapter.project(source);
    expect(projected.currentStep, 8);
    expect(projected.visualFlowVersion, 1);
    expect(projected.id, source.id);
    expect(projected.updatedAt, source.updatedAt);
  });

  test('medidor canónico no se duplica como inspección de componente', () {
    final projected = adapter.project(_inspection(step: 5));
    expect(
      projected.componentInspections
          .where((item) => item.componentType.name == 'flowMeter'),
      isEmpty,
    );
  });

  test('validación pública y privada reporta el paso accionable correcto', () {
    final projected = adapter.project(_inspection(step: 5));
    const validator = VisualInspectionStepValidator(
      photos: [],
      damageDocuments: {},
    );
    expect(
      validator.validateStep(projected, 5).errors,
      everyElement(isA<InspectionValidationError>().having(
        (error) => error.stepNumber,
        'paso',
        5,
      )),
    );
    expect(
      validator.validateStep(projected, 6).errors,
      everyElement(isA<InspectionValidationError>().having(
        (error) => error.stepNumber,
        'paso',
        6,
      )),
    );
  });

  test('posición activa de ambos subasistentes sobrevive round-trip', () {
    final source = _inspection(step: 6, flowVersion: 2).copyWith(
      publicComponentIndex: 4,
      privateComponentIndex: 12,
      flowMeterComponentConfirmed: true,
      flowMeterComponentReviewedBy: 'inspector',
      flowMeterComponentReviewedAt: DateTime.utc(2026, 7, 16),
    );
    final restored = VisualInspection.fromJson(source.toJson());
    expect(restored.publicComponentIndex, 4);
    expect(restored.privateComponentIndex, 12);
    expect(restored.flowMeterComponentConfirmed, isTrue);
    expect(restored.flowMeterComponentReviewedBy, 'inspector');
  });
}
