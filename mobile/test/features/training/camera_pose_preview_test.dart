import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/presentation/camera_pose_preview.dart';
import 'package:syncdance_mobile/features/training/presentation/pose_overlay.dart';

import 'fake_camera_platform.dart';

void main() {
  late CameraPlatform original;
  late FakeCameraPlatform platform;
  late CameraController camera;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    original = CameraPlatform.instance;
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    camera = CameraController(
      FakeCameraPlatform.front,
      ResolutionPreset.medium,
    );
    // Exercise the real CameraPreview layout without starting native resources.
    camera.value = camera.value.copyWith(
      isInitialized: true,
      previewSize: const Size(640, 480),
    );
  });

  tearDown(() async {
    await camera.dispose();
    await platform.close();
    CameraPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  PoseFrame pose(double ratio) => PoseFrame(
    timestampMs: 0,
    imageAspectRatio: ratio,
    poseConfidence: 1,
    landmarks: [
      PoseLandmark(joint: Joint.nose, x: 0.25, y: 0.25, confidence: 1),
    ],
  );

  final overlay = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is PoseOverlayPainter,
  );

  for (final orientation in DeviceOrientation.values) {
    testWidgets('overlay shares preview bounds for $orientation', (
      tester,
    ) async {
      final landscape =
          orientation == DeviceOrientation.landscapeLeft ||
          orientation == DeviceOrientation.landscapeRight;
      camera.value = camera.value.copyWith(deviceOrientation: orientation);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: CameraPosePreview(
                camera: camera,
                pose: pose(landscape ? 4 / 3 : 3 / 4),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getRect(overlay),
        tester.getRect(find.byType(CameraPreview)),
      );
      expect(
        tester.getSize(overlay),
        landscape ? const Size(400, 300) : const Size(300, 400),
      );
      final painter =
          tester.widget<CustomPaint>(overlay).painter! as PoseOverlayPainter;
      expect(painter.mirrored, isTrue);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('incompatible crops hide skeleton rather than stretching it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CameraPosePreview(camera: camera, pose: pose(1)),
      ),
    );
    expect(overlay, findsNothing);
    expect(
      find.textContaining('encuadre de cámara y análisis difiere'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
