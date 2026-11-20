import '../pitch/pitch_source.dart';
import '../reference/pitch_reference.dart';
import 'vocal_turns.dart';

/// What to tell the singer right now: which way to move and how far.
enum VocalCue { higher, slightlyHigher, onPitch, slightlyLower, lower }

/// How close a sung note was to the melody.
enum NoteGrade { inTune, close, off }

/// How the student sings the exercise.
enum PracticeMode {
  /// The guide sings a phrase and stops; then the student repeats it. The
  /// microphone only counts while the guide is silent, so it works without
  /// headphones too.
  echo('echo'),

  /// Together with the guide, like karaoke: only with headphones, or the
  /// microphone hears the guide and takes it for the student.
  together('together'),

  /// One note again and again, held longer; never kept in the history.
  drill('drill');

  const PracticeMode(this.code);
  final String code;

  static PracticeMode? parse(Object? code) =>
      values.where((mode) => mode.code == code).firstOrNull;
}

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

  NoteGrade? get grade => cents == null ? null : gradeOf(cents!);
}

/// In tune up to 25 cents, close up to 50 (the nearest note is right, but it
/// is heard off), off beyond.
NoteGrade gradeOf(double cents) => cents.abs() <= VocalPractice.inTuneCents
    ? NoteGrade.inTune
    : cents.abs() <= VocalPractice.closeCents
    ? NoteGrade.close
    : NoteGrade.off;

/// Scores 0-100, null without evidence.
class VocalSummary {
  const VocalSummary({
    required this.notes,
    required this.tuning,
    required this.coverage,
    required this.overall,
    required this.reachedEnd,
    required this.latencyMs,
    this.mode = PracticeMode.together,
    this.speed = 1.0,
  });

  /// v2: a close note counts half; v1 counted everything within 50 cents.
  static const version = 'vocal-summary-v2';
  final List<NoteResult> notes;

  /// Sung notes weighted by length: in tune counts whole, close counts half.
  final int? tuning;

  /// Share of the heard notes the student sang, weighted by length.
  final int? coverage;

  /// Tuning times coverage: a note not sung counts against the total, never
  /// against the tuning.
  final int? overall;
  final bool reachedEnd;
  final int latencyMs;
  final PracticeMode mode;
  final double speed;

  int _count(NoteGrade grade) => notes.where((n) => n.grade == grade).length;
  int get inTune => _count(NoteGrade.inTune);
  int get close => _count(NoteGrade.close);
  int get outOfTune => _count(NoteGrade.off);

  /// Heard and silent: the student did not sing them.
  int get missed => notes.where((n) => n.heard && !n.sung).length;
}

/// Compares the student's pitch with the melody.
///
/// Together with the guide, every comparison happens at the guide position
/// minus [latencyMs]: the time the sound needs to reach the ears, the singer
/// and the detector. In an echo or drill turn the student follows the screen,
/// so only the microphone's delay counts. Any octave is accepted (a man may
/// sing a woman's exercise an octave lower).
///
/// Provisional values, like the dance thresholds: in tune within 25 cents,
/// close within 50, the central 60 % of each note, half of it sung to count.
/// They travel with `vocal-summary-v2`. The per-note rules are the server's
/// (`backend/ai_engine/voice/evaluate.py`); its report (`voice-score-v1`)
/// still counts a note within 50 cents as fully in tune.
class VocalPractice {
  VocalPractice(
    this.reference, {
    this.latencyMs = 120,
    this.speed = 1.0,
    this.mode = PracticeMode.together,
  }) : _buckets = [for (final _ in reference.notes) _Bucket()];

  static const inTuneCents = 25.0;
  static const closeCents = 50.0;
  static const edgeFraction = 0.2;
  static const minSungFraction = 0.5;

  /// Samples a cue must last before it replaces another (~250 ms at 31 per
  /// second); the first cue of a note needs fewer.
  static const cuePersistence = 8;
  static const firstCuePersistence = 4;

  /// Cents a voice may go past the border of the cue on screen before it
  /// changes: a voice right at 25 or 50 cents does not flicker.
  static const cueHysteresis = 8.0;

  /// Samples without voice (~300 ms) before the cue clears: a breath keeps it.
  static const silenceSamples = 10;

  final PitchReference reference;

  /// Wall-clock milliseconds; at another [speed] they are fewer or more
  /// milliseconds of the melody.
  final int latencyMs;
  final double speed;
  final PracticeMode mode;
  final List<_Bucket> _buckets;
  final _recent = <double>[];
  VocalCue? _cue, _candidate;
  int _candidateCount = 0, _silentSamples = 0;
  SungNote? _lastNote;

  /// The latency in melody milliseconds at this speed.
  int get lagMs => (latencyMs * speed).round();

  /// Together with the guide: [guideMs] is the guide position when the
  /// sample arrived.
  LiveVocalState onSample(PitchSample sample, int guideMs) {
    final at = guideMs - lagMs;
    final index = reference.noteIndexAt(at);
    return _hear(
      sample,
      at,
      index == null ? null : reference.notes[index],
      index,
    );
  }

  /// An echo or drill turn: [timelineMs] is the melody time the screen shows
  /// when the sample arrived; only the turn's notes count.
  LiveVocalState onTurnSample(
    PitchSample sample,
    int timelineMs,
    VocalTurn turn,
  ) {
    final at = timelineMs - lagMs;
    final slot = turn.slotAt(at);
    return _hear(
      sample,
      at,
      slot == null ? null : turn.notes[slot],
      slot == null ? null : turn.indices[slot],
    );
  }

  /// Forgets what was sung in [turn]'s notes: the student repeats it.
  void restart(VocalTurn turn) {
    for (final index in turn.indices) {
      _buckets[index] = _Bucket();
    }
    _lastNote = null;
    _recent.clear();
    _clearCue();
  }

  /// One note so far.
  NoteResult resultOf(int index) =>
      _buckets[index].result(reference.notes[index]);

  VocalSummary finish({required bool reachedEnd}) {
    final results = <NoteResult>[
      for (var i = 0; i < reference.notes.length; i++) resultOf(i),
    ];
    return summarize(
      results,
      reachedEnd: reachedEnd,
      latencyMs: latencyMs,
      mode: mode,
      speed: speed,
    );
  }

  LiveVocalState _hear(PitchSample sample, int at, SungNote? note, int? index) {
    if (note != _lastNote) {
      _recent.clear();
      _clearCue();
      _lastNote = note;
    }
    if (note == null || index == null) return const LiveVocalState();

    final folded = sample.midi == null ? null : fold(sample.midi!, note.midi);
    if (_inMiddle(note, at)) _buckets[index].add(folded);

    if (folded == null) {
      if (++_silentSamples >= silenceSamples) {
        _recent.clear();
        _clearCue();
      }
      return LiveVocalState(expected: note, cue: _cue);
    }
    _silentSamples = 0;
    _recent.add(folded);
    if (_recent.length > 5) _recent.removeAt(0);
    final cents = (_median(_recent) - note.midi) * 100;
    _update(cents);
    return LiveVocalState(
      expected: note,
      sungMidi: folded,
      cents: cents,
      cue: _cue,
    );
  }

  void _clearCue() {
    _cue = null;
    _candidate = null;
    _candidateCount = 0;
    _silentSamples = 0;
  }

  /// Persistence and hysteresis, like the dance `LiveFeedback`: a cue only
  /// changes when the voice clearly left it, and for long enough.
  void _update(double cents) {
    final current = _cue;
    if (current != null && cueFits(current, cents, cueHysteresis)) {
      _candidate = null;
      _candidateCount = 0;
      return;
    }
    // The candidate gets the same margin: a voice wobbling across a border
    // still settles on one cue instead of restarting the count every sample.
    final candidate = _candidate;
    if (candidate != null && cueFits(candidate, cents, cueHysteresis)) {
      _candidateCount++;
    } else {
      _candidate = cueFor(cents);
      _candidateCount = 1;
    }
    final needed = current == null ? firstCuePersistence : cuePersistence;
    if (_candidateCount >= needed) {
      _cue = _candidate;
      _candidate = null;
      _candidateCount = 0;
    }
  }

  static bool _inMiddle(SungNote note, int at) {
    final edge = (note.durationMs * edgeFraction).floor();
    return at >= note.startMs + edge && at < note.endMs - edge;
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final middle = sorted.length >> 1;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

/// The summary of [results]: one rule for a whole practice or a part of it.
VocalSummary summarize(
  List<NoteResult> results, {
  required bool reachedEnd,
  int latencyMs = 0,
  PracticeMode mode = PracticeMode.together,
  double speed = 1.0,
}) {
  int? percent(num part, int whole) =>
      whole <= 0 ? null : (100 * part / whole).round();
  final sung = results.where((r) => r.sung);
  final heard = results.where((r) => r.heard);
  int length(Iterable<NoteResult> notes) =>
      notes.fold(0, (total, r) => total + r.note.durationMs);
  final credit = sung.fold<double>(
    0,
    (total, r) =>
        total +
        r.note.durationMs *
            switch (r.grade) {
              NoteGrade.inTune => 1.0,
              NoteGrade.close => 0.5,
              _ => 0.0,
            },
  );
  final tuning = percent(credit, length(sung));
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
    mode: mode,
    speed: speed,
  );
}

/// The cue for a voice [cents] away from the note (negative: too low).
VocalCue cueFor(double cents) {
  if (cents.abs() <= VocalPractice.inTuneCents) return VocalCue.onPitch;
  if (cents < 0) {
    return cents < -VocalPractice.closeCents
        ? VocalCue.higher
        : VocalCue.slightlyHigher;
  }
  return cents > VocalPractice.closeCents
      ? VocalCue.lower
      : VocalCue.slightlyLower;
}

/// Whether [cents] is still within [cue]'s range widened by [margin].
bool cueFits(VocalCue cue, double cents, double margin) {
  const tune = VocalPractice.inTuneCents, close = VocalPractice.closeCents;
  return switch (cue) {
    VocalCue.onPitch => cents.abs() <= tune + margin,
    VocalCue.slightlyHigher =>
      cents >= -close - margin && cents <= -tune + margin,
    VocalCue.higher => cents <= -close + margin,
    VocalCue.slightlyLower => cents <= close + margin && cents >= tune - margin,
    VocalCue.lower => cents >= close - margin,
  };
}

/// The pitch moved by whole octaves to sit within half an octave of [target].
double fold(double midi, double target) {
  final offset = ((midi - target + 6) % 12 + 12) % 12 - 6;
  return target + offset;
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
