import 'feedback_rules.dart';

class _Evidence {
  _Evidence(this.startMs);
  final int startMs;
  int samples = 1;
}

/// One cue at a time; capture time establishes persistence, monotonic local time
/// controls display/cooldown even after a seek or a camera timestamp restart.
class LiveFeedback {
  static const persistenceMs = 400;
  static const minimumSamples = 4;
  static const maximumGapMs = 250;
  static const displayMs = 1200;
  static const cooldownMs = 1500;
  final _evidence = <String, _Evidence>{};
  final _regionReadyAt = <String, int>{};
  int? _lastCaptureMs;
  int _shownAt = 0;
  int _nextMessageAt = 0;
  FeedbackCue? _active;
  FeedbackCue? get active => _active;
  int _presentations = 0;
  int get presentations => _presentations;

  void _clearActive(int nowMs) {
    final cue = _active;
    if (cue != null) _regionReadyAt[cue.region] = nowMs + cooldownMs;
    _active = null;
  }

  /// Invalid quality, pauses, seeks and stale input clear guidance immediately.
  /// Keep cooldown so interruptions cannot cause rapid contradictory messages.
  void invalidate(int nowMs) {
    _clearActive(nowMs);
    _evidence.clear();
    _lastCaptureMs = null;
  }

  void update({
    required int captureMs,
    required int nowMs,
    required List<FeedbackCue> cues,
  }) {
    if (_lastCaptureMs != null && captureMs <= _lastCaptureMs!) return;
    if (_lastCaptureMs != null && captureMs - _lastCaptureMs! > maximumGapMs) {
      invalidate(nowMs);
    }
    _lastCaptureMs = captureMs;
    final valid = {
      for (final cue in cues)
        if (cue.threshold.isFinite &&
            cue.threshold > 0 &&
            cue.magnitude.isFinite &&
            cue.magnitude >= 0)
          cue.code: cue,
    };
    _evidence.removeWhere((code, _) => (valid[code]?.severity ?? 0) < 1);
    for (final cue in valid.values.where((cue) => cue.severity >= 1)) {
      final evidence = _evidence[cue.code];
      if (evidence == null) {
        _evidence[cue.code] = _Evidence(captureMs);
      } else {
        evidence.samples++;
      }
    }
    if (_active != null) {
      final current = valid[_active!.code];
      // Hysteresis: keep an existing cue until below 60% of its entry threshold.
      if (current != null &&
          current.severity >= 0.6 &&
          nowMs - _shownAt < displayMs) {
        return;
      }
      _clearActive(nowMs);
    }
    if (nowMs < _nextMessageAt) return;
    final eligible =
        valid.values.where((cue) {
          final evidence = _evidence[cue.code];
          return evidence != null &&
              evidence.samples >= minimumSamples &&
              captureMs - evidence.startMs >= persistenceMs &&
              nowMs >= (_regionReadyAt[cue.region] ?? 0);
        }).toList()..sort((a, b) {
          final priority = b.severity.compareTo(a.severity);
          return priority != 0 ? priority : a.code.compareTo(b.code);
        });
    if (eligible.isEmpty) return;
    _active = eligible.first;
    _presentations++;
    _shownAt = nowMs;
    _nextMessageAt = nowMs + cooldownMs;
  }
}
