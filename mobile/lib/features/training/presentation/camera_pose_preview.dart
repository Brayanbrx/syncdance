import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../pose/pose_frame.dart';
import 'pose_overlay.dart';

/// The overlay shares CameraPreview's exact viewport, including letterboxing.
/// ML Kit already rotates the coordinates; only the frontal mirror is applied.
class CameraPosePreview extends StatelessWidget {
  const CameraPosePreview({
    required this.camera,
    required this.pose,
    this.highlightedJoints = const {},
    super.key,
  });

  final CameraController camera;
  final PoseFrame? pose;
  final Set<Joint> highlightedJoints;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Center(
      child: CameraPreview(
        camera,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final frame = pose;
            if (frame == null || frame.landmarks.isEmpty) {
              return const SizedBox.shrink();
            }
            final viewportRatio = constraints.maxWidth / constraints.maxHeight;
            // Different preview/analysis crops need device calibration. Avoid
            // stretching a skeleton over an unknown field of view.
            if ((viewportRatio / frame.imageAspectRatio - 1).abs() > 0.03) {
              return const Align(
                alignment: Alignment.bottomCenter,
                child: ColoredBox(
                  color: Colors.black87,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Esqueleto oculto: el encuadre de cámara y análisis difiere.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              );
            }
            return IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: PoseOverlayPainter(
                    pose: frame,
                    highlightedJoints: highlightedJoints,
                    mirrored:
                        camera.description.lensDirection ==
                        CameraLensDirection.front,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
