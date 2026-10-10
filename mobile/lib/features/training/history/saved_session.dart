import 'dart:math';

import '../../routines/reference/motion_reference.dart';
import '../comparison/follow_mode.dart';
import '../comparison/session_summary.dart';
import '../game/dance_game.dart';

String newSessionId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Frozen metadata and aggregate evidence; no images or per-frame poses.
class SavedSession {
  const SavedSession({
    required this.id,
    required this.routineName,
    required this.reference,
    required this.startedAt,
    required this.finishedAt,
    required this.summary,
    this.game,
  });
  final String id, routineName;
  final ReferenceMetadata reference;
  final DateTime startedAt, finishedAt;
  final SessionSummary summary;

  /// Present when the practice was played in dance (game) mode.
  final GameSummary? game;
  static final validId = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
  );

  Map<String, dynamic> toJson() => {
    'schema': 'local-session-v2',
    'id': id,
    'routine_name': routineName,
    'reference': reference.toJson(),
    'started_at': startedAt.toUtc().toIso8601String(),
    'finished_at': finishedAt.toUtc().toIso8601String(),
    'summary': {
      'duration_ms': summary.durationMs,
      'evaluated_ms': summary.evaluatedMs,
      'score': summary.score,
      'angle_score': summary.angleScore,
      'position_score': summary.positionScore,
      'mean_error_degrees': summary.meanErrorDegrees,
      'mean_position_error': summary.meanPositionError,
      'reached_video_end': summary.reachedVideoEnd,
      'scoring_version': summary.scoringVersion,
      'summary_version': summary.summaryVersion,
      'feedback_version': summary.feedbackVersion,
      'follow_mode': summary.followMode.code,
      'playback_speed': summary.playbackSpeed,
      'segments': [
        for (final s in summary.segments)
          {
            'start_ms': s.startMs,
            'end_ms': s.endMs,
            'evaluated_ms': s.evaluatedMs,
            'score': s.score,
          },
      ],
      'feedback': [
        for (final f in summary.feedback)
          {
            'code': f.code,
            'region': f.region,
            'message': f.message,
            'count': f.count,
            'max_severity': f.maxSeverity,
          },
      ],
    },
    if (game != null) 'game': game!.toJson(),
  };

  /// Payload for `POST training/sessions/` (backend/apps/training/README.md).
  /// The overall score is pose-only under pose-window-v1; timing is not measured.
  Map<String, Object?> toUpload() => {
    'id': id,
    'routine': reference.routineId,
    'reference_version': reference.version,
    'started_at': startedAt.toUtc().toIso8601String(),
    'finished_at': finishedAt.toUtc().toIso8601String(),
    'status': 'COMPLETED',
    'mode': 'LIVE',
    'overall_score': summary.score,
    'pose_score': summary.score,
    'timing_score': null,
    'angle_score': summary.angleScore,
    'position_score': summary.positionScore,
    'mean_error_degrees': summary.meanErrorDegrees,
    'mean_position_error': summary.meanPositionError,
    'duration_ms': summary.durationMs,
    'evaluated_ms': summary.evaluatedMs,
    'reached_video_end': summary.reachedVideoEnd,
    'scoring_version': summary.scoringVersion,
    'summary_version': summary.summaryVersion,
    'feedback_version': summary.feedbackVersion,
    'follow_mode': summary.followMode.code,
    'playback_speed': summary.playbackSpeed,
    'timeline_segments': [
      for (final s in summary.segments)
        {
          'start_ms': s.startMs,
          'end_ms': s.endMs,
          'evaluated_ms': s.evaluatedMs,
          'score': s.score,
        },
    ],
    'feedback_counts': [
      for (final f in summary.feedback)
        {
          'code': f.code,
          'region': f.region,
          'message': f.message,
          'count': f.count,
          'max_severity': f.maxSeverity,
        },
    ],
    if (game != null) 'game': game!.toJson(),
  };

  factory SavedSession.fromJson(Map<String, dynamic> data) {
    void require(bool condition) {
      if (!condition) throw const FormatException('Resumen local inválido.');
    }

    String label(Object? value, [int max = 500]) {
      require(value is String && value.isNotEmpty && value.length <= max);
      return value as String;
    }

    int integer(Object? value, int min, int max) {
      require(value is int && value >= min && value <= max);
      return value as int;
    }

    double? metric(Object? value, bool hasEvidence, double max) {
      if (!hasEvidence) {
        require(value == null);
        return null;
      }
      require(value is num && value.isFinite && value >= 0 && value <= max);
      return (value as num).toDouble();
    }

    // v1 predates follow modes: it always compared the same anatomical sides.
    final schema = data['schema'];
    require(schema == 'local-session-v1' || schema == 'local-session-v2');
    final id = label(data['id']);
    require(validId.hasMatch(id));
    final reference = ReferenceMetadata.fromJson(object(data['reference']));
    final startText = label(data['started_at']);
    final endText = label(data['finished_at']);
    require(startText.endsWith('Z') && endText.endsWith('Z'));
    final startedAt = DateTime.parse(startText);
    final finishedAt = DateTime.parse(endText);
    require(!finishedAt.isBefore(startedAt));
    final s = object(data['summary']);
    final followMode = schema == 'local-session-v1'
        ? FollowMode.sameSide
        : FollowMode.fromCode(s['follow_mode']);
    require(followMode != null);
    // Absent before learn mode existed: those practices ran at normal speed.
    final rawSpeed = s['playback_speed'] ?? 1.0;
    require(rawSpeed is num);
    final playbackSpeed = (rawSpeed as num).toDouble();
    require(SessionAccumulator.speeds.contains(playbackSpeed));
    final duration = integer(s['duration_ms'], 1, 300000);
    require(duration == reference.durationMs);
    final evaluated = integer(s['evaluated_ms'], 0, duration);
    final segments = <SegmentSummary>[];
    var end = 0, covered = 0;
    var weighted = 0.0;
    final rawSegments = s['segments'];
    require(rawSegments is List && rawSegments.length <= 60);
    for (final value in rawSegments as List) {
      final segment = object(value);
      final start = integer(segment['start_ms'], 0, duration - 1);
      final next = integer(segment['end_ms'], start + 1, duration);
      require(start == end && next == (start + 5000).clamp(0, duration));
      final evidence = integer(segment['evaluated_ms'], 0, next - start);
      final score = metric(segment['score'], evidence > 0, 100);
      segments.add(
        SegmentSummary(
          startMs: start,
          endMs: next,
          evaluatedMs: evidence,
          score: score,
        ),
      );
      covered += evidence;
      weighted += (score ?? 0) * evidence;
      end = next;
    }
    require(end == duration && covered == evaluated);
    final score = metric(s['score'], evaluated > 0, 100);
    require(evaluated == 0 || (score! - weighted / evaluated).abs() < 1e-6);
    require(s['reached_video_end'] is bool);
    final rawFeedback = s['feedback'];
    require(rawFeedback is List && rawFeedback.length <= 64);
    final feedback = <FeedbackSummary>[];
    final codes = <String>{};
    for (final value in rawFeedback as List) {
      final f = object(value);
      final code = label(f['code'], 100);
      require(codes.add(code) && evaluated > 0);
      final severity = metric(f['max_severity'], true, double.maxFinite)!;
      require(severity >= 1);
      feedback.add(
        FeedbackSummary(
          code: code,
          region: label(f['region'], 100),
          message: label(f['message']),
          count: integer(f['count'], 1, 3000),
          maxSeverity: severity,
        ),
      );
    }
    feedback.sort((a, b) {
      final count = b.count.compareTo(a.count);
      return count != 0 ? count : a.code.compareTo(b.code);
    });
    // v1 files never contain a game; a game needs evidence of the follow mode.
    final game = data['game'] == null
        ? null
        : schema == 'local-session-v2'
        ? GameSummary.fromJson(data['game'])
        : throw const FormatException('Resumen local inválido.');
    return SavedSession(
      id: id,
      routineName: label(data['routine_name']),
      reference: reference,
      startedAt: startedAt,
      finishedAt: finishedAt,
      game: game,
      summary: SessionSummary(
        durationMs: duration,
        evaluatedMs: evaluated,
        score: score,
        angleScore: metric(s['angle_score'], evaluated > 0, 100),
        positionScore: metric(s['position_score'], evaluated > 0, 100),
        meanErrorDegrees: metric(s['mean_error_degrees'], evaluated > 0, 180),
        meanPositionError: metric(
          s['mean_position_error'],
          evaluated > 0,
          double.maxFinite,
        ),
        reachedVideoEnd: s['reached_video_end'] as bool,
        segments: segments,
        feedback: feedback,
        scoringVersion: label(s['scoring_version'], 100),
        summaryVersion: label(s['summary_version'], 100),
        feedbackVersion: label(s['feedback_version'], 100),
        followMode: followMode!,
        playbackSpeed: playbackSpeed,
      ),
    );
  }
}
