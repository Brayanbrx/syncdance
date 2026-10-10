/// Canonical anatomical joints, independent of any pose SDK.
enum Joint {
  nose,
  leftEyeInner,
  leftEye,
  leftEyeOuter,
  rightEyeInner,
  rightEye,
  rightEyeOuter,
  leftEar,
  rightEar,
  leftMouth,
  rightMouth,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftPinky,
  rightPinky,
  leftIndex,
  rightIndex,
  leftThumb,
  rightThumb,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
  leftHeel,
  rightHeel,
  leftFootIndex,
  rightFootIndex,
}

/// pose-v1: upright image coordinates, x right/y down, normalized by image
/// width/height. Anatomical left/right are never swapped for a mirrored preview.
/// Coordinates outside [0, 1] are allowed to represent an out-of-frame joint.
/// Optional z is relative depth in image-width units, not clinical 3D data.
class PoseLandmark {
  PoseLandmark({
    required this.joint,
    required this.x,
    required this.y,
    this.z,
    required this.confidence,
  }) {
    if (!x.isFinite || !y.isFinite || (z != null && !z!.isFinite)) {
      throw ArgumentError('Landmark coordinates must be finite.');
    }
    _checkConfidence(confidence);
  }

  final Joint joint;
  final double x;
  final double y;
  final double? z;
  final double confidence;
}

/// A monotonic timestamp in milliseconds since the start of capture, not UTC.
/// Missing joints remain absent; adapters must never invent zero coordinates.
class PoseFrame {
  PoseFrame({
    required this.timestampMs,
    required this.imageAspectRatio,
    required List<PoseLandmark> landmarks,
    required this.poseConfidence,
  }) : landmarks = List.unmodifiable(landmarks) {
    if (timestampMs < 0) {
      throw ArgumentError.value(timestampMs, 'timestampMs', 'Must be >= 0.');
    }
    _checkConfidence(poseConfidence);
    if (!imageAspectRatio.isFinite || imageAspectRatio <= 0) {
      throw ArgumentError.value(
        imageAspectRatio,
        'imageAspectRatio',
        'Must be positive.',
      );
    }
    if (landmarks.map((landmark) => landmark.joint).toSet().length !=
        landmarks.length) {
      throw ArgumentError('A frame cannot contain duplicate joints.');
    }
  }

  static const schemaVersion = 'pose-v1';
  final int timestampMs;

  /// Upright image width / height. Multiply x by this ratio before calculating
  /// Euclidean angles/distances with normalized y (or undo both normalizations).
  final double imageAspectRatio;
  final List<PoseLandmark> landmarks;
  final double poseConfidence;

  PoseLandmark? landmark(Joint joint) {
    for (final landmark in landmarks) {
      if (landmark.joint == joint) return landmark;
    }
    return null;
  }
}

void _checkConfidence(double confidence) {
  if (!confidence.isFinite || confidence < 0 || confidence > 1) {
    throw ArgumentError.value(confidence, 'confidence', 'Must be in [0, 1].');
  }
}
