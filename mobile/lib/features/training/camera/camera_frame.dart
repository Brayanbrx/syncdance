import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// Ephemeral native input. Consumers must drop busy frames, never queue buffers.
class CameraFrame {
  const CameraFrame({
    required this.image,
    required this.camera,
    required this.orientation,
    required this.timestampMs,
    required this.generation,
  });

  final CameraImage image;
  final CameraDescription camera;
  final DeviceOrientation orientation;
  final int timestampMs;
  final int generation;
}
