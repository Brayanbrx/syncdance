import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/comparison/follow_mode.dart';
import 'package:syncdance_mobile/features/training/comparison/session_summary.dart';
import 'package:syncdance_mobile/features/training/history/routine_progress.dart';
import 'package:syncdance_mobile/features/training/history/saved_session.dart';

import '../routines/reference_test_samples.dart';

SavedSession practice(
  double? score, {
  double coverage = 1,
  int day = 1,
  int routine = 7,
  int version = 1,
  String scoring = 'pose-window-v1',
  FollowMode followMode = FollowMode.sameSide,
  double speed = 1.0,
}) {
  final json = metadataJson(version: version)..['routine'] = routine;
  final evaluated = score == null ? 0 : (coverage * 250).round();
  return SavedSession(
    id: newSessionId(),
    routineName: 'Rutina $routine',
    reference: ReferenceMetadata.fromJson(json),
    startedAt: DateTime.utc(2026, 10, day),
    finishedAt: DateTime.utc(2026, 10, day, 0, 1),
    summary: SessionSummary(
      durationMs: 250,
      evaluatedMs: evaluated,
      score: score,
      meanErrorDegrees: score == null ? null : 10,
      meanPositionError: score == null ? null : 0.2,
      angleScore: score,
      positionScore: score,
      reachedVideoEnd: true,
      segments: const [],
      scoringVersion: scoring,
      followMode: followMode,
      playbackSpeed: speed,
    ),
  );
}

void main() {
  const calculator = RoutineProgressCalculator();

  test('best mark and change use comparable practices in time order', () {
    final progress = calculator.compute([
      practice(70, day: 3),
      practice(60, day: 1),
      practice(82, day: 2),
    ]).single;
    expect(progress.best!.summary.score, 82);
    expect(progress.latest!.summary.score, 70);
    expect(progress.change, -12);
    expect(progress.recentScores(), [60, 82, 70]);
    expect(progress.excluded, 0);
  });

  test('a real zero counts, missing evidence and low coverage do not', () {
    final progress = calculator.compute([
      practice(0, day: 1),
      practice(null, day: 2),
      practice(95, day: 3, coverage: 0.3),
      practice(40, day: 4),
    ]).single;
    expect(progress.recentScores(), [0, 40]);
    expect(progress.change, 40);
    expect(progress.excluded, 2);
    expect(progress.best!.summary.score, 40);
  });

  test('another reference or scoring version is never compared', () {
    final progress = calculator.compute([
      practice(90, day: 1, version: 1),
      practice(50, day: 2, scoring: 'pose-window-v0'),
      practice(60, day: 3, version: 2),
    ]).single;
    expect(progress.referenceVersion, 2);
    expect(progress.recentScores(), [60]);
    expect(progress.change, isNull);
    expect(progress.excluded, 2);
  });

  test('mirror and same-side practices are never compared', () {
    final progress = calculator.compute([
      practice(90, day: 1),
      practice(55, day: 2, followMode: FollowMode.mirror),
      practice(65, day: 3, followMode: FollowMode.mirror),
    ]).single;
    expect(progress.recentScores(), [55, 65]);
    expect(progress.best!.summary.score, 65);
    expect(progress.excluded, 1);
  });

  test('learn-mode speeds are never compared with normal speed', () {
    final progress = calculator.compute([
      practice(90, day: 1, speed: 0.5),
      practice(60, day: 2),
      practice(70, day: 3),
    ]).single;
    expect(progress.recentScores(), [60, 70]);
    expect(progress.excluded, 1);
  });

  test('routines are separate and ordered by their last practice', () {
    final result = calculator.compute([
      practice(50, routine: 7, day: 1),
      practice(65, routine: 8, day: 2),
      practice(null, routine: 9, day: 3),
    ]);
    expect(result.map((p) => p.routineName), [
      'Rutina 9',
      'Rutina 8',
      'Rutina 7',
    ]);
    expect(result.first.best, isNull);
    expect(result.first.excluded, 1);
  });

  test('ties keep the first time the mark was reached', () {
    final first = practice(80, day: 1);
    final progress = calculator.compute([practice(80, day: 2), first]).single;
    expect(identical(progress.best, first), isTrue);
  });

  test('recent scores keep only the last five', () {
    final progress = calculator.compute([
      for (var d = 1; d <= 7; d++) practice(d * 10.0, day: d),
    ]).single;
    expect(progress.recentScores(), [30, 40, 50, 60, 70]);
  });
}
