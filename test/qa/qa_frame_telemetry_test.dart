import 'dart:ui';

import 'package:ddr001diag/qa/qa_frame_telemetry.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('segmenta build, raster y total sin callbacks retenidos', () {
    final source = _Source();
    final times = [DateTime.utc(2026), DateTime.utc(2026, 1, 1, 0, 0, 1)];
    final telemetry = QaFrameTelemetryController(
      source: source,
      now: () => times.removeAt(0),
    );
    telemetry.start('ui-without-camera');
    expect(source.listeners, 1);
    source.emit([
      _frame(build: 1000, raster: 2000, total: 5000),
      _frame(build: 3000, raster: 7000, total: 20000),
    ]);

    final report = telemetry.stop();

    expect(source.listeners, 0);
    expect(telemetry.retainedFrames, 0);
    expect(report.segment, 'ui-without-camera');
    expect(report.frames, 2);
    expect(report.overBudget, 1);
    expect(report.buildMicros['p50'], 1000);
    expect(report.rasterMicros['p99'], 7000);
    expect(report.totalMicros['max'], 20000);
    expect(report.startedAt, DateTime.utc(2026));
    expect(report.endedAt, DateTime.utc(2026, 1, 1, 0, 0, 1));
    expect(
      report.toJson()['frameBudgetMicros'],
      QaFrameTelemetryController.frameBudgetMicros,
    );
  });

  test('una sola sesión activa y dispose elimina listener', () {
    final source = _Source();
    final telemetry = QaFrameTelemetryController(source: source);
    telemetry.start('gallery');
    expect(() => telemetry.start('other'), throwsStateError);

    telemetry.dispose();
    source.emit([_frame(build: 1, raster: 1, total: 2)]);

    expect(source.listeners, 0);
    expect(telemetry.retainedFrames, 0);
    expect(() => telemetry.start('again'), throwsStateError);
  });

  test('segmento vacío devuelve percentiles y porcentaje en cero', () {
    final source = _Source();
    final telemetry = QaFrameTelemetryController(source: source);
    telemetry.start('empty');
    final report = telemetry.stop();

    expect(report.frames, 0);
    expect(report.overBudget, 0);
    expect(report.toJson()['overBudgetPercent'], 0);
    expect(report.buildMicros.values, everyElement(0));
    expect(report.rasterMicros.values, everyElement(0));
    expect(report.totalMicros.values, everyElement(0));
    expect(source.listeners, 0);
  });

  test('presupuesto es exclusivo y sesiones repetidas no mezclan frames', () {
    final source = _Source();
    final telemetry = QaFrameTelemetryController(source: source);
    telemetry.start('first');
    source.emit([
      _frame(build: 100, raster: 100, total: 16667),
      _frame(build: 100, raster: 100, total: 16668),
    ]);
    final first = telemetry.stop();
    expect(first.overBudget, 1);

    telemetry.start('second');
    source.emit([_frame(build: 400, raster: 500, total: 1000)]);
    final second = telemetry.stop();
    expect(second.frames, 1);
    expect(second.totalMicros['p50'], 1000);
    expect(second.totalMicros['max'], 1000);
    expect(source.maxListeners, 1);
  });

  test('percentiles usan nearest-rank sobre unidades en microsegundos', () {
    final source = _Source();
    final telemetry = QaFrameTelemetryController(source: source);
    telemetry.start('math');
    source.emit([
      for (var value = 1; value <= 100; value++)
        _frame(build: value, raster: value, total: value),
    ]);
    final report = telemetry.stop();

    expect(report.totalMicros, {
      'p50': 50,
      'p90': 90,
      'p95': 95,
      'p99': 99,
      'max': 100,
    });
  });
}

FrameTiming _frame({
  required int build,
  required int raster,
  required int total,
}) => FrameTiming(
  vsyncStart: 0,
  buildStart: 100,
  buildFinish: 100 + build,
  rasterStart: total - raster,
  rasterFinish: total,
  rasterFinishWallTime: total,
);

class _Source implements QaFrameTimingSource {
  final _callbacks = <TimingsCallback>[];
  int get listeners => _callbacks.length;
  int maxListeners = 0;

  @override
  void add(TimingsCallback callback) {
    _callbacks.add(callback);
    if (_callbacks.length > maxListeners) maxListeners = _callbacks.length;
  }

  @override
  void remove(TimingsCallback callback) => _callbacks.remove(callback);

  void emit(List<FrameTiming> timings) {
    for (final callback in List<TimingsCallback>.of(_callbacks)) {
      callback(timings);
    }
  }
}
