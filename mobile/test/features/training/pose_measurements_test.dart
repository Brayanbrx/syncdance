import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/pose/pose_measurements.dart';
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

  test('invalid pose clears calibration and cannot leak previous angles', () {
    final processor = PoseMeasurementProcessor();
    calibrate(processor);
    final invalid = processor.process(
      at(1100, frame: modify(fixture(), (_) => null)),
    )!;
    expect(invalid.canMeasure, isFalse);
    expect(invalid.angles, isEmpty);
    expect(invalid.calibration, isNull);
    expect(processor.process(at(1200))!.canMeasure, isFalse);
    expect(calibrate(processor, start: 1300).canMeasure, isTrue);
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
