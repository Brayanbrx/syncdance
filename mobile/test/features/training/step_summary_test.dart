import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/comparison/pose_matcher.dart';
import 'package:syncdance_mobile/features/training/comparison/session_summary.dart';
import 'package:syncdance_mobile/features/training/history/calibration_log.dart';
import 'package:syncdance_mobile/features/training/history/saved_session.dart';

import '../routines/reference_test_samples.dart';
import 'feedback_test.dart' show cue;
import 'session_store_test.dart' show savedPractice, stepsMetadata;

void main() {
  group('step summary (step-summary-v1)', () {
    test('each step takes the evidence of the bins it overlaps', () {
      final steps = stepsMetadata().steps; // [0, 125) and [125, 250)
      final accumulator = SessionAccumulator(250, steps: steps);
      const first = PoseMatch(10, 0.1, 0);
      const second = PoseMatch(40, 0.4, 0);
      accumulator
        ..record(0, first) // bin [0, 100)
        ..record(150, second) // bin [100, 200): 25 ms in step 1, 75 in step 2
        ..recordFeedback(0, cue('leftElbow_extend'))
        ..recordFeedback(150, cue('leftElbow_extend'));

      final summary = accumulator.finish(reachedVideoEnd: true);

      expect(summary.stepsVersion, 'step-summary-v1');
      final (one, two) = (summary.steps[0], summary.steps[1]);
      expect(one.evaluatedMs, 125);
      expect(
        one.score,
        closeTo((first.score * 100 + second.score * 25) / 125, 1e-9),
      );
      expect(two.evaluatedMs, 75);
      expect(two.score, closeTo(second.score, 1e-9));
      expect(one.feedback, {'leftElbow_extend': 1});
      expect(two.feedback, {'leftElbow_extend': 1});
      // Never more evidence in the steps than in the practice.
      expect(one.evaluatedMs + two.evaluatedMs, summary.evaluatedMs);
    });

    test('a step without evidence has no score, never zero', () {
      final accumulator = SessionAccumulator(250, steps: stepsMetadata().steps)
        ..record(0, const PoseMatch(10, 0.1, 0));
      final summary = accumulator.finish(reachedVideoEnd: false);
      expect(summary.steps[1].evaluatedMs, 0);
      expect(summary.steps[1].score, isNull);
    });

    test('without steps nothing is summarized or sent', () {
      final summary = SessionAccumulator(250).finish(reachedVideoEnd: false);
      expect(summary.steps, isEmpty);
      expect(summary.stepsVersion, isNull);
      final upload = savedPractice().toUpload();
      expect(upload.containsKey('step_results'), isFalse);
      expect(upload.containsKey('calibration'), isFalse);
    });
  });

  group('local-session-v3', () {
    Map<String, dynamic> json(SavedSession record) =>
        jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>;

    test('steps and calibration round trip; v2 files still read', () {
      final record = savedPractice(
        withSteps: true,
        calibration: const CalibrationCount(3, 2),
      );
      final copy = SavedSession.fromJson(json(record));
      expect(copy.toJson(), record.toJson());
      expect(copy.summary.steps, hasLength(2));
      expect(copy.calibration!.attempts, 3);

      final v2 = json(savedPractice())..['schema'] = 'local-session-v2';
      expect(SavedSession.fromJson(v2).summary.steps, isEmpty);
    });

    test('steps that are not the published ones are refused', () {
      final record = savedPractice(withSteps: true);
      void refused(void Function(Map<String, dynamic> data) spoil) {
        final data = json(record);
        spoil(data);
        expect(() => SavedSession.fromJson(data), throwsFormatException);
      }

      Map<String, dynamic> step(Map<String, dynamic> data, int index) =>
          ((data['summary'] as Map)['steps'] as List)[index]
              as Map<String, dynamic>;
      refused((d) => step(d, 1)['start_ms'] = 100);
      refused((d) => ((d['summary'] as Map)['steps'] as List).removeLast());
      refused((d) => step(d, 0)['feedback'] = {'rightKnee_bend': 1});
      refused((d) => step(d, 0)['feedback'] = {'leftElbow_extend': 9});
      refused((d) => step(d, 1)['evaluated_ms'] = 0);
      refused((d) => d['schema'] = 'local-session-v2');
      refused((d) => d['calibration'] = {'attempts': 1, 'calibrated': 2});
    });
  });

  group('calibration log', () {
    late Directory root;
    late CalibrationLog log;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('calibration-test-');
      log = CalibrationLog(File('${root.path}/scope/calibration.json'));
    });
    tearDown(() => root.delete(recursive: true));

    test('tries add up and a saved practice takes only its own', () async {
      expect((await log.pending()).isEmpty, isTrue);
      await log.record(calibrated: true);
      await log.record(calibrated: false);
      await log.record(calibrated: true);
      final sent = await log.pending();
      expect((sent.attempts, sent.calibrated), (3, 2));
      await log.record(calibrated: false); // after the practice was built
      await log.clear(sent);
      final left = await log.pending();
      expect((left.attempts, left.calibrated), (1, 0));
      await log.clear(left);
      expect(await log.file.exists(), isFalse);
    });

    test('a damaged log counts as empty and never throws', () async {
      await log.file.parent.create(recursive: true);
      await log.file.writeAsString('{"attempts": -1}');
      expect((await log.pending()).isEmpty, isTrue);
      await log.record(calibrated: true);
      expect((await log.pending()).attempts, 1);
    });

    test('an attempt closes once', () {
      final closed = <bool>[];
      final attempt = CalibrationAttempt(closed.add)
        ..start()
        ..calibrated()
        ..abandoned();
      expect(closed, [true]);
      attempt
        ..start()
        ..abandoned()
        ..calibrated();
      expect(closed, [true, false]);
      CalibrationAttempt(closed.add).abandoned(); // never started
      expect(closed, [true, false]);
    });
  });

  test('metadata helper keeps the fixture duration', () {
    expect(stepsMetadata().durationMs, metadata().durationMs);
  });
}
