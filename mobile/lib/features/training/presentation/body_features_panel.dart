import 'package:flutter/material.dart';

import '../pose/body_features.dart';
import '../pose/pose_frame.dart';

class BodyFeaturesPanel extends StatelessWidget {
  const BodyFeaturesPanel({this.pose, this.angles, super.key})
    : assert(pose != null || angles != null);

  final PoseFrame? pose;
  final Map<BodyAngle, double>? angles;

  @override
  Widget build(BuildContext context) {
    final features = pose == null
        ? null
        : const BodyFeatureExtractor().extract(pose!);
    if (angles == null && features?.pose == null) {
      return const Text(
        'Para medir, muestra ambos hombros y caderas con claridad.',
        textAlign: TextAlign.center,
      );
    }
    final values = angles ?? features!.angles;
    String angle(BodyAngle name) =>
        values[name] == null ? '—' : '${values[name]!.toStringAsFixed(0)}°';
    return Text(
      'Ángulos 2D · Izquierda / Derecha\n'
      'Codos: ${angle(BodyAngle.leftElbow)} / ${angle(BodyAngle.rightElbow)}\n'
      'Hombros: ${angle(BodyAngle.leftShoulder)} / ${angle(BodyAngle.rightShoulder)}\n'
      'Rodillas: ${angle(BodyAngle.leftKnee)} / ${angle(BodyAngle.rightKnee)}\n'
      '— = sin medida válida. No es una puntuación.',
      textAlign: TextAlign.center,
    );
  }
}
