import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/singing/pitch/pitch_source.dart';
import 'package:syncdance_mobile/features/singing/pitch/yin.dart';

const rate = 16000;

double midiOf(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;

/// A voice-like tone: fundamental and harmonics, optional vibrato.
Float64List tone(
  double hz,
  int samples, {
  double vibrato = 0,
  double level = 0.25,
}) {
  final out = Float64List(samples);
  var phase = 0.0;
  for (var i = 0; i < samples; i++) {
    final t = i / rate;
    final f = hz * (1 + vibrato * math.sin(2 * math.pi * 5.5 * t));
    phase += 2 * math.pi * f / rate;
    out[i] =
        level *
        (math.sin(phase) +
            0.5 * math.sin(2 * phase) +
            0.25 * math.sin(3 * phase) +
            0.12 * math.sin(4 * phase));
  }
  return out;
}

List<int> pcm(Float64List samples) {
  final bytes = <int>[];
  for (final value in samples) {
    final v = (value.clamp(-1, 1) * 32767).round();
    bytes
      ..add(v & 0xff)
      ..add((v >> 8) & 0xff);
  }
  return bytes;
}

void main() {
  group('YIN', () {
    final detector = YinPitchDetector();

    test('hears a sung note within a few cents across the range', () {
      for (final hz in [82.4, 110.0, 196.0, 261.63, 440.0, 659.3, 987.8]) {
        final estimate = detector.detect(tone(hz, detector.frameLength))!;
        final cents = (estimate.midi - midiOf(hz)) * 100;
        expect(cents.abs(), lessThan(5), reason: '$hz Hz: $cents cents');
        expect(estimate.confidence, greaterThan(0.85));
      }
    });

    test('never answers an octave off for a rich tone', () {
      // Strong second harmonic: the classic trap for period detectors.
      final samples = Float64List(detector.frameLength);
      for (var i = 0; i < samples.length; i++) {
        final phase = 2 * math.pi * 220 * i / rate;
        samples[i] = 0.2 * math.sin(phase) + 0.25 * math.sin(2 * phase);
      }
      final estimate = detector.detect(samples)!;
      expect((estimate.midi - midiOf(220)).abs(), lessThan(0.1));
    });

    test('silence and noise have no pitch, never zero', () {
      expect(detector.detect(Float64List(detector.frameLength)), isNull);
      final random = math.Random(3);
      final noise = Float64List.fromList([
        for (var i = 0; i < detector.frameLength; i++)
          (random.nextDouble() * 2 - 1) * 0.3,
      ]);
      expect(detector.detect(noise), isNull);
    });

    test('refuses a window that is too short', () {
      expect(() => detector.detect(Float64List(100)), throwsArgumentError);
    });
  });

  group('PCM to pitch samples', () {
    test('one sample per hop, timed at the middle of its window', () {
      final tracker = PcmPitchTracker();
      final bytes = pcm(tone(440, rate)); // one second of A4
      final samples = <PitchSample>[];
      // Odd chunk sizes split 16-bit samples in two.
      for (var start = 0; start < bytes.length; start += 777) {
        samples.addAll(
          tracker.add(
            bytes.sublist(start, math.min(start + 777, bytes.length)),
          ),
        );
      }
      final window = tracker.detector.frameLength;
      expect(samples.length, (rate - window) ~/ 512 + 1);
      expect(samples.first.timeMs, (window / 2 * 1000 / rate).round());
      for (final sample in samples) {
        expect((sample.midi! - 69).abs(), lessThan(0.05));
      }
      final gaps = [
        for (var i = 1; i < samples.length; i++)
          samples[i].timeMs - samples[i - 1].timeMs,
      ];
      expect(gaps.every((gap) => gap == 32 || gap == 33), isTrue);
    });

    test('a pause in the voice is reported as no pitch', () {
      final tracker = PcmPitchTracker();
      final quiet = tracker.add(pcm(Float64List(rate ~/ 2)));
      expect(quiet, isNotEmpty);
      expect(quiet.every((s) => s.midi == null), isTrue);
    });

    test('a sample is never built from invalid numbers', () {
      expect(() => PitchSample(-1, 60, 1), throwsArgumentError);
      expect(() => PitchSample(0, double.nan, 1), throwsArgumentError);
    });
  });
}
