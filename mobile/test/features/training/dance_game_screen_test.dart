import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/routines/reference/reference_cache.dart';
import 'package:syncdance_mobile/features/training/camera/camera_frame.dart';
import 'package:syncdance_mobile/features/training/comparison/follow_mode.dart';
import 'package:syncdance_mobile/features/training/game/dance_game.dart';
import 'package:syncdance_mobile/features/training/history/calibration_log.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/presentation/dance_game_screen.dart';
import 'package:syncdance_mobile/features/training/presentation/game_sounds.dart';
import 'package:syncdance_mobile/features/training/presentation/move_drill_screen.dart';
import 'package:syncdance_mobile/features/training/presentation/move_pictogram.dart';

import '../routines/reference_test_samples.dart';
import 'game_sounds_test.dart' show recordingSounds;
import 'camera_training_screen_test.dart' show PreviewEstimator;
import 'fake_camera_platform.dart';
import 'live_comparison_panel_test.dart' show PairedCapture;
import 'master_playback_screen_test.dart' show MemorySessionStore, TestPlayer;
import 'mlkit_pose_mapper_test.dart' show sampleFrame;
import 'pose_test_samples.dart' as samples;

/// Fake camera, estimator and player around a 3 s master of the fixture pose.
class GameHarness {
  GameHarness(this.tester);
  final WidgetTester tester;
  late final CameraPlatform original;
  late final FakeCameraPlatform platform;
  late final CameraController camera;
  late final PairedCapture capture;
  final estimator = PreviewEstimator();
  final player = TestPlayer(duration: const Duration(seconds: 3));
  final store = MemorySessionStore();
  final pose = samples.fixture();
  final frame = sampleFrame();
  var now = 0;
  var cameraMs = 0;
  var synced = 0;

  /// Cue names played by the real [GameSounds] over recording players.
  final cues = <String>[];
  late final sounds = recordingSounds(cues);

  /// Set before mounting: the reference reads it once.
  Map<String, dynamic>? scoringProfile;
  CalibrationLog? calibrationLog;
  late final MotionReference reference = _reference();

  MotionReference _reference() {
    final features = const BodyFeatureExtractor().extract(pose);
    final normalized = features.pose!.points.map(
      (joint, point) => MapEntry(joint, (x: point.x, y: point.y)),
    );
    return MotionReference(
      ReferenceMetadata.fromJson({
        ...metadataJson(),
        'duration_ms': 3000,
        'scoring_profile': ?scoringProfile,
      }),
      [
        for (var i = 0; i < 36; i++)
          MotionSample(
            (i * 1000 / 12).round(),
            features.angles,
            'SINGLE_PERSON',
            normalized: normalized,
          ),
      ],
      1,
    );
  }

  Future<void> mount({
    Widget Function(DanceMove move)? openDrill,
    String instructions = '',
  }) => _pump(
    () => DanceGameScreen(
      instructions: instructions,
      saved: SavedReference('Guerrero II', reference),
      videoFile: File('master.mp4'),
      storeScope: 'test',
      followMode: FollowMode.sameSide,
      sessionStore: store,
      onSessionSaved: () async => synced++,
      createController: (_) => player,
      capture: capture,
      createPoseEstimator: (_) => estimator,
      nowMs: () => now,
      openDrill: openDrill,
      sounds: sounds,
      calibrationLog: calibrationLog,
    ),
  );

  Future<void> mountDrill(DanceMove move, {RoutineStep? step}) => _pump(
    () => MoveDrillScreen(
      saved: SavedReference('Guerrero II', reference),
      videoFile: File('master.mp4'),
      move: move,
      step: step,
      followMode: FollowMode.sameSide,
      createController: (_) => player,
      capture: capture,
      createPoseEstimator: (_) => estimator,
      nowMs: () => now,
      sounds: sounds,
    ),
  );

  /// [screen] is built once the fake camera exists.
  Future<void> _pump(Widget Function() screen) async {
    original = CameraPlatform.instance;
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    camera = CameraController(
      FakeCameraPlatform.front,
      ResolutionPreset.medium,
    );
    camera.value = camera.value.copyWith(
      isInitialized: true,
      previewSize: const Size(640, 480),
    );
    capture = PairedCapture(camera);
    addTearDown(() async {
      await camera.dispose();
      await platform.close();
      CameraPlatform.instance = original;
    });
    await tester.pumpWidget(MaterialApp(home: screen()));
    await tester.pump();
  }

  /// One captured camera frame and its inference result.
  Future<void> step({
    bool valid = true,
    int advanceMs = 0,
    PoseFrame? as,
  }) async {
    now = cameraMs;
    capture.inputs.add(
      CameraFrame(
        image: frame.image,
        camera: frame.camera,
        orientation: camera.value.deviceOrientation,
        timestampMs: cameraMs,
        generation: 0,
      ),
    );
    estimator.output.add(
      PoseFrame(
        timestampMs: cameraMs,
        imageAspectRatio: pose.imageAspectRatio,
        landmarks: valid ? (as ?? pose).landmarks : [],
        poseConfidence: valid ? 1 : 0,
      ),
    );
    cameraMs += 100;
    await tester.pump(Duration(milliseconds: advanceMs));
    await tester.pump();
  }

  Future<void> calibrate() async {
    for (var i = 0; i <= 10; i++) {
      await step();
    }
  }

  /// Frames keep arriving during the countdown, as on a real phone.
  Future<void> countdown() async {
    for (var i = 0; i < 30 && !player.value.isPlaying; i++) {
      await step(advanceMs: 100);
    }
  }

  Future<void> playAt(int position, {bool valid = true, PoseFrame? as}) async {
    player.value = player.value.copyWith(
      position: Duration(milliseconds: position),
    );
    await step(valid: valid, as: as);
  }

  Future<void> complete() async {
    player.value = player.value.copyWith(
      position: const Duration(seconds: 3),
      isPlaying: false,
      isCompleted: true,
    );
    await tester.pump();
    await tester.pump();
  }
}

/// Framing tries kept in memory (the real log writes a file).
class MemoryCalibrationLog extends CalibrationLog {
  MemoryCalibrationLog([this.count = CalibrationCount.none])
    : super(File('unused'));
  CalibrationCount count;
  final tries = <bool>[];

  @override
  Future<CalibrationCount> pending() async => count;

  @override
  Future<void> record({required bool calibrated}) async {
    tries.add(calibrated);
    count = CalibrationCount(
      count.attempts + 1,
      count.calibrated + (calibrated ? 1 : 0),
    );
  }

  @override
  Future<void> clear(CalibrationCount sent) async => count = CalibrationCount(
    count.attempts - sent.attempts,
    count.calibrated - sent.calibrated,
  );
}

void main() {
  tearDown(() => GameSounds.enabled = true);

  testWidgets('framing tries travel with the saved game and leave the log', (
    tester,
  ) async {
    // One try given up on before this game.
    final log = MemoryCalibrationLog(const CalibrationCount(1, 0));
    final game = GameHarness(tester)..calibrationLog = log;
    await game.mount();
    await game.calibrate();
    await game.countdown();
    for (var position = 0; position <= 2900; position += 100) {
      await game.playAt(position);
    }
    await game.complete();
    final saved = game.store.records.values.single;
    expect(
      (saved.calibration!.attempts, saved.calibration!.calibrated),
      (2, 1),
    );
    expect(log.tries, [true]);
    expect(log.count.isEmpty, isTrue);
  });

  testWidgets('leaving before getting into position is a failed try', (
    tester,
  ) async {
    final log = MemoryCalibrationLog();
    final game = GameHarness(tester)..calibrationLog = log;
    await game.mount();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(log.tries, [false]);
  });

  testWidgets(
    'hands-free countdown, PERFECT moves, stars and a saved game summary',
    (tester) async {
      final game = GameHarness(tester);
      await game.mount();
      expect(find.textContaining('El baile empieza solo'), findsOneWidget);
      // The first moves are previewed before the song starts.
      expect(find.byKey(const ValueKey('pictogram-0')), findsOneWidget);
      expect(find.byType(MovePictogram), findsNWidgets(3));
      await game.calibrate();
      expect(find.text('3'), findsOneWidget);
      await game.countdown();
      expect(game.player.value.isPlaying, isTrue);
      // Heard from 2-3 m: a tick per number and a brighter cue to start.
      expect(game.cues, ['tick', 'tick', 'tick', 'go']);

      for (var position = 0; position <= 2900; position += 100) {
        await game.playAt(position);
        if (position == 1500) {
          expect(find.text('PERFECT'), findsOneWidget);
          expect(find.text('100'), findsOneWidget);
          // Moves already started leave the strip; the last one is next.
          expect(find.byType(MovePictogram), findsOneWidget);
          expect(find.byKey(const ValueKey('pictogram-2')), findsOneWidget);
        }
      }
      await game.complete();
      // The last move is rated when the song ends, on the results screen.
      expect(game.cues.skip(4), ['perfect', 'perfect']);

      expect(find.text('★★★★★'), findsOneWidget);
      expect(find.text('300 pts'), findsOneWidget);
      expect(find.text('PERFECT: 3'), findsOneWidget);
      expect(find.textContaining('guardado en tu historial'), findsOneWidget);
      final saved = game.store.records.values.single;
      expect(saved.game!.points, 300);
      expect(saved.game!.stars, 5);
      expect(saved.game!.counts[MoveRating.perfect.name], 3);
      expect(saved.summary.followMode, FollowMode.sameSide);
      // The game shows no textual cues, so none are counted as shown.
      expect(saved.summary.feedback, isEmpty);
      expect(game.synced, 1);
    },
  );

  testWidgets('the step instructions are read while getting into position', (
    tester,
  ) async {
    final game = GameHarness(tester);
    await game.mount(instructions: 'Paso a un lado y junta.');
    expect(find.text('Cómo se hace: Paso a un lado y junta.'), findsOneWidget);
    await game.calibrate();
    await game.countdown();
    expect(find.textContaining('Cómo se hace'), findsNothing);
  });

  testWidgets('the game keeps the phone vertical and releases it on exit', (
    tester,
  ) async {
    final orientations = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final game = GameHarness(tester);
    await game.mount();
    expect(orientations, [
      ['DeviceOrientation.portraitUp'],
    ]);
    await tester.pumpWidget(const SizedBox());
    expect(orientations.last, isEmpty);
  });

  testWidgets('the sound button mutes the cues', (tester) async {
    final game = GameHarness(tester);
    await game.mount();
    await tester.tap(find.byTooltip('Silenciar sonidos'));
    await tester.pump();
    expect(find.byTooltip('Activar sonidos'), findsOneWidget);
    await game.calibrate();
    await game.countdown();
    expect(game.player.value.isPlaying, isTrue);
    expect(game.cues, isEmpty);
  });

  testWidgets('leaving the frame is unmeasured, never a miss', (tester) async {
    final game = GameHarness(tester);
    await game.mount();
    await game.calibrate();
    await game.countdown();
    for (var position = 0; position <= 2900; position += 100) {
      final away = position >= 1000 && position < 2000;
      await game.playAt(position, valid: !away);
      if (position == 1500) {
        expect(find.textContaining('Vuelve al encuadre'), findsOneWidget);
      }
    }
    await game.complete();
    final saved = game.store.records.values.single;
    expect(saved.game!.counts['miss'], 0);
    expect(saved.game!.counts['unrated'], greaterThanOrEqualTo(1));
    expect(
      find.textContaining('Sin medir (fuera de encuadre)'),
      findsOneWidget,
    );
    // Unmeasured time is not evidence in the technical summary either.
    expect(saved.summary.evaluatedMs, lessThan(3000));
  });

  testWidgets('a stalled camera cancels the countdown and asks to come back', (
    tester,
  ) async {
    final game = GameHarness(tester);
    await game.mount();
    await game.calibrate();
    expect(find.text('3'), findsOneWidget);
    // No pose for longer than the camera's 500 ms expiry: nothing is measured.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('3'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(game.player.value.isPlaying, isFalse);

    await game.calibrate();
    await game.countdown();
    await game.playAt(500);
    expect(find.textContaining('Vuelve al encuadre'), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('Vuelve al encuadre'), findsOneWidget);
  });

  testWidgets('walking away during the countdown cancels it', (tester) async {
    final game = GameHarness(tester);
    await game.mount();
    await game.calibrate();
    expect(find.text('3'), findsOneWidget);
    await game.step(valid: false, advanceMs: 100);
    expect(find.text('3'), findsNothing);
    expect(find.textContaining('Colócate frente a la cámara'), findsOneWidget);
    for (var i = 0; i < 40; i++) {
      await game.step(valid: false, advanceMs: 100);
    }
    expect(game.player.value.isPlaying, isFalse);
  });
}
