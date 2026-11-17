import 'dart:typed_data';

import 'yin.dart';

/// What the microphone heard at one moment. [midi] is null when there was no
/// voice (silence, breath, consonant): never zero.
class PitchSample {
  PitchSample(this.timeMs, this.midi, this.confidence) {
    if (timeMs < 0 || !(midi?.isFinite ?? true) || !confidence.isFinite) {
      throw ArgumentError('invalid pitch sample');
    }
  }

  /// Milliseconds since the capture started (monotonic).
  final int timeMs;
  final double? midi;
  final double confidence;
}

/// The singing domain never sees the audio plugin: it gets pitch samples.
/// Contract: one capture at a time; `stop` releases the microphone and is safe
/// to call twice; errors arrive through the stream.
abstract class PitchSource {
  /// Asks for the microphone; false when the person refused.
  Future<bool> requestPermission();

  Stream<PitchSample> start();

  Future<void> stop();
}

/// Turns 16-bit little-endian mono PCM chunks into pitch samples, one every
/// [hop] samples. Chunks may split a sample in two; the odd byte waits.
class PcmPitchTracker {
  PcmPitchTracker({YinPitchDetector? detector, this.hop = 512})
    : detector = detector ?? YinPitchDetector() {
    _ring = Float64List(this.detector.frameLength);
    _window = Float64List(this.detector.frameLength);
  }

  final YinPitchDetector detector;
  final int hop;

  /// The latest samples, written in a circle; copied in order into [_window]
  /// only when a detection is due.
  late final Float64List _ring, _window;
  int _write = 0, _filled = 0, _sinceLast = 0, _total = 0;
  int? _pendingByte;

  List<PitchSample> add(List<int> bytes) {
    final out = <PitchSample>[];
    var index = 0;
    if (_pendingByte != null && bytes.isNotEmpty) {
      _push(_sample(_pendingByte!, bytes[0]), out);
      _pendingByte = null;
      index = 1;
    }
    for (; index + 1 < bytes.length; index += 2) {
      _push(_sample(bytes[index], bytes[index + 1]), out);
    }
    if (index < bytes.length) _pendingByte = bytes[index];
    return out;
  }

  static double _sample(int low, int high) {
    var value = (high << 8) | (low & 0xff);
    if (value >= 0x8000) value -= 0x10000;
    return value / 32768.0;
  }

  void _push(double value, List<PitchSample> out) {
    final length = _ring.length;
    _ring[_write] = value;
    _write = (_write + 1) % length;
    if (_filled < length) _filled++;
    _total++;
    _sinceLast++;
    if (_filled == length && _sinceLast >= hop) {
      _sinceLast = 0;
      // Oldest sample first: from the write position to the end, then the start.
      _window.setRange(0, length - _write, _ring, _write);
      _window.setRange(length - _write, length, _ring);
      final estimate = detector.detect(_window);
      // The window's middle is when that pitch was sung.
      final centerMs = ((_total - length / 2) * 1000 / detector.sampleRate)
          .round();
      out.add(
        PitchSample(
          centerMs < 0 ? 0 : centerMs,
          estimate?.midi,
          estimate?.confidence ?? 0,
        ),
      );
    }
  }
}
