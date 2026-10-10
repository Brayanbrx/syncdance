import 'dart:math' as math;

import 'body_features.dart';
import 'pose_frame.dart';

enum PoseQuality {
  ready,
  noPerson,
  bodyNotVisible,
  lowConfidence,
  tooClose,
  tooFar,
}

/// Initial framing heuristics, not calibrated distance or multi-person detection.
class PoseQualityGate {
  const PoseQualityGate();

  static const requiredJoints = [
    Joint.nose,
    Joint.leftShoulder,
    Joint.rightShoulder,
    Joint.leftElbow,
    Joint.rightElbow,
    Joint.leftWrist,
    Joint.rightWrist,
    Joint.leftHip,
    Joint.rightHip,
    Joint.leftKnee,
    Joint.rightKnee,
    Joint.leftAnkle,
    Joint.rightAnkle,
  ];

  PoseQuality evaluate(PoseFrame frame) {
    if (frame.landmarks.isEmpty) return PoseQuality.noPerson;
    final points = requiredJoints.map(frame.landmark).toList();
    if (points.any((p) => p == null)) return PoseQuality.bodyNotVisible;
    final body = points.cast<PoseLandmark>();
    // Out of frame first: ML Kit still estimates off-screen joints, with low
    // confidence, so standing too close must not read as poor lighting.
    if (body.any((p) => p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1)) {
      return PoseQuality.bodyNotVisible;
    }
    if (body.any((p) => p.confidence < 0.6)) return PoseQuality.lowConfidence;
    if (body.any((p) => p.x < 0.02 || p.x > 0.98 || p.y < 0.02 || p.y > 0.98)) {
      return PoseQuality.tooClose;
    }
    final height =
        body.map((p) => p.y).reduce(math.max) -
        body.map((p) => p.y).reduce(math.min);
    if (height < 0.4 || _torso(frame).scale < 0.08) return PoseQuality.tooFar;
    // Confident but collapsed geometry must not pass the gate.
    final features = const BodyFeatureExtractor().extract(frame);
    if (features.angles.length != BodyAngle.values.length) {
      return PoseQuality.lowConfidence;
    }
    return PoseQuality.ready;
  }
}

({double x, double y, double scale}) _torso(PoseFrame frame) {
  final lh = frame.landmark(Joint.leftHip)!;
  final rh = frame.landmark(Joint.rightHip)!;
  final ls = frame.landmark(Joint.leftShoulder)!;
  final rs = frame.landmark(Joint.rightShoulder)!;
  final x = (lh.x + rh.x) / 2 * frame.imageAspectRatio;
  final y = (lh.y + rh.y) / 2;
  final dx = (ls.x + rs.x) / 2 * frame.imageAspectRatio - x;
  final dy = (ls.y + rs.y) / 2 - y;
  return (x: x, y: y, scale: math.sqrt(dx * dx + dy * dy));
}

/// A local framing baseline; not intrinsic camera or anatomical calibration.
class FramingCalibration {
  const FramingCalibration(this.timestampMs, this.torsoScale);
  final int timestampMs;
  final double torsoScale;
}

class PoseMeasurements {
  PoseMeasurements({
    required this.quality,
    required this.calibrationProgress,
    required this.calibration,
    required Map<BodyAngle, double> angles,
  }) : angles = Map.unmodifiable(angles);

  final PoseQuality quality;
  final double calibrationProgress;
  final FramingCalibration? calibration;
  final Map<BodyAngle, double> angles;
  bool get canMeasure => quality == PoseQuality.ready && calibration != null;
}

/// Time-based EMA, with no carry-over for missing angles or invalid samples.
class AngleSmoother {
  int? _time;
  Map<BodyAngle, double> _previous = {};

  void reset() {
    _time = null;
    _previous = {};
  }

  Map<BodyAngle, double> update(
    int timestampMs,
    Map<BodyAngle, double> angles,
  ) {
    final delta = _time == null ? null : timestampMs - _time!;
    if (delta != null && delta <= 0) return Map.unmodifiable(_previous);
    final alpha = delta == null || delta > 500
        ? 1.0
        : 1 - math.exp(-delta / 150);
    _previous = {
      for (final entry in angles.entries)
        if (entry.value.isFinite && entry.value >= 0 && entry.value <= 180)
          entry.key: _previous[entry.key] == null
              ? entry.value
              : _previous[entry.key]! +
                    alpha * (entry.value - _previous[entry.key]!),
    };
    _time = timestampMs;
    return Map.unmodifiable(_previous);
  }
}

/// One instance per camera screen. Call reset on pause, rotation and expiry.
class PoseMeasurementProcessor {
  static const version = 'pose-measurements-v2';
  final _smoother = AngleSmoother();
  int? _lastTime;
  double? _aspect;
  int? _calibrationStart;
  ({double x, double y, double scale})? _anchor;
  int _samples = 0;
  double _scaleSum = 0;
  FramingCalibration? _calibration;

  void reset() {
    _lastTime = null;
    _aspect = null;
    _calibration = null;
    _clearWindow();
    _smoother.reset();
  }

  void _clearWindow() {
    _calibrationStart = null;
    _anchor = null;
    _samples = 0;
    _scaleSum = 0;
  }

  /// Out-of-order/duplicate timestamps never advance calibration or the filter.
  PoseMeasurements? process(PoseFrame frame) {
    if (_lastTime != null && frame.timestampMs <= _lastTime!) return null;
    if ((_lastTime != null && frame.timestampMs - _lastTime! > 500) ||
        (_aspect != null && (frame.imageAspectRatio - _aspect!).abs() > 1e-6)) {
      reset();
    }
    _lastTime = frame.timestampMs;
    _aspect = frame.imageAspectRatio;
    final quality = const PoseQualityGate().evaluate(frame);
    if (quality != PoseQuality.ready) {
      _calibration = null;
      _clearWindow();
      _smoother.reset();
      return PoseMeasurements(
        quality: quality,
        calibrationProgress: 0,
        calibration: null,
        angles: {},
      );
    }

    var progress = 1.0;
    if (_calibration == null) {
      final torso = _torso(frame);
      final anchor = _anchor;
      if (anchor != null &&
          ((torso.x - anchor.x).abs() > 0.03 ||
              (torso.y - anchor.y).abs() > 0.03 ||
              (torso.scale / anchor.scale - 1).abs() > 0.1)) {
        _clearWindow();
      }
      _anchor ??= torso;
      _calibrationStart ??= frame.timestampMs;
      _samples++;
      _scaleSum += torso.scale;
      final elapsed = frame.timestampMs - _calibrationStart!;
      progress = math.min(1.0, math.min(elapsed / 1000, _samples / 8));
      if (progress >= 1) {
        _calibration = FramingCalibration(
          frame.timestampMs,
          _scaleSum / _samples,
        );
      }
    }
    final angles = _calibration == null
        ? <BodyAngle, double>{}
        : _smoother.update(
            frame.timestampMs,
            const BodyFeatureExtractor().extract(frame).angles,
          );
    return PoseMeasurements(
      quality: quality,
      calibrationProgress: progress,
      calibration: _calibration,
      angles: angles,
    );
  }
}
