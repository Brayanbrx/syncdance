import 'pose_estimator.dart';
import 'pose_frame.dart';

/// Device benchmark for the physical validation (Phase 1): a fixed window of
/// capture and inference counters summarized as values to register by hand.
/// It is a diagnostic, never a score. Capture images/s are not inferences/s.
class PoseBenchmark {
  PoseBenchmark({
    required PoseEstimatorStats stats,
    required int capturedFrames,
  }) : _start = stats,
       _startCaptured = capturedFrames,
       _lastProcessed = stats.processedFrames;

  static const version = 'pose-benchmark-v1';
  static const duration = Duration(seconds: 60);

  /// Width of the start and end windows used to spot thermal slowdowns.
  static const edgeMs = 10000;

  final PoseEstimatorStats _start;
  final int _startCaptured;
  int _lastProcessed;
  int? _lastTimestampMs;
  int _results = 0;
  int _withPerson = 0;
  final _inference = <({int atMs, double ms})>[];

  /// One estimator result. A new processed frame adds its inference time;
  /// repeated or older timestamps are ignored (they do not advance time).
  void sample(PoseFrame pose, PoseEstimatorStats stats) {
    final last = _lastTimestampMs;
    if (last != null && pose.timestampMs <= last) return;
    _lastTimestampMs = pose.timestampMs;
    _results++;
    if (pose.landmarks.isNotEmpty) _withPerson++;
    if (stats.processedFrames > _lastProcessed) {
      _lastProcessed = stats.processedFrames;
      final ms = stats.lastInferenceMs;
      if (ms.isFinite && ms >= 0) {
        _inference.add((atMs: pose.timestampMs, ms: ms));
      }
    }
  }

  PoseBenchmarkReport finish({
    required int elapsedMs,
    required PoseEstimatorStats stats,
    required int capturedFrames,
  }) {
    int? delta(int end, int start) => end >= start ? end - start : null;
    final times = [for (final s in _inference) s.ms];
    final first = _inference.isEmpty ? 0 : _inference.first.atMs;
    final lastAt = _inference.isEmpty ? 0 : _inference.last.atMs;
    return PoseBenchmarkReport(
      elapsedMs: elapsedMs,
      capturedFrames: delta(capturedFrames, _startCaptured),
      processedFrames: delta(stats.processedFrames, _start.processedFrames),
      droppedFrames: delta(stats.droppedFrames, _start.droppedFrames),
      results: _results,
      resultsWithPerson: _withPerson,
      inferenceP50Ms: percentile(times, 0.5),
      inferenceP95Ms: percentile(times, 0.95),
      inferenceMaxMs: times.isEmpty
          ? null
          : times.reduce((a, b) => a > b ? a : b),
      startP50Ms: percentile([
        for (final s in _inference)
          if (s.atMs - first < edgeMs) s.ms,
      ], 0.5),
      endP50Ms: percentile([
        for (final s in _inference)
          if (lastAt - s.atMs < edgeMs) s.ms,
      ], 0.5),
    );
  }

  /// Nearest-rank percentile; null without samples (absent is not zero).
  static double? percentile(List<double> values, double p) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }
}

class PoseBenchmarkReport {
  const PoseBenchmarkReport({
    required this.elapsedMs,
    required this.capturedFrames,
    required this.processedFrames,
    required this.droppedFrames,
    required this.results,
    required this.resultsWithPerson,
    this.inferenceP50Ms,
    this.inferenceP95Ms,
    this.inferenceMaxMs,
    this.startP50Ms,
    this.endP50Ms,
  });

  final int elapsedMs, results, resultsWithPerson;

  /// Null when a counter went backwards (the camera restarted midway).
  final int? capturedFrames, processedFrames, droppedFrames;
  final double? inferenceP50Ms, inferenceP95Ms, inferenceMaxMs;
  final double? startP50Ms, endP50Ms;

  double? _rate(int? count) =>
      count == null || elapsedMs <= 0 ? null : count * 1000 / elapsedMs;

  double? get captureRate => _rate(capturedFrames);
  double? get inferenceRate => _rate(processedFrames);

  double? get droppedShare {
    final processed = processedFrames, dropped = droppedFrames;
    if (processed == null || dropped == null || processed + dropped == 0) {
      return null;
    }
    return dropped / (processed + dropped);
  }

  double? get personShare => results == 0 ? null : resultsWithPerson / results;

  /// Plain text to paste in the validation record.
  String get text {
    String n(double? value, [int digits = 0]) =>
        value == null ? '—' : value.toStringAsFixed(digits);
    String pct(double? value) =>
        value == null ? '—' : '${(value * 100).toStringAsFixed(0)} %';
    return [
      '${PoseBenchmark.version} · ${n(elapsedMs / 1000)} s',
      'Captura: ${n(captureRate, 1)} imágenes/s '
          '(${capturedFrames ?? '—'} recibidas)',
      'Análisis: ${n(inferenceRate, 1)} inferencias/s '
          '(${processedFrames ?? '—'}) · ${droppedFrames ?? '—'} descartadas '
          '(${pct(droppedShare)}, por el tope de ~12/s o una inferencia en curso)',
      'Inferencia: p50 ${n(inferenceP50Ms)} ms · p95 ${n(inferenceP95Ms)} ms · '
          'máx ${n(inferenceMaxMs)} ms',
      'Primeros 10 s: p50 ${n(startP50Ms)} ms · últimos 10 s: '
          'p50 ${n(endP50Ms)} ms',
      'Persona detectada en ${pct(personShare)} de $results resultados',
    ].join('\n');
  }
}
