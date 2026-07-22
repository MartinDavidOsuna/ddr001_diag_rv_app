import '../../../domain/functional/functional_models.dart';

class CalculatedFunctionalResult {
  const CalculatedFunctionalResult({
    required this.result,
    required this.reasons,
    this.rulesVersion = 'functional-result-demo-v1',
  });
  final FunctionalOverallResult result;
  final List<String> reasons;
  final String rulesVersion;
}

abstract final class FunctionalResultEngine {
  static CalculatedFunctionalResult calculate(FunctionalInspection inspection) {
    if (inspection.status == FunctionalInspectionStatus.suspended) {
      return const CalculatedFunctionalResult(
        result: FunctionalOverallResult.suspended,
        reasons: ['La prueba fue suspendida.'],
      );
    }
    if (inspection.visitWithoutTest) {
      return const CalculatedFunctionalResult(
        result: FunctionalOverallResult.incompleteTest,
        reasons: ['La visita se guardó sin prueba.'],
      );
    }
    if (!inspection.preconditions.criticalReady) {
      return const CalculatedFunctionalResult(
        result: FunctionalOverallResult.notEvaluable,
        reasons: ['No se cumplieron precondiciones críticas.'],
      );
    }
    final statuses = [
      for (var step = 3; step <= 8; step++)
        '${inspection.stepData['step${step}Status'] ?? ''}',
    ];
    if (statuses.contains('failed')) {
      return const CalculatedFunctionalResult(
        result: FunctionalOverallResult.requiresRepair,
        reasons: ['Existe al menos una prueba con falla.'],
      );
    }
    if (inspection.stepData['flowToleranceResult'] == 'demoOutsideTolerance') {
      return const CalculatedFunctionalResult(
        result: FunctionalOverallResult.requiresAdjustment,
        reasons: [
          'El caudal está fuera de la tolerancia DEMO; no constituye un rechazo técnico oficial.',
        ],
      );
    }
    if (statuses.contains('notPerformed') ||
        statuses.any((value) => value.isEmpty)) {
      return const CalculatedFunctionalResult(
        result: FunctionalOverallResult.incompleteTest,
        reasons: ['Existen pruebas no realizadas o pendientes.'],
      );
    }
    if (statuses.contains('notApplicable')) {
      return const CalculatedFunctionalResult(
        result: FunctionalOverallResult.approvedWithObservations,
        reasons: ['Existen pruebas justificadas como No aplica.'],
      );
    }
    return const CalculatedFunctionalResult(
      result: FunctionalOverallResult.approvedWithObservations,
      reasons: [
        'Cálculo DEMO: requiere confirmación del inspector y tolerancias oficiales.',
      ],
    );
  }
}
