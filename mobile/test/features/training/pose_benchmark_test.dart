import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/pose/pose_benchmark.dart';
import 'package:syncdance_mobile/features/training/pose/pose_estimator.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/presentation/camera_training_screen.dart';

import 'camera_training_screen_test.dart' show PreviewCapture;
import 'fake_camera_platform.dart';

PoseFrame pose(int ms, {bool person = true}) => PoseFrame(
  timestampMs: ms,
  imageAspectRatio: 3 / 4,
  poseConfidence: person ? 1 : 0,
  landmarks: person
      ? [PoseLandmark(joint: Joint.nose, x: 0.5, y: 0.2, confidence: 1)]
      : const [],
);

PoseEstimatorStats stats(int processed, int dropped, double ms) =>
    PoseEstimatorStats(
      processedFrames: processed,
      droppedFrames: dropped,
      lastInferenceMs: ms,
    );

/// Stats change as the test feeds results, like a real estimator.
class CountingEstimator implements PoseEstimator {
  final output = StreamController<PoseFrame>.broadcast();
  @override
  PoseEstimatorStats stats = const PoseEstimatorStats();
  @override
  Stream<PoseFrame> start() => output.stream;
  @override
  Future<void> stop() => output.close();
}

void main() {
  test('summarizes rates, percentiles and the start and end windows', () {
    final bench = PoseBenchmark(stats: stats(10, 5, 30), capturedFrames: 100);
    // 60 results over 60 s: inference 20 ms for 30 s, then 40 ms.
    for (var i = 1; i <= 60; i++) {
      bench.sample(
        pose(i * 1000, person: i % 4 != 0),
        stats(10 + i, 5 + i * 2, i <= 30 ? 20 : 40),
      );
    }
    final report = bench.finish(
      elapsedMs: 60000,
      stats: stats(70, 125, 40),
      capturedFrames: 1900,
    );
    expect(report.captureRate, 30);
    expect(report.inferenceRate, 1);
    expect(report.droppedShare, closeTo(120 / 180, 1e-9));
    expect(report.inferenceP50Ms, 20);
    expect(report.inferenceP95Ms, 40);
    expect(report.inferenceMaxMs, 40);
    expect(report.startP50Ms, 20);
    expect(report.endP50Ms, 40);
    expect(report.personShare, 0.75);
    expect(report.text, contains('Captura: 30.0 imágenes/s (1800 recibidas)'));
    expect(report.text, contains('Inferencia: p50 20 ms · p95 40 ms'));
  });

  test('no evidence stays absent, never zero', () {
    final bench = PoseBenchmark(stats: stats(4, 0, 15), capturedFrames: 50);
    // No new processed frame: the old inference time is not a sample.
    bench.sample(pose(100), stats(4, 0, 15));
    // The camera restarted: its counter went backwards.
    final report = bench.finish(
      elapsedMs: 60000,
      stats: stats(4, 0, 15),
      capturedFrames: 3,
    );
    expect(report.inferenceP50Ms, isNull);
    expect(report.startP50Ms, isNull);
    expect(report.capturedFrames, isNull);
    expect(report.captureRate, isNull);
    expect(report.droppedShare, isNull);
    expect(report.text, contains('p50 — ms'));
    expect(PoseBenchmark.percentile(const [], 0.5), isNull);
  });

  test('repeated or older timestamps do not count twice', () {
    final bench = PoseBenchmark(stats: stats(0, 0, 0), capturedFrames: 0);
    bench.sample(pose(1000), stats(1, 0, 10));
    bench.sample(pose(1000), stats(2, 0, 99));
    bench.sample(pose(900), stats(3, 0, 99));
    bench.sample(pose(2000), stats(4, 0, 12));
    bench.sample(pose(3000), stats(5, 0, double.nan));
    final report = bench.finish(
      elapsedMs: 3000,
      stats: stats(5, 0, 12),
      capturedFrames: 90,
    );
    expect(report.results, 3);
    expect(report.inferenceMaxMs, 12);
    expect(report.inferenceP50Ms, 10);
  });

  testWidgets('measures 60 s on the pose screen and copies the summary', (
    tester,
  ) async {
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
    final estimator = CountingEstimator();
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
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
    var time = 0;
    var processed = 0;
    Future<void> emit() async {
      estimator.stats = PoseEstimatorStats(
        processedFrames: ++processed,
        lastInferenceMs: 25,
      );
      estimator.output.add(pose(time += 100));
      await tester.pump();
    }

    await emit();
    await tester.tap(find.text('Medir rendimiento 60 s'));
    await tester.pump();
    for (var second = 0; second < 59; second++) {
      await emit();
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Midiendo rendimiento… 1 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Rendimiento en este teléfono'), findsOneWidget);
    expect(find.textContaining('p50 25 ms'), findsOneWidget);
    await tester.tap(find.text('Copiar'));
    await tester.pumpAndSettle();
    expect(copied, startsWith('pose-benchmark-v1 · 60 s'));
    expect(find.textContaining('Copiado.'), findsOneWidget);

    // Going to background cancels a measurement in progress.
    await tester.tap(find.text('Medir rendimiento 60 s'));
    await tester.pump();
    expect(find.textContaining('Midiendo rendimiento'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Rendimiento en este teléfono'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });
}
