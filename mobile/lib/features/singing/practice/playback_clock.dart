/// Where the guide audio is now, between the player's coarse reports.
///
/// Players report their position a few times per second; in between, time
/// runs at the wall-clock rate. A report that jumps backwards or more than
/// a second forward (a seek, a stall) replaces the estimate at once.
class PlaybackClock {
  int? _positionMs, _reportedAtMs;
  bool _playing = false;

  void report({
    required int positionMs,
    required int nowMs,
    required bool playing,
  }) {
    _playing = playing;
    if (_positionMs == null || positionMs != _positionMs) {
      _positionMs = positionMs;
      _reportedAtMs = nowMs;
    }
  }

  /// Estimated position at [nowMs]; null before the first report or paused.
  int? positionAt(int nowMs) {
    final position = _positionMs, reportedAt = _reportedAtMs;
    if (position == null || reportedAt == null) return null;
    if (!_playing) return position;
    final elapsed = nowMs - reportedAt;
    // A player that stopped reporting for long is stuck: do not run ahead.
    if (elapsed < 0 || elapsed > 1500) return position;
    return position + elapsed;
  }

  void reset() {
    _positionMs = null;
    _reportedAtMs = null;
    _playing = false;
  }
}
