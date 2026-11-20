import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../routines/reference/motion_reference.dart';
import '../feedback/feedback_rules.dart';
import '../feedback/live_feedback.dart';
import '../pose/body_features.dart';
import '../pose/pose_frame.dart';
import '../pose/pose_measurements.dart';
import 'capture_video_clock.dart';
import 'pose_matcher.dart';
import 'session_summary.dart';

/// The live comparison loop without widgets or plugins: binds capture time to
/// the master video, compares with the reference, drives one feedback cue and
/// feeds the session summary. It never uses the network.
///
/// The owner reports whether the master video is running (playing, not
/// buffering, completed or failed) and its position; anything else invalidates.
class LivePractice extends ChangeNotifier {
  LivePractice({
    required this._reference,
    this._session,
    this._nowMs,
    this.coaching = true,
  });

  /// False in the dance game: no textual cues are shown, so none are evaluated
  /// or counted as shown in the summary.
  final bool coaching;

  /// A score older than this is withdrawn together with its guidance.
  static const expiry = Duration(milliseconds: 250);

  final int Function()? _nowMs;
  final _watch = Stopwatch()..start();
  final _clock = CaptureVideoClock();
  MotionReference _reference;
  SessionAccumulator? _session;
  var _feedback = LiveFeedback();
  PoseMatch? _match;
  Timer? _expiry;
  int? _generation;
  Object? _orientation;
  bool _disposed = false;

  /// The video ended; frames captured before the end may still arrive.
  bool _ended = false;

  int get _now => _nowMs?.call() ?? _watch.elapsedMilliseconds;
  PoseMatch? get match => _match;
  FeedbackCue? get activeCue => _feedback.active;
  SessionAccumulator? get session => _session;

  /// A new practice or reference starts with fresh guidance (no cooldown carry).
  void rebind({
    required MotionReference reference,
    required SessionAccumulator? session,
  }) {
    if (identical(reference, _reference) && identical(session, _session)) {
      return;
    }
    invalidate();
    _reference = reference;
    _session = session;
    _feedback = LiveFeedback();
  }

  /// Pause, seek, buffering, quality loss, recalibration or a new camera
  /// generation: drop pending bindings, the score and the visible cue.
  void invalidate() {
    if (_disposed) return;
    _ended = false;
    _clock.invalidate();
    _expiry?.cancel();
    _match = null;
    _feedback.invalidate(_now);
    notifyListeners();
  }

  /// [speed] is the playback rate (learn mode slows the master).
  void videoChanged({
    required bool running,
    required int positionMs,
    double speed = 1.0,
  }) {
    if (!running) {
      // After the end the player stays stopped: that is not a pause, so the
      // frames still on their way are kept (see [videoEnded]).
      if (!_ended) invalidate();
      return;
    }
    _ended = false;
    _clock.report(
      videoMs: positionMs,
      nowMs: _now,
      playing: true,
      speed: speed,
    );
  }

  /// The video played to its end. Frames captured before it still count
  /// when their pose arrives (inference is late, as every move's settle time
  /// assumes); nothing captured after it is bound, and no cue is shown.
  void videoEnded() {
    if (_disposed || _ended) return;
    _ended = true;
    _clock.end(nowMs: _now);
    _expiry?.cancel();
    _match = null;
    _feedback.invalidate(_now);
    notifyListeners();
  }

  void frameCaptured({
    required int generation,
    required Object orientation,
    required int timestampMs,
    required bool running,
    required int positionMs,
    double speed = 1.0,
  }) {
    if (_generation != generation || _orientation != orientation) {
      invalidate();
      _generation = generation;
      _orientation = orientation;
    }
    videoChanged(running: running, positionMs: positionMs, speed: speed);
    _clock.capture(timestampMs: timestampMs, nowMs: _now);
  }

  void measured(
    PoseFrame pose,
    PoseMeasurements measurements, {
    required bool running,
  }) {
    if (_disposed) return;
    final videoMs = _clock.resolve(timestampMs: pose.timestampMs, nowMs: _now);
    _expiry?.cancel();
    // Reference features are unsmoothed: avoid adding display EMA delay.
    final features =
        (running || _ended) && videoMs != null && measurements.canMeasure
        ? const BodyFeatureExtractor().extract(pose)
        : null;
    final match = features != null && videoMs != null
        ? PoseMatcher(_reference).compare(features, videoMs)
        : null;
    _match = match;
    if (videoMs != null) _session?.record(videoMs, match);
    if (match != null && coaching && !_ended) {
      final presentations = _feedback.presentations;
      _feedback.update(
        captureMs: pose.timestampMs,
        nowMs: _now,
        cues: const FeedbackRules().evaluate(features!, match),
      );
      if (_feedback.presentations != presentations && videoMs != null) {
        _session?.recordFeedback(videoMs, _feedback.active!);
      }
    } else {
      _feedback.invalidate(_now);
    }
    if (match != null) {
      _expiry = Timer(expiry, () {
        _match = null;
        _feedback.invalidate(_now);
        if (!_disposed) notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    _watch.stop();
    super.dispose();
  }
}
