import 'functional_collection_models.dart';
import 'functional_models.dart';

class FunctionalAggregateAssessment {
  const FunctionalAggregateAssessment({
    required this.result,
    required this.reasons,
    required this.criticalPending,
    required this.formulaVersion,
  });
  final FunctionalOverallResult result;
  final List<String> reasons;
  final bool criticalPending;
  final String formulaVersion;
}

class FunctionalAggregateResultService {
  const FunctionalAggregateResultService();

  FunctionalAggregateAssessment calculate({
    required FunctionalInspection inspection,
    required List<ValveRecord> valves,
    required List<ReducerRun> reducerRuns,
    required List<AlarmAttemptRecord> alarms,
    required List<MeasurementSeries> series,
    required List<InstrumentRecord> instruments,
  }) {
    final reasons = <String>[];
    final activeValves = valves.where((value) => value.active).toList();
    final acceptedRuns = reducerRuns
        .where((value) => value.valid && value.accepted)
        .toList();
    final validAlarms = alarms.where((value) => value.valid).toList();
    final acceptedSeries = series
        .where(
          (value) =>
              !value.isActive &&
              value.readings.any((reading) => reading.accepted),
        )
        .toList();
    if (!inspection.visitWithoutTest && activeValves.isEmpty) {
      reasons.add('No se registraron válvulas activas.');
    }
    if (reducerRuns.any((value) => value.valid) && acceptedRuns.isEmpty) {
      reasons.add('No existe corrida de reductora aceptada.');
    }
    if (validAlarms.any((value) => value.result.isEmpty)) {
      reasons.add('Existen intentos de alarma sin resultado.');
    }
    if (inspection.measurementSeriesIds.isNotEmpty && acceptedSeries.isEmpty) {
      reasons.add('No existe una serie finalizada con lecturas aceptadas.');
    }
    final invalidCalibration = instruments.any(
      (value) =>
          value.calibrationStatus == CalibrationStatus.expired ||
          value.calibrationStatus == CalibrationStatus.unknown,
    );
    if (invalidCalibration) {
      reasons.add('Hay instrumentos con calibración no válida.');
    }
    final criticalPending = reasons.isNotEmpty;
    return FunctionalAggregateAssessment(
      result: inspection.visitWithoutTest
          ? FunctionalOverallResult.notEvaluable
          : criticalPending
          ? FunctionalOverallResult.incompleteTest
          : FunctionalOverallResult.approved,
      reasons: reasons,
      criticalPending: criticalPending,
      formulaVersion: 'functional-aggregate-demo-v1',
    );
  }
}
