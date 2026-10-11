import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/dance_game.dart';
import '../pose/pose_measurements.dart';
import 'game_sounds.dart';

/// Hands-free screens stay vertical: an auto-rotation on a stand would
/// recalibrate the camera mid-song and reflow the layout.
Future<void> lockPortrait() =>
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

/// Back to the orientations the app allows elsewhere.
Future<void> unlockOrientation() =>
    SystemChrome.setPreferredOrientations(const []);

/// Hands-free positioning text shared by the game and the move drill.
String positioningGuidance(PoseMeasurements? measurements, String? poseError) {
  if (poseError != null) return poseError;
  if (measurements == null) {
    return 'Apoya el teléfono vertical a la altura de la cadera y aléjate '
        '2–3 m hasta verte de cuerpo entero. El baile empieza solo.';
  }
  return switch (measurements.quality) {
    PoseQuality.noPerson => 'Colócate frente a la cámara.',
    PoseQuality.bodyNotVisible =>
      'Que se vean cabeza, brazos y piernas completos.',
    PoseQuality.lowConfidence => 'Necesitas más luz.',
    PoseQuality.tooClose => 'Aléjate un poco.',
    PoseQuality.tooFar => 'Acércate un poco.',
    PoseQuality.ready =>
      'Quieto un momento… '
          '${(measurements.calibrationProgress * 100).round()} %',
  };
}

class GameBanner extends StatelessWidget {
  const GameBanner({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 18),
    ),
  );
}

Color ratingColor(MoveRating? rating) => switch (rating) {
  MoveRating.perfect => Colors.amber,
  MoveRating.great => Colors.lightGreenAccent,
  MoveRating.good => Colors.lightBlueAccent,
  MoveRating.miss => Colors.redAccent,
  null => Colors.white70,
};

class RatingLabel extends StatelessWidget {
  const RatingLabel({required this.move, super.key});
  final RatedMove move;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      move.rating?.label ?? 'SIN MEDIR',
      style: TextStyle(
        color: ratingColor(move.rating),
        fontSize: move.rating == null ? 28 : 48,
        fontWeight: FontWeight.w900,
        shadows: const [Shadow(blurRadius: 8)],
      ),
    ),
  );
}

/// `m:ss` of a video position.
String clockTime(int ms) {
  final seconds = ms ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Turns the countdown and rating cues on or off (shared by game and drill).
class SoundToggle extends StatelessWidget {
  const SoundToggle({required this.onPressed, super.key});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: GameSounds.enabled ? 'Silenciar sonidos' : 'Activar sonidos',
    color: Colors.white,
    onPressed: onPressed,
    icon: Icon(GameSounds.enabled ? Icons.volume_up : Icons.volume_off),
  );
}
