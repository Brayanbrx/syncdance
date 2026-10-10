import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/comparison/pose_matcher.dart';
import 'package:syncdance_mobile/features/training/comparison/session_summary.dart';
import 'package:syncdance_mobile/features/training/presentation/session_summary_panel.dart';
import 'feedback_test.dart' show cue;

void main() {
  test(
    'feedback counts only evidence-backed occurrences and deduplicates replay bins',
    () {
      final session = SessionAccumulator(1000);
      session.recordFeedback(0, cue('a'));
      session.record(0, const PoseMatch(0, 0, 0));
      session.record(100, const PoseMatch(0, 0, 0));
      session.recordFeedback(0, cue('a'));
      session.recordFeedback(10, cue('a'));
      session.recordFeedback(100, cue('a', magnitude: 40));
      session.recordFeedback(100, cue('b'));
      session.recordFeedback(100, cue('c', magnitude: 1));
      final summary = session.finish(reachedVideoEnd: false);
      session.recordFeedback(100, cue('late'));
      expect(summary.feedback.map((f) => f.code), ['a', 'b']);
      expect(summary.feedback.first.count, 2);
      expect(summary.feedback.first.maxSeverity, 2);
      expect(() => summary.feedback.clear(), throwsUnsupportedError);
    },
  );
  test(
    'weights unique video intervals and short final interval, not sample count',
    () {
      final session = SessionAccumulator(250);
      session.record(0, const PoseMatch(0, 0, 0));
      session.record(100, const PoseMatch(45, 0.5, 0));
      session.record(200, const PoseMatch(90, 1, 0));
      for (var i = 0; i < 50; i++) {
        session.record(110, const PoseMatch(0, 0, 0));
      }
      final result = session.finish(reachedVideoEnd: true);
      expect(result.evaluatedMs, 250);
      expect(result.coverage, 1);
      expect(result.score, 60);
      expect(result.meanErrorDegrees, 36);
      expect(result.meanPositionError, 0.4);
      expect(result.angleScore, 60);
      expect(result.positionScore, 60);
      expect(result.scoringVersion, 'pose-window-v1');
      expect(result.summaryVersion, 'pose-summary-v1');
    },
  );
  test(
    'gaps and skipped video remain uncovered; replay cannot replace first valid evidence',
    () {
      final session = SessionAccumulator(5500);
      session.record(1000, null);
      session.record(1000, const PoseMatch(90, 1, 0));
      session.record(1090, const PoseMatch(0, 0, 0));
      session.record(5000, const PoseMatch(0, 0, 0));
      final result = session.finish(reachedVideoEnd: false);
      expect(result.evaluatedMs, 200);
      expect(result.score, 50);
      expect(result.coverage, closeTo(200 / 5500, 1e-9));
      expect(result.segments[0].score, 0); // Real zero remains evidence.
      expect(result.segments[0].coverage, 0.02);
      expect(result.segments[1].coverage, 0.2);
    },
  );
  test('no evidence is null even when video reaches its end', () {
    final session = SessionAccumulator(12000);
    for (final t in [-1, 12000]) {
      session.record(t, const PoseMatch(0, 0, 0));
    }
    session.record(0, const PoseMatch(double.nan, 0, 0));
    session.record(100, const PoseMatch(181, 0, 0));
    session.record(200, const PoseMatch(45, double.infinity, 0));
    session.record(300, const PoseMatch(0, -1, 0));
    final result = session.finish(reachedVideoEnd: true);
    expect(result.score, isNull);
    expect(result.meanErrorDegrees, isNull);
    expect(result.meanPositionError, isNull);
    expect(result.coverage, 0);
    expect(result.segments.map((s) => s.score), everyElement(isNull));
  });
  test(
    'finished result is immutable, idempotent and ignores late inference',
    () {
      final session = SessionAccumulator(200);
      session.record(0, const PoseMatch(45, 0.5, 0));
      final result = session.finish(reachedVideoEnd: false);
      session.record(100, const PoseMatch(0, 0, 0));
      expect(identical(session.finish(reachedVideoEnd: true), result), isTrue);
      expect(result.reachedVideoEnd, isFalse);
      expect(result.evaluatedMs, 100);
      expect(result.score, 50);
      expect(() => result.segments.clear(), throwsUnsupportedError);
    },
  );
  testWidgets(
    'empty summary explains missing evidence; partial score includes coverage',
    (tester) async {
      final session = SessionAccumulator(1000);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionSummaryPanel(
              summary: session.finish(reachedVideoEnd: true),
              referenceVersion: 2,
            ),
          ),
        ),
      );
      expect(
        find.text('Similitud: —. Sin comparaciones válidas.'),
        findsOneWidget,
      );
      expect(find.text('Cobertura estimada: 0.0 %'), findsOneWidget);
      final partial = SessionAccumulator(1000)
        ..record(0, const PoseMatch(0, 0, 0));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionSummaryPanel(
              summary: partial.finish(reachedVideoEnd: false),
              referenceVersion: 2,
            ),
          ),
        ),
      );
      expect(find.textContaining('evaluados: 100/100'), findsOneWidget);
      expect(find.text('Cobertura estimada: 10.0 %'), findsOneWidget);
      expect(find.textContaining('Resultado parcial'), findsOneWidget);
      expect(
        find.textContaining('Diferencia de posiciones: 0.00'),
        findsOneWidget,
      );
    },
  );
}
