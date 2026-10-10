import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/camera/camera_capture.dart';
import 'package:syncdance_mobile/features/training/presentation/camera_training_screen.dart';
import 'package:syncdance_mobile/features/training/presentation/pose_overlay.dart';
import 'package:syncdance_mobile/features/training/presentation/pose_measurements_panel.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/pose/pose_estimator.dart';

import 'fake_camera_platform.dart';
import 'pose_test_samples.dart' as samples;

class PreviewCapture extends CameraCapture {
  PreviewCapture(this.preview);
  final CameraController preview;
  CaptureStatus currentStatus = CaptureStatus.streaming;

  @override
  CameraController get controller => preview;

  @override
  CaptureStatus get status => currentStatus;

  @override
  Future<void> start() async {}

  @override
  Future<void> setForeground(bool foreground) async {
    currentStatus = foreground ? CaptureStatus.streaming : CaptureStatus.paused;
    notifyListeners();
  }
}

class PreviewEstimator implements PoseEstimator {
  final output = StreamController<PoseFrame>.broadcast();

  @override
  PoseEstimatorStats get stats => const PoseEstimatorStats(
    processedFrames: 1,
    droppedFrames: 0,
    lastInferenceMs: 20,
  );

  @override
  Stream<PoseFrame> start() => output.stream;

  @override
  Future<void> stop() => output.close();
}

// Native startup/stream/disposal are tested in camera_capture_test.dart.
// Widget tests verify recovery controls without starting native resources.
class DeniedCapture extends CameraCapture {
  int attempts = 0;
  bool released = false;

  @override
  CaptureStatus get status => CaptureStatus.failed;

  @override
  String get errorCode => 'CameraAccessDeniedWithoutPrompt';

  @override
  Future<void> start() async {
    attempts++;
  }

  @override
  void dispose() {
    released = true;
    super.dispose();
  }
}

void main() {
  testWidgets(
    'live overlay toggles and clears after timeout, rotation and pause',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final original = CameraPlatform.instance;
      final platform = FakeCameraPlatform();
      CameraPlatform.instance = platform;
      final camera = CameraController(
        FakeCameraPlatform.front,
        ResolutionPreset.medium,
      );
      camera.value = camera.value.copyWith(
        isInitialized: true,
        previewSize: const Size(640, 480),
      );
      final capture = PreviewCapture(camera);
      final estimator = PreviewEstimator();
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        await camera.dispose();
        await platform.close();
        CameraPlatform.instance = original;
        debugDefaultTargetPlatformOverride = null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: CameraTrainingScreen(
            capture: capture,
            createPoseEstimator: (_) => estimator,
          ),
        ),
      );
      final overlay = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is PoseOverlayPainter,
      );
      var frameTime = 0;
      Future<void> emit({bool fullBody = false}) async {
        estimator.output.add(
          PoseFrame(
            timestampMs: frameTime += 100,
            imageAspectRatio: 3 / 4,
            poseConfidence: 1,
            landmarks: fullBody
                ? samples.fixture().landmarks
                : [
                    PoseLandmark(
                      joint: Joint.nose,
                      x: 0.5,
                      y: 0.25,
                      confidence: 1,
                    ),
                  ],
          ),
        );
        await tester.pump();
      }

      await emit();
      expect(overlay, findsOneWidget);
      expect(find.byType(PoseMeasurementsPanel), findsOneWidget);
      await tester.tap(find.byTooltip('Ocultar esqueleto'));
      await tester.pump();
      expect(overlay, findsNothing);
      await tester.tap(find.byTooltip('Mostrar esqueleto'));
      await tester.pump();
      expect(overlay, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 501));
      expect(overlay, findsNothing);
      expect(find.byType(PoseMeasurementsPanel), findsNothing);
      await emit();
      camera.value = camera.value.copyWith(
        deviceOrientation: DeviceOrientation.portraitDown,
      );
      await tester.pump();
      expect(overlay, findsNothing);
      camera.value = camera.value.copyWith(
        deviceOrientation: DeviceOrientation.portraitUp,
      );
      await tester.pump();
      expect(overlay, findsNothing);
      await emit();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Cámara pausada'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(overlay, findsNothing);
      await emit();
      expect(overlay, findsOneWidget);
      for (final size in [const Size(844, 390), const Size(390, 844)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pump();
        expect(find.byType(PoseMeasurementsPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      for (var i = 0; i < 11; i++) {
        await emit(fullBody: true);
      }
      expect(find.textContaining('Codos:'), findsOneWidget);
      // A rebuild/toggle must not be counted as another calibration sample.
      await tester.ensureVisible(find.text('Recalibrar encuadre'));
      await tester.tap(find.text('Recalibrar encuadre'));
      await tester.pump();
      expect(find.textContaining('Codos:'), findsNothing);
      await emit(fullBody: true);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        await emit(fullBody: true);
      }
      expect(find.textContaining('Codos:'), findsOneWidget);
      await emit();
      expect(find.textContaining('Codos:'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('denied permission explains settings and exposes retry', (
    tester,
  ) async {
    final capture = DeniedCapture();
    await tester.pumpWidget(
      MaterialApp(home: CameraTrainingScreen(capture: capture)),
    );
    expect(find.textContaining('ajustes del teléfono'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    expect(capture.attempts, 2);
    await tester.pumpWidget(const SizedBox());
    expect(capture.released, isTrue);
  });

  testWidgets('desktop explains that a phone is needed', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(const MaterialApp(home: CameraTrainingScreen()));
    await tester.pumpAndSettle();
    expect(
      find.text('Abre esta prueba en un teléfono Android o iPhone.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
