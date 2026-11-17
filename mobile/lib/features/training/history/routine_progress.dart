import '../game/dance_game.dart';
import 'saved_session.dart';

/// The best game of each routine at normal speed, of any reference version
/// or follow mode, by share of points: the rule the server uses for course
/// tasks (`apps/coaching/selectors.routine_evidence`). The catalog stars and
/// the learning path use it, so they never disagree with the course, and a
/// passed step stays passed after a new version or a change of mode.
Map<int, GameSummary> bestGamesByRoutine(Iterable<SavedSession> sessions) {
  final best = <int, GameSummary>{};
  for (final session in sessions) {
    final game = session.game;
    if (game == null ||
        game.maxPoints <= 0 ||
        session.summary.playbackSpeed != 1.0) {
      continue;
    }
    final routine = session.reference.routineId;
    final current = best[routine];
    if (current == null ||
        game.points / game.maxPoints > current.points / current.maxPoints) {
      best[routine] = game;
    }
  }
  return best;
}

/// Best mark and recent trend among comparable practices of one routine.
class RoutineProgress {
  RoutineProgress({
    required this.routineName,
    required this.referenceVersion,
    required this.lastPracticeAt,
    required List<SavedSession> comparable,
    required this.excluded,
    this.bestGame,
  }) : comparable = List.unmodifiable(comparable);

  final String routineName;
  final int referenceVersion;

  /// Most recent practice of the routine, comparable or not.
  final DateTime lastPracticeAt;

  /// Oldest first; every entry has a score and enough coverage.
  final List<SavedSession> comparable;

  /// Practices of the same routine left out: no evidence, low coverage, or
  /// another reference/algorithm version.
  final int excluded;

  /// Highest game points among games comparable with the latest one (same
  /// reference, game version and follow mode); the first to reach it wins a
  /// tie. Null when the routine was never played in game mode.
  final SavedSession? bestGame;

  SavedSession? get best => comparable.isEmpty
      ? null
      : comparable.reduce(
          (a, b) => b.summary.score! > a.summary.score! ? b : a,
        );
  SavedSession? get latest => comparable.isEmpty ? null : comparable.last;

  /// Latest minus the previous comparable score; null with fewer than two.
  double? get change => comparable.length < 2
      ? null
      : comparable.last.summary.score! -
            comparable[comparable.length - 2].summary.score!;

  /// Scores of the last [count] comparable practices, oldest first.
  List<double> recentScores([int count = 5]) => [
    for (final s in comparable.skip(
      comparable.length > count ? comparable.length - count : 0,
    ))
      s.summary.score!,
  ];
}

/// Progress is only meaningful between equal references, algorithms, follow
/// modes, playback speeds and enough evaluated time. The coverage cutoff is provisional until physical validation.
class RoutineProgressCalculator {
  const RoutineProgressCalculator();

  /// v2: adds the best game per routine.
  static const version = 'routine-progress-v2';
  static const minimumCoverage = 0.5;

  static bool _sameBasis(SavedSession a, SavedSession b) =>
      a.reference.routineId == b.reference.routineId &&
      a.reference.version == b.reference.version &&
      a.summary.scoringVersion == b.summary.scoringVersion &&
      a.summary.summaryVersion == b.summary.summaryVersion &&
      a.summary.followMode == b.summary.followMode &&
      a.summary.playbackSpeed == b.summary.playbackSpeed;

  static bool _sameGameBasis(SavedSession a, SavedSession b) =>
      a.reference.routineId == b.reference.routineId &&
      a.reference.version == b.reference.version &&
      a.game!.version == b.game!.version &&
      a.summary.followMode == b.summary.followMode &&
      a.summary.playbackSpeed == b.summary.playbackSpeed;

  static SavedSession? _bestGame(Iterable<SavedSession> ofRoutine) {
    final games = ofRoutine.where((s) => s.game != null).toList();
    if (games.isEmpty) return null;
    SavedSession? best;
    for (final s in games) {
      if (!_sameGameBasis(s, games.last)) continue;
      if (best == null || s.game!.points > best.game!.points) best = s;
    }
    return best;
  }

  /// One entry per routine, based on the basis of its most recent practice.
  List<RoutineProgress> compute(List<SavedSession> sessions) {
    final ordered = [...sessions]
      ..sort((a, b) {
        final time = a.startedAt.compareTo(b.startedAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    final latestByRoutine = <int, SavedSession>{};
    for (final session in ordered) {
      latestByRoutine[session.reference.routineId] = session;
    }
    final result = <RoutineProgress>[];
    for (final anchor in latestByRoutine.values) {
      final ofRoutine = ordered.where(
        (s) => s.reference.routineId == anchor.reference.routineId,
      );
      final comparable = [
        for (final s in ofRoutine)
          if (_sameBasis(s, anchor) &&
              s.summary.score != null &&
              s.summary.coverage >= minimumCoverage)
            s,
      ];
      result.add(
        RoutineProgress(
          routineName: anchor.routineName,
          referenceVersion: anchor.reference.version,
          lastPracticeAt: anchor.startedAt,
          comparable: comparable,
          excluded: ofRoutine.length - comparable.length,
          bestGame: _bestGame(ofRoutine),
        ),
      );
    }
    result.sort((a, b) => b.lastPracticeAt.compareTo(a.lastPracticeAt));
    return result;
  }
}
