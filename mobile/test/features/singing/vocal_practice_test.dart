import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/singing/pitch/pitch_source.dart';
import 'package:syncdance_mobile/features/singing/practice/playback_clock.dart';
import 'package:syncdance_mobile/features/singing/practice/vocal_practice.dart';
import 'package:syncdance_mobile/features/singing/reference/pitch_reference.dart';

import 'pitch_reference_test.dart' show fixtureReference;

/// Sings the reference: [pitchOf] gives the student's pitch for each note
/// (null = silence). One sample every 32 ms, as the phone produces them.
VocalSummary sing(
  PitchReference reference,
  double? Function(SungNote note) pitchOf, {
  int latencyMs = 0,
  int stopAtMs = 1 << 30,
  List<LiveVocalState>? live,
}) {
  final practice = VocalPractice(reference, latencyMs: latencyMs);
  for (var guide = 0; guide < reference.durationMs; guide += 32) {
    if (guide >= stopAtMs) return practice.finish(reachedEnd: false);
    final note = reference.noteAt(guide - latencyMs);
    final midi = note == null ? null : pitchOf(note);
    final state = practice.onSample(PitchSample(guide, midi, 0.9), guide);
    live?.add(state);
  }
  return practice.finish(reachedEnd: true);
}

void main() {
  final reference = fixtureReference();

  test('singing the melody scores full marks', () {
    final summary = sing(reference, (note) => note.midi);
    expect(summary.tuning, 100);
    expect(summary.coverage, 100);
    expect(summary.overall, 100);
    expect(summary.outOfTune, 0);
    expect(summary.notes.every((n) => n.sung && n.cents == 0), isTrue);
  });

  test('any octave is fine', () {
    expect(sing(reference, (note) => note.midi - 12).tuning, 100);
    expect(sing(reference, (note) => note.midi + 12).tuning, 100);
  });

  test('a wrong note is found and its direction told', () {
    final summary = sing(
      reference,
      (note) => note.midi == 64 ? 65.0 : note.midi, // E sung as F
    );
    final wrong = summary.notes.where((n) => n.inTuneWithin(50) == false);
    expect(wrong.map((n) => n.note.name), ['E4', 'E4']);
    expect(wrong.first.cents, 100);
    expect(summary.tuning, lessThan(100));
    expect(summary.coverage, 100);
  });

  test('a note not sung lowers the coverage, never the tuning', () {
    final summary = sing(
      reference,
      (note) => note.midi == 72 ? null : note.midi, // skips the top C
    );
    expect(summary.tuning, 100);
    expect(summary.coverage, lessThan(100));
    expect(summary.overall, summary.coverage);
    final top = summary.notes.firstWhere((n) => n.note.midi == 72);
    expect((top.heard, top.sung, top.cents), (true, false, null));
  });

  test('stopping early leaves the rest without evidence, not wrong', () {
    final third = reference.notes[2];
    final summary = sing(reference, (n) => n.midi, stopAtMs: third.startMs);
    expect(summary.reachedEnd, isFalse);
    expect(summary.notes.where((n) => n.heard).length, 2);
    expect(summary.tuning, 100);
    expect(summary.coverage, 100);
  });

  test('silence all along gives no score at all', () {
    final summary = sing(reference, (_) => null);
    expect(summary.tuning, isNull);
    expect(summary.overall, isNull);
    expect(summary.coverage, 0);
  });

  test('the latency is taken off before comparing', () {
    // The singer hears the guide 300 ms late and sings it 300 ms late.
    final summary = sing(reference, (n) => n.midi, latencyMs: 300);
    expect(summary.tuning, 100);
    expect(summary.latencyMs, 300);
  });

  test('the live cue says which way to go and does not flicker', () {
    final live = <LiveVocalState>[];
    sing(reference, (note) => note.midi - 1, live: live); // a semitone low
    final cues = live.map((s) => s.cue).whereType<VocalCue>().toSet();
    expect(cues, {VocalCue.higher});
    final cents = live.map((s) => s.cents).whereType<double>();
    expect(cents.every((c) => c == -100), isTrue);

    // Mostly in tune with one stray sample: the cue does not jump to it.
    final steady = VocalPractice(reference, latencyMs: 0);
    final note = reference.notes.first;
    final seen = <VocalCue?>[];
    for (var t = note.startMs, i = 0; t < note.endMs; t += 32, i++) {
      final midi = i == 5 ? note.midi + 1 : note.midi;
      seen.add(steady.onSample(PitchSample(t, midi, 0.9), t).cue);
    }
    expect(seen.whereType<VocalCue>().toSet(), {VocalCue.onPitch});
  });

  test('the playback clock runs between coarse reports', () {
    final clock = PlaybackClock();
    expect(clock.positionAt(0), isNull);
    clock.report(positionMs: 1000, nowMs: 5000, playing: true);
    expect(clock.positionAt(5250), 1250);
    clock.report(positionMs: 1000, nowMs: 5400, playing: true); // same value
    expect(clock.positionAt(5450), 1450);
    clock.report(positionMs: 1500, nowMs: 5500, playing: true);
    expect(clock.positionAt(5600), 1600);
    expect(clock.positionAt(9000), 1500); // stuck player: do not run ahead
    clock.report(positionMs: 1500, nowMs: 5600, playing: false);
    expect(clock.positionAt(6000), 1500);
  });
}
