import '../../routines/reference/motion_reference.dart';
import 'follow_mode.dart';
import 'pose_matcher.dart';
import '../feedback/feedback_rules.dart';

class FeedbackSummary {
  const FeedbackSummary({
    required this.code,
    required this.region,
    required this.message,
    required this.count,
    required this.maxSeverity,
  });
  final String code, region, message;
  final int count;
  final double maxSeverity;
}

class SegmentSummary {
  const SegmentSummary({
    required this.startMs,
    required this.endMs,
    required this.evaluatedMs,
    required this.score,
  });
  final int startMs, endMs, evaluatedMs;
  final double? score;
  double get coverage => evaluatedMs / (endMs - startMs);
}

/// One instructor step of the practice (`step-summary-v1`): the same 100 ms
/// evidence as the segments, over the step's window, and the cues shown in it.
class StepSummary {
  StepSummary({
    required this.index,
    required this.startMs,
    required this.endMs,
    required this.evaluatedMs,
    required this.score,
    Map<String, int> feedback = const {},
  }) : feedback = Map.unmodifiable(feedback);
  final int index, startMs, endMs, evaluatedMs;
  final double? score;

  /// Times each cue code was shown inside the step.
  final Map<String, int> feedback;
  double get coverage => evaluatedMs / (endMs - startMs);
}

class SessionSummary {
  SessionSummary({
    required this.durationMs,
    required this.evaluatedMs,
    required this.score,
    required this.meanErrorDegrees,
    required this.meanPositionError,
    required this.angleScore,
    required this.positionScore,
    required this.reachedVideoEnd,
    required List<SegmentSummary> segments,
    List<FeedbackSummary> feedback = const [],
    this.scoringVersion = PoseMatcher.version,
    this.summaryVersion = SessionAccumulator.version,
    this.feedbackVersion = FeedbackRules.version,
    this.followMode = FollowMode.sameSide,
    this.playbackSpeed = 1.0,
    List<StepSummary> steps = const [],
    this.stepsVersion,
  }) : segments = List.unmodifiable(segments),
       feedback = List.unmodifiable(feedback),
       steps = List.unmodifiable(steps);
  final int durationMs, evaluatedMs;
  final double? score, meanErrorDegrees;
  final double? meanPositionError, angleScore, positionScore;
  final String scoringVersion, summaryVersion, feedbackVersion;

  /// Compared against the mirrored master or the same sides; never mixed.
  final FollowMode followMode;

  /// Learn mode slows the master (0.5x, 0.75x): timing windows widen in real
  /// time, so practices at different speeds are never compared.
  final double playbackSpeed;
  final List<FeedbackSummary> feedback;
  final bool reachedVideoEnd;
  final List<SegmentSummary> segments;

  /// Results per instructor step; empty for references without steps.
  final List<StepSummary> steps;

  /// [SessionAccumulator.stepsVersion] when steps were summarized, else null
  /// (practices from before steps existed). Apart from [summaryVersion], which
  /// the routine progress compares: adding steps never resets a progress.
  final String? stepsVersion;
  double get coverage => evaluatedMs / durationMs;
}

/// Unique 100 ms video bins, first valid result wins. Missing evidence is null.
/// This is estimated sampled coverage, not continuous biomechanical observation.
class SessionAccumulator {
  SessionAccumulator(
    this.durationMs, {
    this.followMode = FollowMode.sameSide,
    this.playbackSpeed = 1.0,
    List<RoutineStep> steps = const [],
  }) : steps = List.unmodifiable(steps) {
    if (!SessionAccumulator.speeds.contains(playbackSpeed)) {
      throw ArgumentError.value(playbackSpeed, 'playbackSpeed');
    }
    if (durationMs <= 0 || durationMs > 300000) {
      throw ArgumentError.value(durationMs);
    }
  }
  static const version = 'pose-summary-v1';
  static const stepsVersion = 'step-summary-v1';
  static const binMs = 100;
  static const segmentMs = 5000;
  final int durationMs;
  final FollowMode followMode;
  final double playbackSpeed;

  /// The instructor's steps of the reference, summarized one by one.
  final List<RoutineStep> steps;
  static const speeds = [0.5, 0.75, 1.0];
  final _bins = <int, PoseMatch>{};
  final _feedbackBins = <String>{};
  final _feedback = <String, FeedbackSummary>{};
  final _stepFeedback = <int, Map<String, int>>{};
  SessionSummary? _finished;

  /// Count only newly displayed persistent cues, once per code/video bin.
  /// These are guidance occurrences, not all errors or a duration estimate.
  void recordFeedback(int videoMs, FeedbackCue cue) {
    if (_finished != null ||
        videoMs < 0 ||
        videoMs >= durationMs ||
        !_bins.containsKey(videoMs ~/ binMs) ||
        !cue.severity.isFinite ||
        cue.severity < 1 ||
        !_feedbackBins.add('${videoMs ~/ binMs}:${cue.code}')) {
      return;
    }
    for (final step in steps) {
      if (videoMs >= step.startMs && videoMs < step.endMs) {
        final shown = _stepFeedback.putIfAbsent(step.index, () => {});
        shown[cue.code] = (shown[cue.code] ?? 0) + 1;
      }
    }
    final previous = _feedback[cue.code];
    _feedback[cue.code] = FeedbackSummary(
      code: cue.code,
      region: cue.region,
      message: cue.message,
      count: (previous?.count ?? 0) + 1,
      maxSeverity: previous == null || cue.severity > previous.maxSeverity
          ? cue.severity
          : previous.maxSeverity,
    );
  }

  void record(int videoMs, PoseMatch? match) {
    if (_finished != null ||
        videoMs < 0 ||
        videoMs >= durationMs ||
        match == null ||
        !match.score.isFinite ||
        match.score < 0 ||
        match.score > 100 ||
        !match.meanErrorDegrees.isFinite ||
        match.meanErrorDegrees < 0 ||
        match.meanErrorDegrees > 180 ||
        !match.meanPositionError.isFinite ||
        match.meanPositionError < 0) {
      return;
    }
    _bins.putIfAbsent(videoMs ~/ binMs, () => match);
  }

  int get evaluatedMs => _bins.keys.fold(0, (sum, bin) => sum + _width(bin));

  /// Recorded comparisons whose 100 ms bin starts in [startMs, endMs).
  /// Read-only view for layers built on the scorer (the dance game).
  List<PoseMatch> matchesIn(int startMs, int endMs) => [
    for (var bin = startMs ~/ binMs; bin * binMs < endMs; bin++) ?_bins[bin],
  ];
  int _width(int bin) => (durationMs - bin * binMs).clamp(0, binMs);

  SessionSummary finish({required bool reachedVideoEnd}) =>
      _finished ??= _snapshot(reachedVideoEnd);

  SessionSummary _snapshot(bool reachedVideoEnd) {
    var weightedScore = 0.0;
    var weightedError = 0.0;
    var weightedPositionError = 0.0;
    var weightedAngleScore = 0.0;
    var weightedPositionScore = 0.0;
    final segments = <SegmentSummary>[];
    for (var start = 0; start < durationMs; start += segmentMs) {
      final end = (start + segmentMs).clamp(0, durationMs);
      var covered = 0;
      var score = 0.0;
      for (var bin = start ~/ binMs; bin * binMs < end; bin++) {
        final match = _bins[bin];
        if (match == null) continue;
        final width = _width(bin);
        covered += width;
        score += match.score * width;
        weightedError += match.meanErrorDegrees * width;
        weightedPositionError += match.meanPositionError * width;
        weightedAngleScore += match.angleScore * width;
        weightedPositionScore += match.positionScore * width;
      }
      weightedScore += score;
      segments.add(
        SegmentSummary(
          startMs: start,
          endMs: end,
          evaluatedMs: covered,
          score: covered == 0 ? null : score / covered,
        ),
      );
    }
    final covered = evaluatedMs;
    final feedback = _feedback.values.toList()
      ..sort((a, b) {
        final count = b.count.compareTo(a.count);
        return count != 0 ? count : a.code.compareTo(b.code);
      });
    return SessionSummary(
      durationMs: durationMs,
      evaluatedMs: covered,
      score: covered == 0 ? null : weightedScore / covered,
      meanErrorDegrees: covered == 0 ? null : weightedError / covered,
      meanPositionError: covered == 0 ? null : weightedPositionError / covered,
      angleScore: covered == 0 ? null : weightedAngleScore / covered,
      positionScore: covered == 0 ? null : weightedPositionScore / covered,
      reachedVideoEnd: reachedVideoEnd,
      segments: segments,
      feedback: feedback,
      followMode: followMode,
      playbackSpeed: playbackSpeed,
      steps: [for (final step in steps) _stepSummary(step)],
      // Nothing to send without steps: an empty list could disagree with a
      // server that has steps the phone could not read.
      stepsVersion: steps.isEmpty ? null : SessionAccumulator.stepsVersion,
    );
  }

  /// Bins overlapping the step, clipped to it: a bin across two steps splits
  /// its time between them, so step evidence never exceeds the session's.
  StepSummary _stepSummary(RoutineStep step) {
    var covered = 0;
    var score = 0.0;
    for (var bin = step.startMs ~/ binMs; bin * binMs < step.endMs; bin++) {
      final match = _bins[bin];
      if (match == null) continue;
      final start = bin * binMs;
      final end = start + _width(bin);
      final overlap =
          (end < step.endMs ? end : step.endMs) -
          (start > step.startMs ? start : step.startMs);
      if (overlap <= 0) continue;
      covered += overlap;
      score += match.score * overlap;
    }
    return StepSummary(
      index: step.index,
      startMs: step.startMs,
      endMs: step.endMs,
      evaluatedMs: covered,
      score: covered == 0 ? null : score / covered,
      feedback: _stepFeedback[step.index] ?? const {},
    );
  }
}
