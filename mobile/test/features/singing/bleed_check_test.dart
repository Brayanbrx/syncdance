import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/singing/pitch/pitch_source.dart';
import 'package:syncdance_mobile/features/singing/practice/bleed_check.dart';
import 'package:syncdance_mobile/features/singing/practice/vocal_practice.dart';

import 'pitch_reference_test.dart' show fixtureReference;

const _rate = 16000;

/// What the microphone hears: a tone like the server's guide
/// (`backend/ai_engine/voice/exercises.py` `_tone`) at [midi] for [ms],
/// scaled by [gain], then [tailMs] of room; white noise all along. As 16-bit
/// PCM, the way the phone delivers it.
List<int> microphone({
  required double midi,
  required int ms,
  required double gain,
  int tailMs = 400,
  double noise = 0.003,
}) {
  final random = math.Random(3);
  final hz = 440 * math.pow(2, (midi - 69) / 12);
  final toneSamples = ms * _rate ~/ 1000;
  final total = (ms + tailMs) * _rate ~/ 1000;
  final bytes = <int>[];
  var phase = 0.0;
  for (var i = 0; i < total; i++) {
    var value = noise * (random.nextDouble() * 2 - 1);
    if (i < toneSamples) {
      final t = i / _rate, length = toneSamples / _rate;
      final vibrato =
          1 + 0.003 * math.sin(2 * math.pi * 5.2 * t) * math.min(1, t / 0.4);
      phase += 2 * math.pi * hz * vibrato / _rate;
      final wave =
          math.sin(phase) +
          0.45 * math.sin(2 * phase) +
          0.2 * math.sin(3 * phase) +
          0.08 * math.sin(4 * phase);
      final envelope = math.min(1, t / 0.04) * math.min(1, (length - t) / 0.06);
      value += 0.22 * gain * wave * envelope;
    }
    final pcm = (value.clamp(-1.0, 1.0) * 32767).round() & 0xffff;
    bytes
      ..add(pcm & 0xff)
      ..add(pcm >> 8);
  }
  return bytes;
}

List<PitchSample> detect(List<int> pcm) => PcmPitchTracker().add(pcm);

void main() {
  final first = fixtureReference().notes.first;

  test('the guide through the speaker is caught before singing together', () {
    final samples = detect(
      microphone(midi: first.midi, ms: first.durationMs, gain: 0.1),
    );
    expect(hearsGuide(samples.map((s) => s.midi), first.midi), isTrue);

    // Without the check, a silent student would have scored it as sung in
    // tune: that is what made "¡Afinado!" appear with nobody singing.
    final practice = VocalPractice(fixtureReference(), latencyMs: 0);
    for (final sample in samples) {
      practice.onSample(sample, first.startMs + sample.timeMs);
    }
    expect(practice.resultOf(0).grade, NoteGrade.inTune);
  });

  test('headphones that leak a little are fine', () {
    final samples = detect(
      microphone(midi: first.midi, ms: first.durationMs, gain: 0.005),
    );
    expect(hearsGuide(samples.map((s) => s.midi), first.midi), isFalse);
  });

  test('a quiet room and a student humming an octave below are fine', () {
    final room = detect(microphone(midi: first.midi, ms: 0, gain: 0));
    expect(hearsGuide(room.map((s) => s.midi), first.midi), isFalse);

    final octave = detect(
      microphone(midi: first.midi - 12, ms: first.durationMs, gain: 0.3),
    );
    expect(octave.where((s) => s.midi != null), isNotEmpty);
    expect(hearsGuide(octave.map((s) => s.midi), first.midi), isFalse);
  });

  test('a few stray samples on the note are not the guide', () {
    expect(
      hearsGuide([60.1, null, null, null, null, null, null, null], 60),
      isFalse,
    );
    expect(hearsGuide(const [], 60), isFalse);
  });
}
