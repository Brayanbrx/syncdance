import 'saved_session.dart';

/// Best mark and recent trend among comparable practices of one routine.
class RoutineProgress {
  RoutineProgress({
    required this.routineName,
    required this.referenceVersion,
    required this.lastPracticeAt,
    required List<SavedSession> comparable,
    required this.excluded,
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
  static const version = 'routine-progress-v1';
  static const minimumCoverage = 0.5;

  static bool _sameBasis(SavedSession a, SavedSession b) =>
      a.reference.routineId == b.reference.routineId &&
      a.reference.version == b.reference.version &&
      a.summary.scoringVersion == b.summary.scoringVersion &&
      a.summary.summaryVersion == b.summary.summaryVersion &&
      a.summary.followMode == b.summary.followMode &&
      a.summary.playbackSpeed == b.summary.playbackSpeed;

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
        ),
      );
    }
    result.sort((a, b) => b.lastPracticeAt.compareTo(a.lastPracticeAt));
    return result;
  }
}
