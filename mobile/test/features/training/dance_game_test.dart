import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/comparison/pose_matcher.dart';
import 'package:syncdance_mobile/features/training/comparison/session_summary.dart';
import 'package:syncdance_mobile/features/training/game/dance_game.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';

import '../routines/reference_test_samples.dart';

/// A comparison whose pose similarity is exactly [score].
PoseMatch matchWithScore(double score) =>
    PoseMatch(90 * (1 - score / 100), 1 - score / 100, 0);

const fullAngles = {
  BodyAngle.leftElbow: 90.0,
  BodyAngle.rightElbow: 90.0,
  BodyAngle.leftShoulder: 90.0,
  BodyAngle.rightShoulder: 90.0,
  BodyAngle.leftKnee: 170.0,
  BodyAngle.rightKnee: 170.0,
};

/// 12 Hz reference; [unusable] marks seconds where the master is not ratable.
MotionReference reference(
  int durationMs, {
  Set<int> unusable = const {},
}) => MotionReference(
  ReferenceMetadata.fromJson({...metadataJson(), 'duration_ms': durationMs}),
  [
    for (var i = 0; i * 1000 / 12 < durationMs; i++)
      unusable.contains((i * 1000 / 12) ~/ 1000)
          ? MotionSample((i * 1000 / 12).round(), const {}, 'NO_USABLE_POSE')
          : MotionSample((i * 1000 / 12).round(), fullAngles, 'SINGLE_PERSON'),
  ],
  1,
);

/// Records [score] in every 100 ms bin of [second] (fraction [cover] of it).
void dance(
  SessionAccumulator session,
  int second,
  double score, {
  double cover = 1,
}) {
  for (var bin = 0; bin < (10 * cover).round(); bin++) {
    session.record(second * 1000 + bin * 100, matchWithScore(score));
  }
}

void main() {
  test('moves cover only seconds where the master is measurable', () {
    final moves = DanceGame.movesFor(reference(4300, unusable: {2}));
    expect(moves.map((m) => (m.startMs, m.endMs)), [
      (0, 1000),
      (1000, 2000),
      (3000, 4000),
    ]);
    expect(moves.map((m) => m.index), [0, 1, 2]);
  });

  test('ratings follow the provisional thresholds', () {
    expect(DanceGame.ratingFor(90), MoveRating.perfect);
    expect(DanceGame.ratingFor(85), MoveRating.perfect);
    expect(DanceGame.ratingFor(72), MoveRating.great);
    expect(DanceGame.ratingFor(55), MoveRating.good);
    expect(DanceGame.ratingFor(49.9), MoveRating.miss);
  });

  test('combo grows with hits, a miss breaks it, points accumulate', () {
    final session = SessionAccumulator(5000);
    final game = DanceGame(reference: reference(5000), session: session);
    dance(session, 0, 90);
    dance(session, 1, 75);
    dance(session, 2, 30);
    dance(session, 3, 60);
    dance(session, 4, 88);
    final result = game.finish();
    expect(result.moves.map((m) => m.rating), [
      MoveRating.perfect,
      MoveRating.great,
      MoveRating.miss,
      MoveRating.good,
      MoveRating.perfect,
    ]);
    expect(result.points, 100 + 75 + 0 + 50 + 100);
    expect(result.maxPoints, 500);
    expect(result.maxCombo, 2);
    expect(game.combo, 2);
  });

  test('not measurable is unrated: no points and the combo survives', () {
    final session = SessionAccumulator(3000);
    final game = DanceGame(reference: reference(3000), session: session);
    dance(session, 0, 90);
    dance(session, 1, 90, cover: 0.3); // out of frame most of the move
    dance(session, 2, 90);
    final result = game.finish();
    expect(result.moves[1].rating, isNull);
    expect(result.moves[1].evidence, closeTo(0.3, 1e-9));
    expect(result.count(null), 1);
    expect(result.points, 200);
    expect(result.maxPoints, 300);
    expect(result.maxCombo, 2);
  });

  test('a move is rated only after it settles', () {
    final session = SessionAccumulator(3000);
    final game = DanceGame(reference: reference(3000), session: session);
    dance(session, 0, 90);
    expect(game.advance(1000), isEmpty);
    expect(game.advance(1000 + DanceGame.settleMs - 1), isEmpty);
    final rated = game.advance(1000 + DanceGame.settleMs);
    expect(rated.single.rating, MoveRating.perfect);
    expect(game.points, 100);
    expect(game.finish().moves, hasLength(3));
  });

  test('stars come from the share of the maximum points', () {
    DanceGameResult result(int points) => DanceGameResult(
      points: points,
      maxPoints: 1000,
      maxCombo: 0,
      moves: const [],
    );
    expect(result(0).stars, 0);
    expect(result(299).stars, 0);
    expect(result(300).stars, 1);
    expect(result(600).stars, 3);
    expect(result(899).stars, 4);
    expect(result(1000).stars, 5);
    expect(
      DanceGameResult(
        points: 0,
        maxPoints: 0,
        maxCombo: 0,
        moves: const [],
      ).stars,
      0,
    );
  });

  test('moves to practise are the weakest rated ones, in video order', () {
    final session = SessionAccumulator(5000);
    final game = DanceGame(reference: reference(5000), session: session);
    dance(session, 0, 52);
    dance(session, 1, 95);
    dance(session, 2, 40);
    dance(session, 4, 71);
    final practice = game.finish().toPractice(2);
    expect(practice.map((m) => m.move.index), [0, 2]);
  });

  test('game summary round trips and rejects inconsistent data', () {
    final session = SessionAccumulator(3000);
    final game = DanceGame(reference: reference(3000), session: session);
    dance(session, 0, 90);
    dance(session, 1, 30);
    final summary = GameSummary.of(game.finish());
    final json = summary.toJson();
    final copy = GameSummary.fromJson(json);
    expect(copy.points, 100);
    expect(copy.maxPoints, 300);
    expect(copy.counts, {
      'perfect': 1,
      'great': 0,
      'good': 0,
      'miss': 1,
      'unrated': 1,
    });
    expect(copy.stars, summary.stars);
    for (final broken in [
      {...json, 'points': 400},
      {...json, 'max_points': 200},
      {...json, 'max_combo': 9},
      {
        ...json,
        'counts': {'perfect': 1},
      },
      {...json, 'version': ''},
    ]) {
      expect(() => GameSummary.fromJson(broken), throwsFormatException);
    }
  });
}
