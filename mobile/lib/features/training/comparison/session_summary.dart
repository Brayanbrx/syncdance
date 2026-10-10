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
  }) : segments = List.unmodifiable(segments),
       feedback = List.unmodifiable(feedback);
  final int durationMs, evaluatedMs;
  final double? score, meanErrorDegrees;
  final double? meanPositionError, angleScore, positionScore;
  final String scoringVersion, summaryVersion, feedbackVersion;

  /// Compared against the mirrored master or the same sides; never mixed.
  final FollowMode followMode;
  final List<FeedbackSummary> feedback;
  final bool reachedVideoEnd;
  final List<SegmentSummary> segments;
  double get coverage => evaluatedMs / durationMs;
}

/// Unique 100 ms video bins, first valid result wins. Missing evidence is null.
/// This is estimated sampled coverage, not continuous biomechanical observation.
class SessionAccumulator {
  SessionAccumulator(this.durationMs, {this.followMode = FollowMode.sameSide}) {
    if (durationMs <= 0 || durationMs > 300000) {
      throw ArgumentError.value(durationMs);
    }
  }
  static const version = 'pose-summary-v1';
  static const binMs = 100;
  static const segmentMs = 5000;
  final int durationMs;
  final FollowMode followMode;
  final _bins = <int, PoseMatch>{};
  final _feedbackBins = <String>{};
  final _feedback = <String, FeedbackSummary>{};
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
    );
  }
}
