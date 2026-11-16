import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/game/dance_game.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/presentation/move_pictogram.dart';

import 'dance_game_screen_test.dart' show GameHarness;
import 'pose_test_samples.dart' as samples;

/// The fixture with both arms down: four of the six angles change (GOOD).
PoseFrame armsDown(PoseFrame pose) => samples.modify(
  pose,
  (p) => switch (p.joint) {
    Joint.leftElbow => PoseLandmark(
      joint: p.joint,
      x: 0.25,
      y: 0.42,
      confidence: p.confidence,
    ),
    Joint.leftWrist => PoseLandmark(
      joint: p.joint,
      x: 0.22,
      y: 0.52,
      confidence: p.confidence,
    ),
    Joint.rightElbow => PoseLandmark(
      joint: p.joint,
      x: 0.75,
      y: 0.42,
      confidence: p.confidence,
    ),
    Joint.rightWrist => PoseLandmark(
      joint: p.joint,
      x: 0.78,
      y: 0.52,
      confidence: p.confidence,
    ),
    _ => p,
  },
);

void main() {
  testWidgets('the move loops slower with a run-up and every pass is rated', (
    tester,
  ) async {
    final game = GameHarness(tester);
    await game.mountDrill(const DanceMove(1, 1000, 2000));
    expect(find.text('Practicar 0:01–0:02'), findsOneWidget);
    expect(find.byType(MovePictogram), findsOneWidget);
    expect(game.player.value.playbackSpeed, 0.5);
    await game.calibrate();
    await game.countdown();
    expect(game.player.value.isPlaying, isTrue);

    // Pass 1, danced right: rated once the move settles (2000 + 400 ms).
    for (var position = 0; position < 2400; position += 100) {
      await game.playAt(position);
    }
    expect(find.text('PERFECT'), findsNothing);
    await game.playAt(2400);
    expect(find.text('PERFECT'), findsOneWidget);
    expect(find.text('Pasadas: 1 · mejor: PERFECT'), findsOneWidget);
    expect(game.cues, ['tick', 'tick', 'tick', 'go', 'perfect']);
    // Back to the run-up, one move before, and still playing.
    expect(game.player.value.position, Duration.zero);
    expect(game.player.value.isPlaying, isTrue);

    // Pass 2 with the arms down: a fresh pass, so pass 1 does not mix in.
    final wrong = armsDown(game.pose);
    for (var position = 0; position <= 2400; position += 100) {
      await game.playAt(position, as: wrong);
    }
    expect(find.text('GOOD'), findsOneWidget);
    expect(find.text('Pasadas: 2 · mejor: PERFECT'), findsOneWidget);

    // Out of frame for the whole move: unmeasured, never a miss.
    for (var position = 0; position <= 2400; position += 100) {
      await game.playAt(position, valid: position < 1000);
    }
    expect(find.text('SIN MEDIR'), findsOneWidget);
    expect(find.text('Pasadas: 3 · mejor: PERFECT'), findsOneWidget);
    // Not being seen is not a mistake: no MISS cue for an unmeasured pass.
    expect(game.cues.skip(4), ['perfect', 'good']);
  });

  testWidgets('an instructor step shows its name, tip and the counts', (
    tester,
  ) async {
    final game = GameHarness(tester)
      ..scoringProfile = {
        'beat_grid': {
          'version': 'beat-grid-v1',
          'bpm': 120,
          'first_beat_ms': 1000,
          'beats_per_move': 2,
        },
      };
    const step = RoutineStep(
      index: 1,
      name: 'Giro',
      startMs: 1000,
      endMs: 2000,
      counts: 2,
      tip: 'Mira al frente al terminar.',
    );
    await game.mountDrill(const DanceMove(1, 1000, 2000), step: step);
    expect(find.text('Giro'), findsOneWidget);
    expect(find.text('Mira al frente al terminar.'), findsOneWidget);
    await game.calibrate();
    await game.countdown();
    // 120 BPM from 1000 ms: 1600 ms is the second beat of the first eight.
    await game.playAt(1600);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('ocho 1'), findsOneWidget);
  });

  testWidgets('a stalled camera stops the countdown of the drill', (
    tester,
  ) async {
    final game = GameHarness(tester);
    await game.mountDrill(const DanceMove(1, 1000, 2000));
    await game.calibrate();
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('3'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(game.player.value.isPlaying, isFalse);
  });

  testWidgets('a faster speed applies at once and restarts the pass', (
    tester,
  ) async {
    final game = GameHarness(tester);
    await game.mountDrill(const DanceMove(1, 1000, 2000));
    await game.calibrate();
    await game.countdown();
    await game.playAt(1500);
    await tester.tap(find.text('1×'));
    await tester.pump();
    expect(game.player.value.playbackSpeed, 1.0);
    expect(game.player.value.position, Duration.zero);
    expect(game.player.value.isPlaying, isTrue);
  });

  testWidgets('the last move of the song loops when the video completes', (
    tester,
  ) async {
    final game = GameHarness(tester);
    await game.mountDrill(const DanceMove(2, 2000, 3000));
    // The run-up starts one move earlier.
    expect(game.player.value.position, const Duration(seconds: 1));
    await game.calibrate();
    await game.countdown();
    for (var position = 1000; position <= 2900; position += 100) {
      await game.playAt(position);
    }
    await game.complete();
    expect(find.text('PERFECT'), findsOneWidget);
    expect(game.player.value.position, const Duration(seconds: 1));
    expect(game.player.value.isPlaying, isTrue);
  });

  testWidgets('a weak move in the results opens its drill', (tester) async {
    final game = GameHarness(tester);
    final opened = <DanceMove>[];
    await game.mount(
      openDrill: (move) {
        opened.add(move);
        return const Scaffold(body: Text('Ejercicio abierto'));
      },
    );
    await game.calibrate();
    await game.countdown();
    final wrong = armsDown(game.pose);
    for (var position = 0; position <= 2900; position += 100) {
      final weak = position >= 1000 && position < 2000;
      await game.playAt(position, as: weak ? wrong : null);
    }
    await game.complete();
    expect(find.text('GOOD: 1'), findsOneWidget);
    expect(find.text('Movimientos para practicar'), findsOneWidget);
    // The weak move shows its pose next to «Practicar».
    expect(find.byType(MovePictogram), findsOneWidget);
    await tester.ensureVisible(find.text('Practicar'));
    await tester.tap(find.text('Practicar'));
    await tester.pumpAndSettle();
    expect(find.text('Ejercicio abierto'), findsOneWidget);
    expect(opened.map((m) => (m.index, m.startMs, m.endMs)), [(1, 1000, 2000)]);
    // The game waits paused underneath.
    expect(game.player.value.isPlaying, isFalse);
  });
}
