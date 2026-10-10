import 'package:flutter/material.dart';

import '../../routines/reference/motion_reference.dart';
import '../game/dance_game.dart';
import '../pose/pose_frame.dart';

/// The master pose that represents a move: the counted beat that opens it when
/// the tempo is known (generated coaches land each pose on the beat), otherwise
/// the middle of the move. Null when the master is not drawable in the move.
MotionSample? keySample(MotionReference reference, DanceMove move) {
  final target = reference.metadata.beatGrid != null
      ? move.startMs
      : (move.startMs + move.endMs) ~/ 2;
  MotionSample? best;
  for (final sample in reference.samples) {
    if (sample.timestampMs < move.startMs ||
        sample.timestampMs >= move.endMs ||
        sample.quality != 'SINGLE_PERSON' ||
        sample.normalized.isEmpty) {
      continue;
    }
    if (best == null ||
        (sample.timestampMs - target).abs() <
            (best.timestampMs - target).abs()) {
      best = sample;
    }
  }
  return best;
}

/// The next moves of the song, the imminent one highlighted, so the learner
/// sees each pose before the beat it lands on; a move leaves the strip once it
/// starts. [poses] is aligned with [moves].
class UpcomingMoves extends StatelessWidget {
  const UpcomingMoves({
    required this.moves,
    required this.poses,
    required this.positionMs,
    this.visible = 3,
    this.size = 80,
    super.key,
  });
  final List<DanceMove> moves;
  final List<MotionSample?> poses;
  final int positionMs;
  final int visible;
  final double size;

  @override
  Widget build(BuildContext context) {
    final upcoming = [
      for (var i = 0; i < moves.length; i++)
        if (moves[i].startMs >= positionMs && poses[i] != null) i,
    ].take(visible);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (order, index) in upcoming.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: MovePictogram(
              key: ValueKey('pictogram-$index'),
              sample: poses[index]!,
              highlighted: order == 0,
              size: size,
            ),
          ),
      ],
    );
  }
}

/// Small stick figure of a move, drawn as the master appears in the video
/// (never mirrored): the learner follows it like the coach.
class MovePictogram extends StatelessWidget {
  const MovePictogram({
    required this.sample,
    this.highlighted = false,
    this.size = 80,
    super.key,
  });
  final MotionSample sample;
  final bool highlighted;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: highlighted ? 0.18 : 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: highlighted ? Colors.amber : Colors.white24,
        width: highlighted ? 3 : 1,
      ),
    ),
    child: CustomPaint(
      painter: PictogramPainter(
        sample.normalized,
        highlighted ? Colors.amber : Colors.white70,
      ),
    ),
  );
}

class PictogramPainter extends CustomPainter {
  PictogramPainter(this.points, this.color);
  final Map<Joint, ReferencePoint> points;
  final Color color;

  static const bones = [
    (Joint.leftShoulder, Joint.rightShoulder),
    (Joint.leftHip, Joint.rightHip),
    (Joint.leftShoulder, Joint.leftHip),
    (Joint.rightShoulder, Joint.rightHip),
    (Joint.leftShoulder, Joint.leftElbow),
    (Joint.leftElbow, Joint.leftWrist),
    (Joint.rightShoulder, Joint.rightElbow),
    (Joint.rightElbow, Joint.rightWrist),
    (Joint.leftHip, Joint.leftKnee),
    (Joint.leftKnee, Joint.leftAnkle),
    (Joint.rightHip, Joint.rightKnee),
    (Joint.rightKnee, Joint.rightAnkle),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // body-normalized-v1: hip midpoint at 0, one torso length = 1, image axes
    // (y down). The standard catalog spans x ±1.7 and y -2.15 (hands up) to
    // 1.86 (feet); centre that span and clip whatever a stock video exceeds.
    canvas.clipRect(Offset.zero & size);
    final scale = size.shortestSide / 4.8;
    final origin = size.center(Offset(0, 0.15 * scale));
    Offset at(Joint joint) {
      final p = points[joint]!;
      return origin + Offset(p.x * scale, p.y * scale);
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = size.shortestSide / 16
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in bones) {
      if (points.containsKey(a) && points.containsKey(b)) {
        canvas.drawLine(at(a), at(b), paint);
      }
    }
    if (points.containsKey(Joint.nose)) {
      canvas.drawCircle(
        at(Joint.nose),
        0.3 * scale,
        paint..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(PictogramPainter old) =>
      old.points != points || old.color != color;
}
