import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Framing tries counted on the phone (`calibration-v1`), for the pilot:
/// how often a student reaches measurable framing without giving up.
class CalibrationCount {
  const CalibrationCount(this.attempts, this.calibrated);
  static const none = CalibrationCount(0, 0);
  static const max = 1000;
  final int attempts, calibrated;
  bool get isEmpty => attempts == 0;

  Map<String, int> toJson() => {'attempts': attempts, 'calibrated': calibrated};

  /// Null for anything that is not a valid count.
  static CalibrationCount? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final attempts = json['attempts'];
    final calibrated = json['calibrated'];
    if (attempts is! int ||
        calibrated is! int ||
        attempts < 1 ||
        attempts > max ||
        calibrated < 0 ||
        calibrated > attempts) {
      return null;
    }
    return CalibrationCount(attempts, calibrated);
  }
}

/// Pending framing tries of one account on this phone. A saved practice
/// carries them to the server and they are cleared once it is saved, so the
/// tries of a student who gave up still count. Telemetry never gets in the
/// way of dancing: every failure here is ignored.
class CalibrationLog {
  CalibrationLog(this.file);
  final File file;

  static Future<CalibrationLog> open(String accountScope) async =>
      CalibrationLog(
        File(
          '${(await getApplicationSupportDirectory()).path}/calibration-v1/'
          '${sha256.convert(utf8.encode(accountScope))}.json',
        ),
      );

  Future<CalibrationCount> pending() async {
    try {
      if (!await file.exists()) return CalibrationCount.none;
      return CalibrationCount.tryParse(jsonDecode(await file.readAsString())) ??
          CalibrationCount.none;
    } catch (_) {
      return CalibrationCount.none;
    }
  }

  Future<void> record({required bool calibrated}) async {
    final now = await pending();
    if (now.attempts >= CalibrationCount.max) return;
    await _write(
      CalibrationCount(now.attempts + 1, now.calibrated + (calibrated ? 1 : 0)),
    );
  }

  /// Forget the tries a saved practice took with it; later ones stay.
  Future<void> clear(CalibrationCount sent) async {
    final now = await pending();
    final attempts = now.attempts - sent.attempts;
    await _write(
      attempts <= 0
          ? CalibrationCount.none
          : CalibrationCount(
              attempts,
              (now.calibrated - sent.calibrated).clamp(0, attempts),
            ),
    );
  }

  Future<void> _write(CalibrationCount count) async {
    try {
      if (count.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(count.toJson()), flush: true);
    } catch (_) {}
  }
}

/// One framing try of a camera screen: opens on positioning, closes once
/// (calibrated, or given up when the screen goes away first).
class CalibrationAttempt {
  CalibrationAttempt(this.onClosed);
  final void Function(bool calibrated) onClosed;
  bool _open = false;

  void start() => _open = true;

  void calibrated() => _close(true);

  void abandoned() => _close(false);

  void _close(bool calibrated) {
    if (!_open) return;
    _open = false;
    onClosed(calibrated);
  }
}
