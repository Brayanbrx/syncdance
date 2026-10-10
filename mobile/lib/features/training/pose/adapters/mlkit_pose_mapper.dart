import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as ml;

import '../../camera/camera_frame.dart';
import '../pose_frame.dart';

/// Android image rotation follows ML Kit's sensor + device compensation.
int androidImageRotation(CameraFrame frame) {
  final deviceDegrees = switch (frame.orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };
  final sensor = frame.camera.sensorOrientation;
  return frame.camera.lensDirection == CameraLensDirection.front
      ? (sensor + deviceDegrees) % 360
      : (sensor - deviceDegrees + 360) % 360;
}

ml.InputImage androidInputImage(CameraFrame frame) {
  final image = frame.image;
  // Never reinterpret arbitrary YUV420 planes as packed NV21. CameraX 0.7.5+1
  // explicitly converts the requested NV21 format and labels the output as such.
  if (image.format.group != ImageFormatGroup.nv21 || image.planes.length != 1) {
    throw const FormatException(
      'Se esperaba una imagen NV21 de un solo plano.',
    );
  }
  if (image.width <= 0 ||
      image.height <= 0 ||
      image.width.isOdd ||
      image.height.isOdd ||
      image.planes.single.bytes.length != image.width * image.height * 3 ~/ 2) {
    throw const FormatException('El tamaño del buffer NV21 no es válido.');
  }
  return ml.InputImage.fromBytes(
    bytes: image.planes.single.bytes,
    metadata: ml.InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: ml.InputImageRotationValue.fromRawValue(
        androidImageRotation(frame),
      )!,
      format: ml.InputImageFormat.nv21,
      bytesPerRow: image.planes.single.bytesPerRow,
    ),
  );
}

/// Android ML Kit returns landmarks in the rotation-corrected coordinate space.
/// Preserve anatomical names; mirroring is a presentation-only transform.
PoseFrame canonicalAndroidPose(CameraFrame frame, ml.Pose? pose) {
  final rotation = androidImageRotation(frame);
  final swap = rotation == 90 || rotation == 270;
  final width = (swap ? frame.image.height : frame.image.width).toDouble();
  final height = (swap ? frame.image.width : frame.image.height).toDouble();
  final points = <PoseLandmark>[];
  for (final point in pose?.landmarks.values ?? <ml.PoseLandmark>[]) {
    if (!point.x.isFinite || !point.y.isFinite || !point.likelihood.isFinite) {
      continue;
    }
    points.add(
      PoseLandmark(
        joint: Joint.values.byName(point.type.name),
        x: point.x / width,
        y: point.y / height,
        // z stays absent until its scale is validated for cross-engine comparison.
        confidence: point.likelihood.clamp(0.0, 1.0),
      ),
    );
  }
  return PoseFrame(
    timestampMs: frame.timestampMs,
    imageAspectRatio: width / height,
    landmarks: points,
    poseConfidence: points.isEmpty
        ? 0
        : points.fold<double>(0, (sum, point) => sum + point.confidence) /
              points.length,
  );
}
