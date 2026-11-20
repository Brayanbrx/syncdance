import 'dart:math' as math;

import '../reference/pitch_reference.dart';

/// A part of the melody the guide sings alone and the student then repeats,
/// in "escucha y repite" and in the note drill.
class VocalTurn {
  VocalTurn({
    required this.indices,
    required this.notes,
    required this.listenFromMs,
    required this.listenToMs,
  }) {
    if (indices.isEmpty ||
        indices.length != notes.length ||
        listenToMs <= listenFromMs) {
      throw ArgumentError('invalid turn');
    }
  }

  /// Positions in the melody of the notes the student sings.
  final List<int> indices;

  /// The notes the student sings, in melody time, in order. A drill holds
  /// its note longer than the guide sang it.
  final List<SungNote> notes;

  /// The part of the guide audio played before the student's turn.
  final int listenFromMs, listenToMs;

  int get startMs => notes.first.startMs;
  int get endMs => notes.last.endMs;

  /// Which of [notes] the student should sing at [ms]; null between them.
  int? slotAt(int ms) {
    for (var i = 0; i < notes.length; i++) {
      if (ms >= notes[i].startMs && ms < notes[i].endMs) return i;
    }
    return null;
  }
}

/// Provisional values: short phrases a beginner can hold in the ear.
const phraseGapMs = 350; // a rest this long ends a phrase
const maxPhraseNotes = 5;
const maxPhraseMs = 6000;
const listenLeadMs = 500; // silence of the guide played before a phrase
const drillHoldMs = 1600; // a drilled note is held at least this long
const drillRepeats = 3;

/// The melody cut into phrases: at the rests first, then runs that are too
/// long for the ear into nearly equal parts.
List<List<int>> phrases(List<SungNote> notes) {
  final segments = <List<int>>[];
  for (var i = 0; i < notes.length; i++) {
    if (i == 0 || notes[i].startMs - notes[i - 1].endMs >= phraseGapMs) {
      segments.add([]);
    }
    segments.last.add(i);
  }
  final out = <List<int>>[];
  for (final segment in segments) {
    final length = notes[segment.last].endMs - notes[segment.first].startMs;
    final parts = math
        .max(
          (segment.length / maxPhraseNotes).ceil(),
          (length / maxPhraseMs).ceil(),
        )
        .clamp(1, segment.length);
    var from = 0;
    for (var part = 0; part < parts; part++) {
      final size = ((segment.length - from) / (parts - part)).ceil();
      out.add(segment.sublist(from, from + size));
      from += size;
    }
  }
  return out;
}

/// "Escucha y repite": one turn per phrase. The first one plays the guide
/// from its count-in, so the student hears the tempo.
List<VocalTurn> echoTurns(PitchReference reference) {
  final notes = reference.notes;
  final beat = reference.beatMs;
  return [
    for (final phrase in phrases(notes))
      VocalTurn(
        indices: phrase,
        notes: [for (final i in phrase) notes[i]],
        listenFromMs: math.max(
          phrase.first == 0 ? 0 : notes[phrase.first - 1].endMs,
          notes[phrase.first].startMs -
              (phrase.first == 0
                  ? (beat == null ? 1500 : (4 * beat).ceil())
                  : listenLeadMs),
        ),
        listenToMs: notes[phrase.last].endMs,
      ),
  ];
}

/// One note, heard and then held by the student [repeats] times.
List<VocalTurn> drillTurns(
  PitchReference reference,
  int index, {
  int repeats = drillRepeats,
}) {
  final note = reference.notes[index];
  final held = SungNote(
    note.startMs,
    note.startMs + math.max(note.durationMs, drillHoldMs),
    note.midi,
  );
  final turn = VocalTurn(
    indices: [index],
    notes: [held],
    listenFromMs: math.max(
      index == 0 ? 0 : reference.notes[index - 1].endMs,
      note.startMs - 300,
    ),
    listenToMs: note.endMs,
  );
  return List.filled(repeats, turn);
}

/// Melody time shown before the first note of a turn: a count-in on screen
/// of two beats, at least a second, so the room is quiet before measuring.
int turnLeadInMs(PitchReference reference) =>
    math.max(1000, ((reference.beatMs ?? 600) * 2).round());
