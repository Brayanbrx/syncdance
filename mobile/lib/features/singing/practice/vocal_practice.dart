import '../pitch/pitch_source.dart';
import '../reference/pitch_reference.dart';

/// What to tell the singer right now.
enum VocalCue { higher, lower, onPitch }

/// Live state for the screen. [cents] is the distance to the expected note in
/// the octave the student sings in: any octave is fine.
class LiveVocalState {
  const LiveVocalState({this.expected, this.sungMidi, this.cents, this.cue});
  final SungNote? expected;

  /// The student's pitch moved to the octave of [expected], for drawing.
  final double? sungMidi;
  final double? cents;
  final VocalCue? cue;
}

/// One note of the melody after the practice. [sung] false with [heard] true
/// means the microphone listened and there was no voice; [heard] false means
/// the practice stopped before it (no evidence, not an error).
class NoteResult {
  const NoteResult(
    this.note, {
    this.heard = false,
    this.sung = false,
    this.cents,
  });
  final SungNote note;
  final bool heard, sung;

  /// Centered pitch against the note; null when not sung.
  final double? cents;

  bool? inTuneWithin(double threshold) =>
      cents == null ? null : cents!.abs() <= threshold;
}

/// Scores 0-100, null without evidence.
class VocalSummary {
  const VocalSummary({
    required this.notes,
    required this.tuning,
    required this.coverage,
    required this.overall,
    required this.reachedEnd,
    required this.latencyMs,
  });

  static const version = 'vocal-summary-v1';
  final List<NoteResult> notes;

  /// Share of the sung notes in tune, weighted by length.
  final int? tuning;

  /// Share of the heard notes the student sang, weighted by length.
  final int? coverage;

  /// Tuning times coverage: a note not sung counts against the total, never
  /// against the tuning.
  final int? overall;
  final bool reachedEnd;
  final int latencyMs;

  int get outOfTune => notes
      .where((n) => n.inTuneWithin(VocalPractice.centThreshold) == false)
      .length;
}

/// Compares the student's pitch with the reference while the guide plays.
///
/// All comparisons happen at the guide position minus [latencyMs]: the time
/// the sound needs to reach the ears, the singer and the detector. Any octave
/// is accepted (a man may sing a woman's exercise an octave lower).
///
/// Provisional values, like the dance thresholds: 50 cents, the central 60 %
/// of each note, half of it sung to count. They travel with
/// `vocal-summary-v1`; the server applies the same rules
/// (`backend/ai_engine/voice/evaluate.py`).
class VocalPractice {
  VocalPractice(this.reference, {this.latencyMs = 120})
    : _buckets = [for (final _ in reference.notes) _Bucket()];

  static const centThreshold = 50.0;
  static const edgeFraction = 0.2;
  static const minSungFraction = 0.5;

  /// Samples a cue must last before it changes (~100 ms at 31 per second).
  static const cuePersistence = 3;

  final PitchReference reference;
  final int latencyMs;
  final List<_Bucket> _buckets;
  final _recent = <double>[];
  VocalCue? _cue, _candidate;
  int _candidateCount = 0, _silentSamples = 0;
  SungNote? _lastNote;

  /// [guideMs] is the guide position when the sample arrived.
  LiveVocalState onSample(PitchSample sample, int guideMs) {
    final at = guideMs - latencyMs;
    final note = reference.noteAt(at);
    if (note != _lastNote) {
      _recent.clear();
      _cue = null;
      _candidate = null;
      _lastNote = note;
    }
    if (note == null) return const LiveVocalState();

    final index = reference.notes.indexOf(note);
    final folded = sample.midi == null ? null : _fold(sample.midi!, note.midi);
    if (_inMiddle(note, at)) _buckets[index].add(folded);

    if (folded == null) {
      // A breath is fine; a long silence clears the cue.
      if (++_silentSamples > 9) _cue = null;
      return LiveVocalState(expected: note, cue: _cue);
    }
    _silentSamples = 0;
    _recent.add(folded);
    if (_recent.length > 5) _recent.removeAt(0);
    final centered = _median(_recent);
    final cents = (centered - note.midi) * 100;
    _update(
      cents.abs() <= centThreshold
          ? VocalCue.onPitch
          : cents < 0
          ? VocalCue.higher
          : VocalCue.lower,
    );
    return LiveVocalState(
      expected: note,
      sungMidi: folded,
      cents: cents,
      cue: _cue,
    );
  }

  VocalSummary finish({required bool reachedEnd}) {
    final results = <NoteResult>[
      for (var i = 0; i < reference.notes.length; i++)
        _buckets[i].result(reference.notes[i]),
    ];
    int? percent(int part, int whole) =>
        whole <= 0 ? null : (100 * part / whole).round();
    final sung = results.where((r) => r.sung);
    final heard = results.where((r) => r.heard);
    int length(Iterable<NoteResult> notes) =>
        notes.fold(0, (total, r) => total + r.note.durationMs);
    final tuning = percent(
      length(sung.where((r) => r.inTuneWithin(centThreshold) == true)),
      length(sung),
    );
    final coverage = percent(length(sung), length(heard));
    return VocalSummary(
      notes: results,
      tuning: tuning,
      coverage: coverage,
      overall: tuning == null || coverage == null
          ? null
          : (tuning * coverage / 100).round(),
      reachedEnd: reachedEnd,
      latencyMs: latencyMs,
    );
  }

  void _update(VocalCue next) {
    if (next == _cue) {
      _candidate = null;
      return;
    }
    if (next == _candidate) {
      if (++_candidateCount >= cuePersistence || _cue == null) {
        _cue = next;
        _candidate = null;
      }
    } else {
      _candidate = next;
      _candidateCount = 1;
      _cue ??= next;
    }
  }

  static bool _inMiddle(SungNote note, int at) {
    final edge = (note.durationMs * edgeFraction).floor();
    return at >= note.startMs + edge && at < note.endMs - edge;
  }

  /// The pitch moved by whole octaves to sit within half an octave of [target].
  static double _fold(double midi, double target) {
    final offset = ((midi - target + 6) % 12 + 12) % 12 - 6;
    return target + offset;
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length >> 1;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

class _Bucket {
  final _values = <double>[];
  int _samples = 0;

  void add(double? folded) {
    _samples++;
    if (folded != null) _values.add(folded);
  }

  NoteResult result(SungNote note) {
    if (_samples == 0) return NoteResult(note);
    if (_values.length < VocalPractice.minSungFraction * _samples) {
      return NoteResult(note, heard: true);
    }
    return NoteResult(
      note,
      heard: true,
      sung: true,
      cents: ((center(_values) - note.midi) * 100 * 10).round() / 10,
    );
  }
}

/// Mean without the 10 % highest and lowest: the middle of a vibrato.
/// Same rule as `pitch_center` on the server.
double center(List<double> values) {
  final sorted = [...values]..sort();
  final cut = (sorted.length * 0.1).floor();
  final kept = sorted.sublist(cut, sorted.length - cut);
  return kept.reduce((a, b) => a + b) / kept.length;
}
