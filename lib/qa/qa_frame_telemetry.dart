import 'package:flutter/scheduler.dart';

abstract interface class QaFrameTimingSource {
  void add(TimingsCallback callback);
  void remove(TimingsCallback callback);
}

class SchedulerQaFrameTimingSource implements QaFrameTimingSource {
  const SchedulerQaFrameTimingSource();

  @override
  void add(TimingsCallback callback) =>
      SchedulerBinding.instance.addTimingsCallback(callback);

  @override
  void remove(TimingsCallback callback) =>
      SchedulerBinding.instance.removeTimingsCallback(callback);
}

class QaFrameTelemetryReport {
  const QaFrameTelemetryReport({
    required this.segment,
    required this.startedAt,
    required this.endedAt,
    required this.frames,
    required this.overBudget,
    required this.buildMicros,
    required this.rasterMicros,
    required this.totalMicros,
  });

  final String segment;
  final DateTime startedAt;
  final DateTime endedAt;
  final int frames;
  final int overBudget;
  final Map<String, int> buildMicros;
  final Map<String, int> rasterMicros;
  final Map<String, int> totalMicros;

  Map<String, dynamic> toJson() => {
    'segment': segment,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'frames': frames,
    'overBudget': overBudget,
    'frameBudgetMicros': QaFrameTelemetryController.frameBudgetMicros,
    'overBudgetPercent': frames == 0 ? 0 : overBudget * 100 / frames,
    'buildMicros': buildMicros,
    'rasterMicros': rasterMicros,
    'totalMicros': totalMicros,
  };
}

/// QA-only Flutter frame telemetry. The callback only appends timings and
/// never emits UI notifications per frame.
class QaFrameTelemetryController {
  QaFrameTelemetryController({
    this._source = const SchedulerQaFrameTimingSource(),
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  /// 60 Hz frame budget, expressed in microseconds.
  static const frameBudgetMicros = 16667;
  final QaFrameTimingSource _source;
  final DateTime Function() _now;
  final List<FrameTiming> _timings = [];
  String? _segment;
  DateTime? _startedAt;
  bool _disposed = false;

  bool get isRecording => _segment != null;
  int get retainedFrames => _timings.length;

  void start(String segment) {
    if (_disposed) throw StateError('Telemetría cerrada.');
    if (isRecording) throw StateError('Ya existe un segmento activo.');
    if (segment.trim().isEmpty) throw ArgumentError.value(segment, 'segment');
    _timings.clear();
    _segment = segment.trim();
    _startedAt = _now().toUtc();
    _source.add(_onTimings);
  }

  QaFrameTelemetryReport stop() {
    final segment = _segment;
    final started = _startedAt;
    if (segment == null || started == null) {
      throw StateError('No existe un segmento activo.');
    }
    _source.remove(_onTimings);
    final snapshot = List<FrameTiming>.of(_timings);
    _segment = null;
    _startedAt = null;
    _timings.clear();
    return QaFrameTelemetryReport(
      segment: segment,
      startedAt: started,
      endedAt: _now().toUtc(),
      frames: snapshot.length,
      overBudget: snapshot
          .where((frame) => frame.totalSpan.inMicroseconds > frameBudgetMicros)
          .length,
      buildMicros: _summary(
        snapshot.map((frame) => frame.buildDuration.inMicroseconds),
      ),
      rasterMicros: _summary(
        snapshot.map((frame) => frame.rasterDuration.inMicroseconds),
      ),
      totalMicros: _summary(
        snapshot.map((frame) => frame.totalSpan.inMicroseconds),
      ),
    );
  }

  void _onTimings(List<FrameTiming> values) {
    if (_disposed || !isRecording) return;
    _timings.addAll(values);
  }

  void dispose() {
    if (_disposed) return;
    if (isRecording) _source.remove(_onTimings);
    _segment = null;
    _startedAt = null;
    _timings.clear();
    _disposed = true;
  }

  static Map<String, int> _summary(Iterable<int> values) {
    final sorted = values.toList()..sort();
    int percentile(double value) {
      if (sorted.isEmpty) return 0;
      final index = ((sorted.length * value).ceil() - 1)
          .clamp(0, sorted.length - 1)
          .toInt();
      return sorted[index];
    }

    return {
      'p50': percentile(.50),
      'p90': percentile(.90),
      'p95': percentile(.95),
      'p99': percentile(.99),
      'max': sorted.isEmpty ? 0 : sorted.last,
    };
  }
}
