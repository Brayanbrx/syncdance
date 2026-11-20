import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/singing/pitch/pitch_source.dart';
import 'package:syncdance_mobile/features/singing/practice/playback_clock.dart';
import 'package:syncdance_mobile/features/singing/practice/vocal_practice.dart';
import 'package:syncdance_mobile/features/singing/practice/vocal_turns.dart';
import 'package:syncdance_mobile/features/singing/reference/pitch_reference.dart';

import 'pitch_reference_test.dart' show fixtureReference;

/// Sings the reference: [pitchOf] gives the student's pitch for each note
/// (null = silence). One sample every 32 ms, as the phone produces them.
VocalSummary sing(
  PitchReference reference,
  double? Function(SungNote note) pitchOf, {
  int latencyMs = 0,
  double speed = 1.0,
  int stopAtMs = 1 << 30,
  List<LiveVocalState>? live,
}) {
  final practice = VocalPractice(reference, latencyMs: latencyMs, speed: speed);
  for (var guide = 0; guide < reference.durationMs; guide += 32) {
    if (guide >= stopAtMs) return practice.finish(reachedEnd: false);
    final note = reference.noteAt(guide - practice.lagMs);
    final midi = note == null ? null : pitchOf(note);
    final state = practice.onSample(PitchSample(guide, midi, 0.9), guide);
    live?.add(state);
  }
  return practice.finish(reachedEnd: true);
}

/// The cues on screen while holding a note at [cents] after [samples].
List<VocalCue?> holdCues(PitchReference reference, List<double> cents) {
  final practice = VocalPractice(reference, latencyMs: 0);
  final note = reference.notes.last; // the long final note
  return [
    for (var i = 0; i < cents.length; i++)
      practice
          .onSample(
            PitchSample(i * 32, note.midi + cents[i] / 100, 0.9),
            note.startMs + i * 32,
          )
          .cue,
  ];
}

void main() {
  final reference = fixtureReference();

  test('singing the melody scores full marks', () {
    final summary = sing(reference, (note) => note.midi);
    expect(summary.tuning, 100);
    expect(summary.coverage, 100);
    expect(summary.overall, 100);
    expect(summary.outOfTune, 0);
    expect(summary.inTune, reference.notes.length);
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
    final wrong = summary.notes.where((n) => n.grade == NoteGrade.off);
    expect(wrong.map((n) => n.note.name), ['E4', 'E4']);
    expect(wrong.first.cents, 100);
    expect(summary.tuning, lessThan(100));
    expect(summary.coverage, 100);
  });

  test('in tune within 25 cents; up to 50 is close and counts half', () {
    final near = sing(reference, (note) => note.midi - 0.2);
    expect(near.tuning, 100);
    expect(near.inTune, reference.notes.length);

    final close = sing(reference, (note) => note.midi - 0.35);
    expect(close.tuning, 50);
    expect(close.close, reference.notes.length);
    expect(close.outOfTune, 0);
    expect(close.notes.first.grade, NoteGrade.close);

    expect(gradeOf(25), NoteGrade.inTune);
    expect(gradeOf(-25.1), NoteGrade.close);
    expect(gradeOf(50), NoteGrade.close);
    expect(gradeOf(50.1), NoteGrade.off);
  });

  test('a note not sung lowers the coverage, never the tuning', () {
    final summary = sing(
      reference,
      (note) => note.midi == 72 ? null : note.midi, // skips the top C
    );
    expect(summary.tuning, 100);
    expect(summary.coverage, lessThan(100));
    expect(summary.overall, summary.coverage);
    expect(summary.missed, 1);
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

  test('a slower guide shortens the latency in melody time', () {
    final practice = VocalPractice(reference, latencyMs: 120, speed: 0.5);
    expect(practice.lagMs, 60);
    final summary = sing(reference, (n) => n.midi, latencyMs: 300, speed: 0.5);
    expect(summary.tuning, 100);
    expect(summary.speed, 0.5);
  });

  group('live cue', () {
    test('says which way to go and how far', () {
      final live = <LiveVocalState>[];
      sing(reference, (note) => note.midi - 1, live: live); // a semitone low
      expect(live.map((s) => s.cue).whereType<VocalCue>().toSet(), {
        VocalCue.higher,
      });
      final cents = live.map((s) => s.cents).whereType<double>();
      expect(cents.every((c) => c == -100), isTrue);

      final slightly = <LiveVocalState>[];
      sing(reference, (note) => note.midi + 0.35, live: slightly);
      expect(slightly.map((s) => s.cue).whereType<VocalCue>().toSet(), {
        VocalCue.slightlyLower,
      });
    });

    test('waits a moment before the first cue of a note', () {
      final cues = holdCues(reference, List.filled(6, 0));
      expect(
        cues.take(VocalPractice.firstCuePersistence - 1),
        everyElement(isNull),
      );
      expect(cues.last, VocalCue.onPitch);
    });

    test('ignores a stray sample and a voice right at a border', () {
      // In tune, one stray sample a semitone up.
      final stray = holdCues(reference, [
        for (var i = 0; i < 30; i++) i == 12 ? 100.0 : 0.0,
      ]);
      expect(stray.whereType<VocalCue>().toSet(), {VocalCue.onPitch});

      // Wobbling around 25 cents: it stays "in tune" instead of flickering.
      final border = holdCues(reference, [
        for (var i = 0; i < 40; i++) i.isEven ? 22.0 : 30.0,
      ]);
      expect(border.whereType<VocalCue>().toSet(), {VocalCue.onPitch});
    });

    test('changes once the voice clearly moved, after a quarter second', () {
      final cues = holdCues(reference, [
        ...List.filled(10, 0.0),
        ...List.filled(20, -80.0),
      ]);
      expect(cues[9], VocalCue.onPitch);
      // The median takes 3 samples to move, then the cue needs 8 more.
      expect(cues[10 + 2 + VocalPractice.cuePersistence - 2], VocalCue.onPitch);
      expect(cues.last, VocalCue.higher);
    });
  });

  group('turns', () {
    test('the melody is cut into short phrases', () {
      // The arpeggio has no rests: seven notes become four and three.
      expect(phrases(reference.notes), [
        [0, 1, 2, 3],
        [4, 5, 6],
      ]);
      SungNote note(int start, int length) =>
          SungNote(start, start + length, 60);
      // A rest ends a phrase; a long run is split in nearly equal parts.
      expect(
        phrases([
          note(0, 500),
          note(600, 500), // 100 ms breath: same phrase
          note(1500, 500), // 400 ms rest: a new phrase
          for (var i = 0; i < 7; i++) note(2060 + i * 560, 500),
        ]),
        [
          [0, 1],
          [2, 3, 4, 5],
          [6, 7, 8, 9],
        ],
      );
    });

    test('echo turns play the count-in first, then only the gap', () {
      final turns = echoTurns(reference);
      final notes = reference.notes;
      expect(turns.length, 2);
      expect(turns.first.listenFromMs, 0);
      expect(turns.first.listenToMs, notes[3].endMs);
      expect(turns.last.listenFromMs, notes[3].endMs); // never the last note
      expect(turns.last.listenToMs, notes.last.endMs);
      expect(turns.last.slotAt(notes[5].startMs), 1);
      expect(turns.last.slotAt(notes[5].endMs), isNull);
    });

    test('a drill holds the note longer, three times', () {
      final turns = drillTurns(reference, 1);
      expect(turns.length, drillRepeats);
      final note = reference.notes[1];
      expect(turns.first.indices, [1]);
      expect(turns.first.notes.single.durationMs, drillHoldMs);
      expect(turns.first.notes.single.midi, note.midi);
      expect(turns.first.listenToMs, note.endMs);
      expect(turns.first.listenFromMs, reference.notes[0].endMs);
    });

    test('a turn scores only its notes and a repeat starts over', () {
      final turn = echoTurns(reference).last;
      final practice = VocalPractice(reference, latencyMs: 0);
      void singTurn(double? Function(SungNote note) pitchOf) {
        for (var t = turn.startMs - 1000; t < turn.endMs + 400; t += 32) {
          final slot = turn.slotAt(t);
          final midi = slot == null ? null : pitchOf(turn.notes[slot]);
          // Before the first note the voice is ignored, whatever it sings.
          practice.onTurnSample(PitchSample(t, midi ?? 70, 0.9), t, turn);
        }
      }

      singTurn((note) => note.midi - 1);
      expect(practice.resultOf(turn.indices.first).grade, NoteGrade.off);
      practice.restart(turn);
      singTurn((note) => note.midi);
      final summary = practice.finish(reachedEnd: true);
      for (final index in turn.indices) {
        expect(summary.notes[index].grade, NoteGrade.inTune);
      }
      // The first phrase was never sung: no evidence, not wrong.
      expect(summary.notes.first.heard, isFalse);
      expect(summary.tuning, 100);
    });
  });

  group('playback clock', () {
    test('runs between coarse reports', () {
      final clock = PlaybackClock();
      expect(clock.positionAt(0), isNull);
      clock.report(positionMs: 1000, nowMs: 5000, playing: true);
      expect(clock.positionAt(5250), 1250);
      clock.report(positionMs: 1000, nowMs: 5400, playing: true); // same
      expect(clock.positionAt(5450), 1450);
      clock.report(positionMs: 1500, nowMs: 5500, playing: true);
      expect(clock.positionAt(5600), 1600);
      expect(clock.positionAt(9000), 1500); // stuck player: do not run ahead
      clock.report(positionMs: 1500, nowMs: 5600, playing: false);
      expect(clock.positionAt(6000), 1500);
    });

    test('counts from when it starts playing, at its speed', () {
      final clock = PlaybackClock()..speed = 0.5;
      clock.report(positionMs: 3000, nowMs: 100, playing: false); // sought
      clock.report(positionMs: 3000, nowMs: 900, playing: true); // plays
      expect(clock.positionAt(1100), 3100);
    });
  });
}
