import 'dart:math' as math;

import '../../routines/reference/motion_reference.dart';
import '../comparison/session_summary.dart';
import '../pose/body_features.dart';

/// Rating of one move. Points and thresholds are provisional until the
/// controlled physical dataset calibrates them (see VALIDACION_FISICA.md).
enum MoveRating {
  perfect('PERFECT', 100),
  great('GREAT', 75),
  good('GOOD', 50),
  miss('MISS', 0);

  const MoveRating(this.label, this.points);
  final String label;
  final int points;
}

/// A time window of the master video that the learner is rated on.
class DanceMove {
  const DanceMove(this.index, this.startMs, this.endMs);
  final int index, startMs, endMs;
}

class RatedMove {
  const RatedMove(this.move, this.rating, this.score, this.evidence);
  final DanceMove move;

  /// Null when the learner was not measurable long enough (out of frame, low
  /// quality): the move is not rated rather than rated as a miss.
  final MoveRating? rating;

  /// Mean pose similarity (0-100) over the comparisons inside the move.
  final double? score;

  /// Fraction of the move's 100 ms bins that had a valid comparison.
  final double evidence;
}

class DanceGameResult {
  DanceGameResult({
    required this.points,
    required this.maxPoints,
    required this.maxCombo,
    required List<RatedMove> moves,
  }) : moves = List.unmodifiable(moves);

  final int points, maxPoints, maxCombo;
  final List<RatedMove> moves;

  /// Unrated moves count as zero here: stars require dancing in view. The
  /// technical similarity summary never penalizes missing evidence.
  double get ratio => maxPoints == 0 ? 0 : points / maxPoints;
  int get stars =>
      DanceGame.starRatios.where((threshold) => ratio >= threshold).length;
  int count(MoveRating? rating) =>
      moves.where((move) => move.rating == rating).length;

  /// The weakest rated moves, in video order, to practise in learn mode.
  List<RatedMove> toPractice([int count = 3]) {
    final weakest =
        moves
            .where((m) => m.rating != null && m.rating != MoveRating.perfect)
            .toList()
          ..sort((a, b) {
            final byScore = a.score!.compareTo(b.score!);
            return byScore != 0 ? byScore : a.move.index - b.move.index;
          });
    return weakest.take(count).toList()
      ..sort((a, b) => a.move.index - b.move.index);
  }
}

/// Game layer over the scorer output (the session accumulator). It never
/// changes how poses are compared; it only groups comparisons into moves and
/// turns them into ratings, combo, points and stars.
class DanceGame {
  DanceGame({required MotionReference reference, required this.session})
    : moves = List.unmodifiable(movesFor(reference));

  static const version = 'dance-game-v1';
  static const moveMs = 1000;

  /// Inference arrives after capture; wait before closing a move.
  static const settleMs = 400;
  static const minEvidence = 0.4;
  static const perfectScore = 85.0;
  static const greatScore = 70.0;
  static const goodScore = 50.0;
  static const starRatios = [0.3, 0.45, 0.6, 0.75, 0.9];

  final SessionAccumulator session;
  final List<DanceMove> moves;
  final _rated = <RatedMove>[];
  int _next = 0;
  int _points = 0;
  int _combo = 0;
  int _maxCombo = 0;

  int get points => _points;
  int get combo => _combo;
  int get maxPoints => moves.length * MoveRating.perfect.points;
  List<RatedMove> get rated => List.unmodifiable(_rated);

  /// Windows where the master itself is measurable; a short tail is dropped.
  static List<DanceMove> movesFor(MotionReference reference) {
    final duration = reference.metadata.durationMs;
    final result = <DanceMove>[];
    for (var start = 0; start < duration; start += moveMs) {
      final end = math.min(start + moveMs, duration);
      if (end - start < moveMs ~/ 2) break;
      final samples = reference.samples.where(
        (s) => s.timestampMs >= start && s.timestampMs < end,
      );
      final ratable = samples.where(
        (s) =>
            s.quality == 'SINGLE_PERSON' &&
            s.angles.length == BodyAngle.values.length,
      );
      if (samples.isNotEmpty && ratable.length * 2 >= samples.length) {
        result.add(DanceMove(result.length, start, end));
      }
    }
    return result;
  }

  static MoveRating ratingFor(double score) => score >= perfectScore
      ? MoveRating.perfect
      : score >= greatScore
      ? MoveRating.great
      : score >= goodScore
      ? MoveRating.good
      : MoveRating.miss;

  /// Rates the moves that ended at least [settleMs] before [videoMs].
  List<RatedMove> advance(int videoMs) {
    final added = <RatedMove>[];
    while (_next < moves.length && moves[_next].endMs + settleMs <= videoMs) {
      added.add(_rate(moves[_next++]));
    }
    return added;
  }

  /// Rates every remaining move; call once when the song ends or is stopped.
  DanceGameResult finish() {
    while (_next < moves.length) {
      _rate(moves[_next++]);
    }
    return DanceGameResult(
      points: _points,
      maxPoints: maxPoints,
      maxCombo: _maxCombo,
      moves: _rated,
    );
  }

  RatedMove _rate(DanceMove move) {
    final matches = session.matchesIn(move.startMs, move.endMs);
    final bins = ((move.endMs - move.startMs) / SessionAccumulator.binMs)
        .ceil();
    final evidence = matches.length / bins;
    if (matches.isEmpty || evidence < minEvidence) {
      // Not measurable: no points, and the combo is neither kept nor broken.
      final unrated = RatedMove(move, null, null, evidence);
      _rated.add(unrated);
      return unrated;
    }
    final score =
        matches.fold<double>(0, (sum, m) => sum + m.score) / matches.length;
    final rating = ratingFor(score);
    _points += rating.points;
    _combo = rating == MoveRating.miss ? 0 : _combo + 1;
    _maxCombo = math.max(_maxCombo, _combo);
    final result = RatedMove(move, rating, score, evidence);
    _rated.add(result);
    return result;
  }
}

/// Game outcome stored with the practice summary (local; not uploaded yet).
class GameSummary {
  const GameSummary({
    required this.points,
    required this.maxPoints,
    required this.maxCombo,
    required this.counts,
    this.version = DanceGame.version,
  });

  factory GameSummary.of(DanceGameResult result) => GameSummary(
    points: result.points,
    maxPoints: result.maxPoints,
    maxCombo: result.maxCombo,
    counts: {
      for (final rating in MoveRating.values) rating.name: result.count(rating),
      'unrated': result.count(null),
    },
  );

  final int points, maxPoints, maxCombo;
  final String version;

  /// Moves per rating name plus `unrated`.
  final Map<String, int> counts;

  int get stars => DanceGameResult(
    points: points,
    maxPoints: maxPoints,
    maxCombo: maxCombo,
    moves: const [],
  ).stars;

  Map<String, Object?> toJson() => {
    'version': version,
    'points': points,
    'max_points': maxPoints,
    'max_combo': maxCombo,
    'counts': counts,
  };

  static GameSummary fromJson(Object? value) {
    void require(bool condition) {
      if (!condition) {
        throw const FormatException('Resultado de juego inválido.');
      }
    }

    require(value is Map<String, dynamic>);
    final data = value as Map<String, dynamic>;
    final points = data['points'], maxPoints = data['max_points'];
    final maxCombo = data['max_combo'], rawCounts = data['counts'];
    require(
      data['version'] is String && (data['version'] as String).isNotEmpty,
    );
    require(maxPoints is int && maxPoints >= 0 && maxPoints <= 100000);
    require(points is int && points >= 0 && points <= (maxPoints as int));
    require(rawCounts is Map<String, dynamic>);
    final counts = <String, int>{};
    for (final name in [...MoveRating.values.map((r) => r.name), 'unrated']) {
      final count = (rawCounts as Map<String, dynamic>)[name];
      require(count is int && count >= 0);
      counts[name] = count as int;
    }
    final moves = counts.values.fold(0, (sum, count) => sum + count);
    require(moves * MoveRating.perfect.points == maxPoints);
    require(maxCombo is int && maxCombo >= 0 && maxCombo <= moves);
    return GameSummary(
      points: points as int,
      maxPoints: maxPoints,
      maxCombo: maxCombo as int,
      counts: counts,
      version: data['version'] as String,
    );
  }
}
