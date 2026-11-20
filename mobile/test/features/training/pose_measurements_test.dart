import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/pose/pose_measurements.dart';
import 'package:syncdance_mobile/features/training/presentation/game_widgets.dart';
import 'package:syncdance_mobile/features/training/presentation/pose_measurements_panel.dart';
import 'pose_test_samples.dart';

PoseFrame at(int time, {PoseFrame? frame}) {
  final p = frame ?? fixture();
  return PoseFrame(
    timestampMs: time,
    imageAspectRatio: p.imageAspectRatio,
    landmarks: p.landmarks,
    poseConfidence: p.poseConfidence,
  );
}

PoseMeasurements calibrate(
  PoseMeasurementProcessor processor, {
  int start = 0,
}) {
  PoseMeasurements? result;
  for (var t = start; t <= start + 1000; t += 100) {
    result = processor.process(at(t));
  }
  return result!;
}

void main() {
  const gate = PoseQualityGate();
  test('gate requires complete reliable body, not mean confidence', () {
    expect(gate.evaluate(fixture()), PoseQuality.ready);
    expect(gate.evaluate(modify(fixture(), (_) => null)), PoseQuality.noPerson);
    expect(
      gate.evaluate(
        modify(fixture(), (p) => p.joint == Joint.leftAnkle ? null : p),
      ),
      PoseQuality.bodyNotVisible,
    );
    final weak = modify(
      fixture(),
      (p) => p.joint == Joint.leftWrist
          ? PoseLandmark(joint: p.joint, x: p.x, y: p.y, confidence: 0.59)
          : p,
    );
    expect(gate.evaluate(weak), PoseQuality.lowConfidence);
  });

  test('gate separates clipped, edge and small framing', () {
    PoseFrame wrist(double x) => modify(
      fixture(),
      (p) => p.joint == Joint.leftWrist
          ? PoseLandmark(joint: p.joint, x: x, y: p.y, confidence: 1)
          : p,
    );
    expect(gate.evaluate(wrist(-0.1)), PoseQuality.bodyNotVisible);
    expect(gate.evaluate(wrist(0.01)), PoseQuality.tooClose);
    // Standing too close: ML Kit guesses off-screen knees with low confidence.
    // That is a framing problem, never reported as poor lighting.
    final close = modify(
      fixture(),
      (p) => p.joint == Joint.leftKnee || p.joint == Joint.rightKnee
          ? PoseLandmark(joint: p.joint, x: p.x, y: 1.3, confidence: 0.1)
          : p,
    );
    expect(gate.evaluate(close), PoseQuality.bodyNotVisible);
    final small = modify(
      fixture(),
      (p) => PoseLandmark(
        joint: p.joint,
        x: 0.5 + (p.x - 0.5) * 0.3,
        y: 0.5 + (p.y - 0.5) * 0.3,
        confidence: 1,
      ),
    );
    expect(gate.evaluate(small), PoseQuality.tooFar);
  });

  test('collapsed geometry is not ready despite high confidence', () {
    final collapsed = modify(
      fixture(),
      (p) => p.joint == Joint.leftWrist
          ? PoseLandmark(joint: p.joint, x: 0.1, y: 0.3, confidence: 1)
          : p,
    );
    expect(gate.evaluate(collapsed), PoseQuality.lowConfidence);
  });

  test(
    'calibration needs elapsed time and enough consecutive stable samples',
    () {
      final processor = PoseMeasurementProcessor();
      expect(processor.process(at(0))!.angles, isEmpty);
      for (var t = 1; t < 9; t++) {
        expect(processor.process(at(t))!.canMeasure, isFalse);
      }
      processor.reset();
      for (final t in [0, 400, 800, 1000]) {
        expect(processor.process(at(t))!.canMeasure, isFalse);
      }
      processor.reset();
      final calibrated = calibrate(processor);
      expect(calibrated.canMeasure, isTrue);
      expect(calibrated.angles.length, 6);
      expect(calibrated.calibration!.torsoScale, closeTo(0.25, 1e-9));
      expect(() => calibrated.angles.clear(), throwsUnsupportedError);
    },
  );

  test(
    'movement restarts calibration window and duplicate time is ignored',
    () {
      final processor = PoseMeasurementProcessor();
      for (var t = 0; t <= 900; t += 100) {
        processor.process(at(t));
      }
      expect(processor.process(at(900)), isNull);
      expect(processor.process(at(500)), isNull);
      final moved = modify(
        fixture(),
        (p) =>
            PoseLandmark(joint: p.joint, x: p.x + 0.05, y: p.y, confidence: 1),
      );
      final result = processor.process(at(1000, frame: moved))!;
      expect(result.canMeasure, isFalse);
      expect(result.calibrationProgress, 0);
    },
  );

  /// The fixture at 70 % of its size: same pose, the learner farther away.
  PoseFrame farther() => modify(
    fixture(),
    (p) => PoseLandmark(
      joint: p.joint,
      x: 0.5 + (p.x - 0.5) * 0.7,
      y: 0.5 + (p.y - 0.5) * 0.7,
      confidence: p.confidence,
    ),
  );
  final empty = modify(fixture(), (_) => null);

  test('a short unmeasurable stretch keeps the framing, never the angles', () {
    final processor = PoseMeasurementProcessor();
    calibrate(processor);
    final invalid = processor.process(at(1100, frame: empty))!;
    expect(invalid.canMeasure, isFalse);
    expect(invalid.angles, isEmpty);
    expect(invalid.calibration, isNotNull);
    // Back in the picture at the same distance: measured at once, with no
    // need to stand still again in the middle of a dance.
    final back = processor.process(at(1200))!;
    expect(back.canMeasure, isTrue);
    expect(back.angles.length, 6);
  });

  test('a long stretch or another distance asks for a new calibration', () {
    final processor = PoseMeasurementProcessor();
    calibrate(processor); // last ready frame at 1000 ms
    PoseMeasurements? last;
    var t = 1000;
    while (t - 1000 <= PoseMeasurementProcessor.graceMs) {
      t += 400; // under the 500 ms gap that resets everything
      last = processor.process(at(t, frame: empty));
    }
    expect(last!.calibration, isNull);
    expect(processor.process(at(t + 100))!.canMeasure, isFalse);
    expect(calibrate(processor, start: t + 200).canMeasure, isTrue);

    final moved = PoseMeasurementProcessor();
    calibrate(moved);
    moved.process(at(1100, frame: empty));
    final away = moved.process(at(1200, frame: farther()))!;
    expect(away.canMeasure, isFalse);
    expect(away.calibrationProgress, lessThan(1));
  });

  test('positioning asks to step back when raised hands would not fit', () {
    PoseMeasurements ready({required bool room}) => PoseMeasurements(
      quality: PoseQuality.ready,
      calibrationProgress: 0.5,
      calibration: null,
      angles: const {},
      roomForArms: room,
    );
    expect(
      positioningGuidance(ready(room: false), null),
      contains(armsRoomHint),
    );
    expect(
      positioningGuidance(ready(room: true), null),
      isNot(contains(armsRoomHint)),
    );
  });

  test('framing guidance tells when raised hands would not fit', () {
    // The fixture fills the picture from the nose (0.10) to the feet (0.95).
    expect(PoseMeasurementProcessor().process(at(0))!.roomForArms, isFalse);
    expect(
      PoseMeasurementProcessor().process(at(0, frame: farther()))!.roomForArms,
      isTrue,
    );
    // Guidance only: the full-size fixture still calibrates.
    expect(calibrate(PoseMeasurementProcessor()).canMeasure, isTrue);
  });

  test('gap, explicit reset and changed aspect demand new calibration', () {
    final processor = PoseMeasurementProcessor();
    calibrate(processor);
    expect(processor.process(at(1600))!.canMeasure, isFalse);
    processor.reset();
    calibrate(processor);
    final changed = modify(fixture(), (p) => p, aspect: 4 / 3);
    expect(processor.process(at(1100, frame: changed))!.canMeasure, isFalse);
    processor.reset();
    expect(processor.process(at(0))!.calibrationProgress, 0);
  });

  test(
    'EMA reduces jumps and is invariant to interval partition for constant input',
    () {
      final whole = AngleSmoother();
      final split = AngleSmoother();
      whole.update(0, {BodyAngle.leftElbow: 0});
      split.update(0, {BodyAngle.leftElbow: 0});
      final expected = whole.update(200, {BodyAngle.leftElbow: 90});
      split.update(100, {BodyAngle.leftElbow: 90});
      final actual = split.update(200, {BodyAngle.leftElbow: 90});
      expect(
        actual[BodyAngle.leftElbow],
        closeTo(90 * (1 - math.exp(-200 / 150)), 1e-9),
      );
      expect(
        actual[BodyAngle.leftElbow],
        closeTo(expected[BodyAngle.leftElbow]!, 1e-9),
      );
      expect(actual[BodyAngle.leftElbow], inExclusiveRange(0, 90));
    },
  );

  test('smoother never fills missing data and resets after gaps', () {
    final smoother = AngleSmoother();
    smoother.update(0, {BodyAngle.leftElbow: 90});
    expect(smoother.update(100, {}), isEmpty);
    expect(
      smoother.update(200, {BodyAngle.leftElbow: 0})[BodyAngle.leftElbow],
      0,
    );
    expect(
      smoother.update(150, {BodyAngle.leftElbow: 90})[BodyAngle.leftElbow],
      0,
    );
    expect(
      smoother.update(1000, {BodyAngle.leftElbow: 180})[BodyAngle.leftElbow],
      180,
    );
    expect(smoother.update(1100, {BodyAngle.leftElbow: double.nan}), isEmpty);
    smoother.reset();
    expect(
      smoother.update(0, {BodyAngle.leftElbow: 90})[BodyAngle.leftElbow],
      90,
    );
  });

  testWidgets(
    'panel shows framing guidance, calibration progress and recalibration',
    (tester) async {
      final processor = PoseMeasurementProcessor();
      var recalibrated = false;
      Future<void> show(PoseMeasurements result) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PoseMeasurementsPanel(
              measurements: result,
              onRecalibrate: () {
                recalibrated = true;
              },
            ),
          ),
        ),
      );
      await show(processor.process(at(0))!);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Codos:'), findsNothing);
      processor.reset();
      await show(calibrate(processor));
      expect(find.textContaining('Codos:'), findsOneWidget);
      await tester.tap(find.text('Recalibrar encuadre'));
      expect(recalibrated, isTrue);
      await show(
        processor.process(at(1100, frame: modify(fixture(), (_) => null)))!,
      );
      expect(find.text('Colócate frente a la cámara.'), findsOneWidget);
      expect(find.textContaining('Codos:'), findsNothing);
    },
  );
}
