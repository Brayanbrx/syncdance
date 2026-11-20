import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/training/comparison/live_practice.dart';
import 'package:syncdance_mobile/features/training/comparison/session_summary.dart';
import 'package:syncdance_mobile/features/training/pose/body_features.dart';
import 'package:syncdance_mobile/features/training/pose/pose_frame.dart';
import 'package:syncdance_mobile/features/training/pose/pose_measurements.dart';

import '../routines/reference_test_samples.dart';
import 'pose_test_samples.dart';

final ready = PoseMeasurements(
  quality: PoseQuality.ready,
  calibrationProgress: 1,
  calibration: const FramingCalibration(0, 0.2),
  angles: const {},
);
final notReady = PoseMeasurements(
  quality: PoseQuality.bodyNotVisible,
  calibrationProgress: 0,
  calibration: null,
  angles: const {},
);

PoseFrame at(int timestampMs) {
  final source = fixture();
  return PoseFrame(
    timestampMs: timestampMs,
    imageAspectRatio: source.imageAspectRatio,
    landmarks: source.landmarks,
    poseConfidence: source.poseConfidence,
  );
}

/// Two seconds of the fixture pose at 12 Hz; [elbowOffset] makes the master
/// bend the left elbow differently so geometric feedback has a reason to fire.
MotionReference reference({double elbowOffset = 0}) {
  final features = const BodyFeatureExtractor().extract(fixture());
  final points = features.pose!.points.map(
    (j, p) => MapEntry(j, (x: p.x, y: p.y)),
  );
  final angles = {
    ...features.angles,
    BodyAngle.leftElbow: features.angles[BodyAngle.leftElbow]! + elbowOffset,
  };
  final samples = [
    for (var i = 0; i < 24; i++)
      MotionSample(
        (i * 1000 / 12).round(),
        angles,
        'SINGLE_PERSON',
        normalized: points,
      ),
  ];
  return MotionReference(
    ReferenceMetadata.fromJson({...metadataJson(), 'duration_ms': 2000}),
    samples,
    1,
  );
}

void main() {
  late int now;
  late SessionAccumulator session;
  late LivePractice practice;
  late int notifications;

  setUp(() {
    now = 0;
    session = SessionAccumulator(2000);
    practice = LivePractice(
      reference: reference(),
      session: session,
      nowMs: () => now,
    );
    notifications = 0;
    practice.addListener(() => notifications++);
  });
  tearDown(() => practice.dispose());

  /// One camera frame captured while the master plays at the same position.
  void step(int t, {bool running = true, PoseMeasurements? quality}) {
    now = t;
    practice.videoChanged(running: running, positionMs: t);
    practice.frameCaptured(
      generation: 1,
      orientation: 'portrait',
      timestampMs: t,
      running: running,
      positionMs: t,
    );
    practice.measured(at(t), quality ?? ready, running: running);
  }

  test('a capture bound to the video position is scored and recorded', () {
    step(100);
    expect(practice.match!.score, closeTo(100, 1e-9));
    expect(practice.match!.offsetMs.abs(), lessThanOrEqualTo(200));
    expect(session.evaluatedMs, 100);
    expect(notifications, greaterThan(0));
  });

  test('at the end, frames taken before it still count once measured', () {
    // Captured while playing; the pose arrives after the video ended.
    now = 1900;
    practice.videoChanged(running: true, positionMs: 1900);
    practice.frameCaptured(
      generation: 1,
      orientation: 'portrait',
      timestampMs: 1900,
      running: true,
      positionMs: 1900,
    );
    practice.videoEnded();
    // The stopped player keeps reporting: it is the end, not a pause.
    practice.videoChanged(running: false, positionMs: 2000);
    now = 2100;
    practice.frameCaptured(
      generation: 1,
      orientation: 'portrait',
      timestampMs: 2050,
      running: false,
      positionMs: 2000,
    );
    practice.measured(at(1900), ready, running: false);
    expect(session.evaluatedMs, 100);
    // Nothing captured after the end is bound, and no cue is shown.
    practice.measured(at(2050), ready, running: false);
    expect(session.evaluatedMs, 100);
    expect(practice.activeCue, isNull);
  });

  test('a paused master produces no score and no evidence', () {
    step(100, running: false);
    expect(practice.match, isNull);
    expect(session.evaluatedMs, 0);
  });

  test('insufficient pose quality is not evaluable, never a low score', () {
    step(100, quality: notReady);
    expect(practice.match, isNull);
    expect(session.evaluatedMs, 0);
  });

  test('a new camera generation drops captures bound before it', () {
    now = 100;
    practice.videoChanged(running: true, positionMs: 100);
    practice.frameCaptured(
      generation: 1,
      orientation: 'portrait',
      timestampMs: 100,
      running: true,
      positionMs: 100,
    );
    practice.frameCaptured(
      generation: 2,
      orientation: 'portrait',
      timestampMs: 150,
      running: true,
      positionMs: 100,
    );
    practice.measured(at(100), ready, running: true);
    expect(practice.match, isNull);
  });

  test('a score expires when no new measurement arrives', () async {
    step(100);
    expect(practice.match, isNotNull);
    final before = notifications;
    await Future<void>.delayed(
      LivePractice.expiry + const Duration(milliseconds: 50),
    );
    expect(practice.match, isNull);
    expect(notifications, greaterThan(before));
  });

  test('persistent deviation shows one cue and counts it in the summary', () {
    practice.rebind(reference: reference(elbowOffset: 40), session: session);
    for (var t = 0; t <= 600; t += 100) {
      step(t);
    }
    expect(practice.activeCue, isNotNull);
    expect(practice.activeCue!.code, startsWith('leftElbow_'));
    expect(practice.activeCue!.highlightedJoints, contains(Joint.leftElbow));
    final summary = session.finish(reachedVideoEnd: false);
    expect(summary.feedback.single.count, 1);
  });

  test('pausing withdraws the score and the cue immediately', () {
    practice.rebind(reference: reference(elbowOffset: 40), session: session);
    for (var t = 0; t <= 600; t += 100) {
      step(t);
    }
    expect(practice.activeCue, isNotNull);
    practice.videoChanged(running: false, positionMs: 600);
    expect(practice.match, isNull);
    expect(practice.activeCue, isNull);
  });

  test('rebinding to a new practice starts without previous guidance', () {
    practice.rebind(reference: reference(elbowOffset: 40), session: session);
    for (var t = 0; t <= 600; t += 100) {
      step(t);
    }
    final next = SessionAccumulator(2000);
    practice.rebind(reference: reference(elbowOffset: 40), session: next);
    expect(practice.activeCue, isNull);
    expect(practice.session, same(next));
    expect(next.evaluatedMs, 0);
  });

  test('events after dispose are ignored', () {
    final disposed = LivePractice(reference: reference(), nowMs: () => now)
      ..dispose();
    expect(
      () => disposed.measured(at(0), ready, running: true),
      returnsNormally,
    );
    expect(disposed.invalidate, returnsNormally);
  });
}
