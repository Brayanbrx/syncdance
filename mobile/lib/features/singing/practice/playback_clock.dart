/// Where the guide audio is now, between the player's coarse reports.
///
/// Players report their position a few times per second; in between, time
/// runs at the wall-clock rate times [speed]. A report that jumps backwards
/// or more than a second forward (a seek, a stall) replaces the estimate at
/// once.
class PlaybackClock {
  int? _positionMs, _reportedAtMs;
  bool _playing = false;

  /// Playback rate: 0.5 is half as fast, with the same pitch.
  double speed = 1.0;

  void report({
    required int positionMs,
    required int nowMs,
    required bool playing,
  }) {
    // Starting to play where it was sought counts from now, not from the
    // seek: otherwise the estimate runs ahead by the time in between.
    if (_positionMs == null ||
        positionMs != _positionMs ||
        (playing && !_playing)) {
      _positionMs = positionMs;
      _reportedAtMs = nowMs;
    }
    _playing = playing;
  }

  /// Estimated position at [nowMs]; null before the first report or paused.
  int? positionAt(int nowMs) {
    final position = _positionMs, reportedAt = _reportedAtMs;
    if (position == null || reportedAt == null) return null;
    if (!_playing) return position;
    final elapsed = nowMs - reportedAt;
    // A player that stopped reporting for long is stuck: do not run ahead.
    if (elapsed < 0 || elapsed > 1500) return position;
    return position + (elapsed * speed).round();
  }

  void reset() {
    _positionMs = null;
    _reportedAtMs = null;
    _playing = false;
  }
}
