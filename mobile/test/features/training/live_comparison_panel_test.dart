import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/camera/camera_frame.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/comparison/session_summary.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/presentation/live_comparison_panel.dart';
import 'package:syncdance_mobile/features/training/presentation/pose_overlay.dart';

import '../routines/reference_test_samples.dart';
import 'camera_training_screen_test.dart' show PreviewCapture, PreviewEstimator;
import 'fake_camera_platform.dart';
import 'master_playback_screen_test.dart' show TestPlayer;
import 'mlkit_pose_mapper_test.dart' show sampleFrame;
import 'pose_test_samples.dart' as samples;

class PairedCapture extends PreviewCapture {
  PairedCapture(super.preview);
  final inputs = StreamController<CameraFrame>.broadcast(sync: true);
  @override
  Stream<CameraFrame> get frames => inputs.stream;
  @override
  void dispose() {
    unawaited(inputs.close());
    super.dispose();
  }
}

void main() {
  testWidgets(
    'calibration gates score, pause/seek drop late results and low quality clears it',
    (tester) async {
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
      final capture = PairedCapture(camera);
      final estimator = PreviewEstimator();
      final player = TestPlayer(duration: const Duration(seconds: 4));
      await player.initialize();
      final pose = samples.fixture();
      final angles = const BodyFeatureExtractor().extract(pose).angles;
      final normalized = const PoseNormalizer()
          .normalize(pose)!
          .points
          .map((joint, point) => MapEntry(joint, (x: point.x, y: point.y)));
      var reference = MotionReference(
        ReferenceMetadata.fromJson({...metadataJson(), 'duration_ms': 4000}),
        [
          for (var i = 0; i < 48; i++)
            MotionSample(
              (i * 1000 / 12).round(),
              angles,
              'SINGLE_PERSON',
              normalized: normalized,
            ),
        ],
        1,
      );
      var now = 0;
      final session = SessionAccumulator(4000);
      var epoch = 0;
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LiveComparisonPanel(
              player: player,
              reference: reference,
              enabled: true,
              epoch: epoch,
              session: session,
              capture: capture,
              createPoseEstimator: (_) => estimator,
              nowMs: () => now,
            ),
          ),
        ),
      );
      addTearDown(() async {
        await player.dispose();
        await camera.dispose();
        await platform.close();
        CameraPlatform.instance = original;
      });
      await mount();
      await tester.pump();
      final frame = sampleFrame();
      void captureAt(int time) {
        now = time;
        capture.inputs.add(
          CameraFrame(
            image: frame.image,
            camera: frame.camera,
            orientation: camera.value.deviceOrientation,
            timestampMs: time,
            generation: 0,
          ),
        );
      }

      Future<void> resultAt(int time, {bool valid = true}) async {
        estimator.output.add(
          PoseFrame(
            timestampMs: time,
            imageAspectRatio: pose.imageAspectRatio,
            landmarks: valid ? pose.landmarks : [],
            poseConfidence: valid ? 1 : 0,
          ),
        );
        await tester.pump();
        // Stream delivery during a frame schedules the parent redraw post-frame.
        await tester.pump();
      }

      // Calibrate while the video is paused; there must be no score.
      for (var t = 0; t <= 1000; t += 100) {
        captureAt(t);
        await resultAt(t);
      }
      expect(find.textContaining('Similitud de pose:'), findsNothing);
      expect(session.evaluatedMs, 0);
      await player.play();
      captureAt(1100);
      await resultAt(1100);
      expect(find.textContaining('100/100'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 251));
      expect(find.textContaining('Similitud de pose:'), findsNothing);
      captureAt(1150);
      await resultAt(1150);
      expect(find.textContaining('100/100'), findsOneWidget);

      captureAt(1200);
      await player.pause();
      await resultAt(1200);
      expect(find.textContaining('Similitud de pose:'), findsNothing);
      await player.play();
      captureAt(1300);
      epoch++;
      await mount();
      await player.seekTo(const Duration(milliseconds: 1500));
      await resultAt(1300);
      expect(find.textContaining('Similitud de pose:'), findsNothing);
      captureAt(1400);
      await resultAt(1400);
      expect(find.textContaining('100/100'), findsOneWidget);
      player.value = player.value.copyWith(isBuffering: true);
      await tester.pump();
      expect(find.textContaining('Similitud de pose:'), findsNothing);
      player.value = player.value.copyWith(isBuffering: false);
      captureAt(1450);
      await resultAt(1450);
      expect(find.textContaining('100/100'), findsOneWidget);
      captureAt(1500);
      await resultAt(1500, valid: false);
      expect(find.textContaining('Similitud de pose:'), findsNothing);
      // A short quality loss keeps the framing: measured again at once,
      // without standing still in the middle of the routine.
      captureAt(1600);
      await resultAt(1600);
      expect(find.textContaining('100/100'), findsOneWidget);
      final summary = session.finish(reachedVideoEnd: false);
      // Each frame is bound to the video position at its capture, which runs
      // on between the player's reports: 100, 150, 1600, 1550 and 1700 ms
      // fall in four 100 ms bins.
      expect(summary.evaluatedMs, 400);
      expect(summary.score, 100);
      expect(summary.meanPositionError, 0);
      expect(summary.positionScore, 100);
      expect(summary.coverage, 0.1);
      // A new reference needs fresh sustained evidence before guidance appears.
      reference = MotionReference(reference.metadata, [
        for (final sample in reference.samples)
          MotionSample(
            sample.timestampMs,
            {...angles, BodyAngle.leftElbow: 120},
            'SINGLE_PERSON',
            normalized: normalized,
          ),
      ], 1);
      await player.pause();
      await mount();
      for (var t = 1700; t <= 2700; t += 100) {
        captureAt(t);
        await resultAt(t);
      }
      const correction =
          'Extiende un poco el codo izquierdo para seguir al maestro.';
      expect(find.text(correction), findsNothing);
      Set<Joint> highlights() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<PoseOverlayPainter>()
          .single
          .highlightedJoints;
      expect(highlights(), isEmpty);
      await player.play();
      for (var t = 2800; t <= 3200; t += 100) {
        player.value = player.value.copyWith(
          position: Duration(milliseconds: t - 2800),
        );
        captureAt(t);
        await resultAt(t);
        expect(
          find.text(correction),
          t == 3200 ? findsOneWidget : findsNothing,
        );
        expect(
          highlights(),
          t == 3200
              ? {Joint.leftShoulder, Joint.leftElbow, Joint.leftWrist}
              : isEmpty,
        );
      }
      await player.pause();
      await tester.pump();
      expect(find.text(correction), findsNothing);
      expect(highlights(), isEmpty);
      // Closing a summary still prevents later feedback/scoring from rewriting it.
      expect(summary.evaluatedMs, 400);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
