import 'dart:math' as math;
import 'dart:typed_data';

/// A pitch heard in one window of samples. Pitch is a fractional MIDI number
/// (60.0 = C4, 69.0 = A4 = 440 Hz), so one cent is 0.01.
class PitchEstimate {
  const PitchEstimate(this.hz, this.confidence);
  final double hz;

  /// 1 - the YIN dip: near 1 for a clean voice, lower with noise.
  final double confidence;

  double get midi => 69 + 12 * math.log(hz / 440) / math.ln2;
}

/// YIN (de Cheveigné and Kawahara, 2002) over mono samples in [-1, 1].
///
/// Runs on the phone for every window, so it stays plain loops over typed
/// arrays: about 250 000 multiply-adds per window at the default sizes.
/// The server uses pyin on the instructor's voice; both agree within a few
/// cents on a clean voice (see the tests).
class YinPitchDetector {
  YinPitchDetector({
    this.sampleRate = 16000,
    this.windowSize = 1024,
    this.minHz = 65,
    this.maxHz = 1100,
    this.threshold = 0.15,
    this.silenceRms = 0.01,
  }) : maxLag = (sampleRate / minHz).floor(),
       minLag = math.max(2, (sampleRate / maxHz).floor()) {
    _difference = Float64List(maxLag + 2);
  }

  static const version = 'yin-v1';
  final int sampleRate, windowSize, maxLag, minLag;
  final double minHz, maxHz, threshold, silenceRms;
  late final Float64List _difference;

  /// Samples one detection reads: the window plus the longest period.
  int get frameLength => windowSize + maxLag + 1;

  /// Pitch of `samples[offset .. offset + frameLength)`; null when the window
  /// is silent or has no clear period (breath, consonant, noise).
  PitchEstimate? detect(Float64List samples, [int offset = 0]) {
    if (samples.length - offset < frameLength) {
      throw ArgumentError('detect needs $frameLength samples');
    }
    var energy = 0.0;
    for (var j = 0; j < windowSize; j++) {
      final x = samples[offset + j];
      energy += x * x;
    }
    if (math.sqrt(energy / windowSize) < silenceRms) return null;

    final d = _difference;
    d[0] = 1;
    var running = 0.0;
    var found = -1;
    for (var tau = 1; tau <= maxLag; tau++) {
      var sum = 0.0;
      for (var j = 0; j < windowSize; j++) {
        final delta = samples[offset + j] - samples[offset + j + tau];
        sum += delta * delta;
      }
      running += sum;
      // Cumulative mean normalized difference.
      d[tau] = running == 0 ? 1 : sum * tau / running;
      if (found < 0) {
        if (tau >= minLag && d[tau] < threshold) found = tau;
      } else if (d[tau] < d[found]) {
        found = tau; // still going down the first dip under the threshold
      } else {
        break; // past its bottom: longer periods are octaves below
      }
    }
    if (found < 0) return null;
    if (found >= maxLag) found = maxLag - 1;

    // Parabolic interpolation around the dip for sub-sample precision.
    final a = d[found - 1], b = d[found], c = d[found + 1];
    final denominator = a - 2 * b + c;
    final shift = denominator.abs() < 1e-12 ? 0.0 : 0.5 * (a - c) / denominator;
    final period = found + shift.clamp(-0.5, 0.5);
    final hz = sampleRate / period;
    if (!hz.isFinite || hz < minHz || hz > maxHz) return null;
    return PitchEstimate(hz, (1 - b).clamp(0.0, 1.0));
  }
}
