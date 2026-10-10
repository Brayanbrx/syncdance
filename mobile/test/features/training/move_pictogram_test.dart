import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/game/dance_game.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/presentation/move_pictogram.dart';

import '../routines/reference_test_samples.dart';
import 'dance_game_test.dart' show fullAngles;

const grid = {
  'beat_grid': {
    'version': 'beat-grid-v1',
    'bpm': 120,
    'first_beat_ms': 2000,
    'beats_per_move': 2,
  },
};

/// 12 Hz master; [empty] seconds have no drawable master.
MotionReference reference(
  int durationMs, {
  bool withGrid = false,
  Set<int> empty = const {},
}) => MotionReference(
  ReferenceMetadata.fromJson({
    ...metadataJson(),
    'duration_ms': durationMs,
    if (withGrid) 'scoring_profile': grid,
  }),
  [
    for (var i = 0; i * 1000 / 12 < durationMs; i++)
      if (empty.contains((i * 1000 / 12) ~/ 1000))
        MotionSample((i * 1000 / 12).round(), const {}, 'NO_USABLE_POSE')
      else
        MotionSample(
          (i * 1000 / 12).round(),
          fullAngles,
          'SINGLE_PERSON',
          normalized: {
            Joint.leftShoulder: (x: 0.3, y: -1.0),
            Joint.rightShoulder: (x: -0.3, y: -1.0),
          },
        ),
  ],
  1,
);

void main() {
  test('with a beat grid the pictogram is the pose on the opening beat', () {
    final master = reference(5000, withGrid: true);
    final move = DanceGame.movesFor(master).first;
    expect(move.startMs, 2000);
    // Samples land every 83.3 ms: 2000 ms is sample 24 exactly.
    expect(keySample(master, move)!.timestampMs, 2000);
  });

  test('without a grid the pictogram is the middle of the move', () {
    final master = reference(3000);
    final move = DanceGame.movesFor(master)[1];
    expect((move.startMs, move.endMs), (1000, 2000));
    expect(keySample(master, move)!.timestampMs, 1500);
  });

  test('only drawable samples inside the move are used', () {
    final master = reference(3000, empty: {1});
    // Second 1 has no master: no move there and nothing borrowed from others.
    expect(keySample(master, const DanceMove(0, 1000, 2000)), isNull);
  });

  testWidgets('the strip shows the next moves, the imminent one highlighted', (
    tester,
  ) async {
    final master = reference(5000);
    final moves = DanceGame.movesFor(master);
    final poses = [for (final move in moves) keySample(master, move)];
    Future<void> at(int positionMs) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpcomingMoves(
            moves: moves,
            poses: poses,
            positionMs: positionMs,
          ),
        ),
      ),
    );

    await at(0);
    expect(find.byType(MovePictogram), findsNWidgets(3));
    MovePictogram pictogram(int index) =>
        tester.widget(find.byKey(ValueKey('pictogram-$index')));
    expect(pictogram(0).highlighted, isTrue);
    expect(pictogram(1).highlighted, isFalse);
    expect(find.byKey(const ValueKey('pictogram-3')), findsNothing);

    await at(3500);
    expect(find.byKey(const ValueKey('pictogram-4')), findsOneWidget);
    expect(find.byType(MovePictogram), findsOneWidget);

    await at(4001);
    expect(find.byType(MovePictogram), findsNothing);
  });
}
