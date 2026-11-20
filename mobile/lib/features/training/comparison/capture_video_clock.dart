/// Binds camera timestamps to the video position at capture time.
/// Retains only small records, never camera buffers. All times are monotonic ms.
///
/// The player reports its position about every 100 ms; between reports the
/// position runs on at the playback speed, so a frame is bound to where the
/// video is when it is captured, not where it was at the last report (up to
/// 100 ms behind, half of the matching window).
class CaptureVideoClock {
  final _pending = <int, ({int videoMs, int capturedAt})>{};
  int? _position, _reportedAt;
  bool _playing = false;
  double _speed = 1.0;
  int? _endedAt;

  void invalidate() {
    _pending.clear();
    _playing = false;
    _position = null;
    _reportedAt = null;
    _endedAt = null;
  }

  /// The video reached its end: no new frame is bound, but the frames bound
  /// before it still resolve for [maxPendingMs], while their pose arrives.
  void end({required int nowMs}) {
    _playing = false;
    _endedAt = nowMs;
  }

  /// How long a bound frame waits for its pose.
  static const maxPendingMs = 500;

  void report({
    required int videoMs,
    required int nowMs,
    required bool playing,
    double speed = 1.0,
  }) {
    if (!playing) {
      invalidate();
      return;
    }
    if (speed.isFinite && speed > 0) _speed = speed;
    _endedAt = null;
    if (_position != videoMs) {
      if (_position != null &&
          (videoMs < _position! || videoMs - _position! > 500)) {
        _pending.clear();
      }
      _reportedAt = nowMs;
      _position = videoMs;
    }
    _playing = true;
  }

  void capture({required int timestampMs, required int nowMs}) {
    if (!_playing || _reportedAt == null || nowMs - _reportedAt! > 250) return;
    // Never further than the freshness limit above (250 ms of wall time).
    final elapsed = ((nowMs - _reportedAt!) * _speed).round();
    _pending[timestampMs] = (
      videoMs: _position! + (elapsed < 0 ? 0 : elapsed),
      capturedAt: nowMs,
    );
    while (_pending.length > 64) {
      _pending.remove(_pending.keys.first);
    }
  }

  int? resolve({required int timestampMs, required int nowMs}) {
    final sample = _pending.remove(timestampMs);
    if (sample == null || nowMs - sample.capturedAt > maxPendingMs) {
      return null;
    }
    final ended = _endedAt;
    if (ended != null) {
      return nowMs - ended <= maxPendingMs ? sample.videoMs : null;
    }
    if (!_playing || _reportedAt == null || nowMs - _reportedAt! > 250) {
      return null;
    }
    return sample.videoMs;
  }
}
