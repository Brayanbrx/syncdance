/// Binds camera timestamps to the last reported video position at capture time.
/// Retains only small records, never camera buffers. All times are monotonic ms.
class CaptureVideoClock {
  final _pending = <int, ({int videoMs, int capturedAt})>{};
  int? _position, _reportedAt;
  bool _playing = false;

  void invalidate() {
    _pending.clear();
    _playing = false;
    _position = null;
    _reportedAt = null;
  }

  void report({
    required int videoMs,
    required int nowMs,
    required bool playing,
  }) {
    if (!playing) {
      invalidate();
      return;
    }
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
    _pending[timestampMs] = (videoMs: _position!, capturedAt: nowMs);
    while (_pending.length > 64) {
      _pending.remove(_pending.keys.first);
    }
  }

  int? resolve({required int timestampMs, required int nowMs}) {
    final sample = _pending.remove(timestampMs);
    if (!_playing ||
        sample == null ||
        nowMs - sample.capturedAt > 500 ||
        _reportedAt == null ||
        nowMs - _reportedAt! > 250) {
      return null;
    }
    return sample.videoMs;
  }
}
