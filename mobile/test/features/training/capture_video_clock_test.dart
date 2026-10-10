import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/comparison/capture_video_clock.dart';

void main() {
  test(
    'inference completion uses capture position and can only consume it once',
    () {
      final clock = CaptureVideoClock();
      clock.report(videoMs: 1000, nowMs: 0, playing: true);
      clock.capture(timestampMs: 800, nowMs: 20);
      clock.report(videoMs: 1100, nowMs: 100, playing: true);
      expect(clock.resolve(timestampMs: 800, nowMs: 180), 1000);
      expect(clock.resolve(timestampMs: 800, nowMs: 180), isNull);
    },
  );
  test('pause, explicit seek and discontinuity discard in-flight results', () {
    for (final reset in <void Function(CaptureVideoClock)>[
      (c) => c.report(videoMs: 1000, nowMs: 30, playing: false),
      (c) => c.invalidate(),
      (c) => c.report(videoMs: 900, nowMs: 30, playing: true),
      (c) => c.report(videoMs: 2000, nowMs: 30, playing: true),
    ]) {
      final clock = CaptureVideoClock();
      clock.report(videoMs: 1000, nowMs: 0, playing: true);
      clock.capture(timestampMs: 10, nowMs: 20);
      reset(clock);
      expect(clock.resolve(timestampMs: 10, nowMs: 40), isNull);
    }
  });
  test(
    'stalled video, slow inference and unrecorded frames cannot be scored',
    () {
      final clock = CaptureVideoClock();
      clock.report(videoMs: 0, nowMs: 0, playing: true);
      clock.capture(timestampMs: 10, nowMs: 10);
      clock.report(videoMs: 0, nowMs: 260, playing: true);
      expect(clock.resolve(timestampMs: 10, nowMs: 260), isNull);
      clock.capture(timestampMs: 20, nowMs: 270);
      clock.report(videoMs: 100, nowMs: 300, playing: true);
      expect(clock.resolve(timestampMs: 20, nowMs: 301), isNull);
      clock.capture(timestampMs: 30, nowMs: 310);
      clock.report(videoMs: 500, nowMs: 800, playing: true);
      expect(clock.resolve(timestampMs: 30, nowMs: 811), isNull);
      expect(clock.resolve(timestampMs: 99, nowMs: 811), isNull);
    },
  );
  test('pending capture records are bounded', () {
    final clock = CaptureVideoClock();
    clock.report(videoMs: 100, nowMs: 0, playing: true);
    for (var t = 0; t < 65; t++) {
      clock.capture(timestampMs: t, nowMs: t);
    }
    expect(clock.resolve(timestampMs: 0, nowMs: 70), isNull);
    expect(clock.resolve(timestampMs: 64, nowMs: 70), 100);
  });
}
