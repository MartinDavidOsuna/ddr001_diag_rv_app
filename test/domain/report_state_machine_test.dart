import 'package:ddr001diag/domain/workflow/report_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const machine = ReportStateMachine();

  ReportTransitionRequest request(
    ReportState from,
    ReportState to, {
    String reason = '',
  }) => ReportTransitionRequest(
    reportId: 'rf-1',
    reportType: 'f02B',
    currentState: from,
    requestedState: to,
    actor: 'inspector-1',
    role: 'inspector',
    deviceId: 'device-1',
    reason: reason,
    timestamp: DateTime.utc(2026, 7, 15),
    correlationId: 'correlation-1',
  );

  test('permite el recorrido operativo y conserva el estado anterior', () {
    final paused = machine.evaluate(
      request(ReportState.inProgress, ReportState.paused),
    );
    final resumed = machine.evaluate(
      request(ReportState.paused, ReportState.inProgress),
    );

    expect(paused.allowed, isTrue);
    expect(paused.previousState, ReportState.inProgress);
    expect(paused.nextState, ReportState.paused);
    expect(resumed.allowed, isTrue);
    expect(resumed.nextState, ReportState.inProgress);
    expect(paused.traceEventId, isNotEmpty);
  });

  test('rechaza reapertura de finalizado y no cambia el estado', () {
    final result = machine.evaluate(
      request(ReportState.completed, ReportState.inProgress),
    );

    expect(result.allowed, isFalse);
    expect(result.reasonCode, 'invalidTransition');
    expect(result.nextState, ReportState.completed);
  });

  test('suspender, cancelar y repetir exigen motivo real', () {
    for (final transition in [
      (ReportState.inProgress, ReportState.suspended),
      (ReportState.inProgress, ReportState.cancelled),
      (ReportState.completed, ReportState.requiresRepeat),
    ]) {
      final rejected = machine.evaluate(request(transition.$1, transition.$2));
      final accepted = machine.evaluate(
        request(transition.$1, transition.$2, reason: 'Condición documentada'),
      );
      expect(rejected.reasonCode, 'reasonRequired');
      expect(accepted.allowed, isTrue);
    }
  });

  test('markPersisted solo confirma el resultado ya permitido', () {
    final result = machine
        .evaluate(request(ReportState.draft, ReportState.ready))
        .markPersisted();
    expect(result.allowed, isTrue);
    expect(result.persisted, isTrue);
  });
}
