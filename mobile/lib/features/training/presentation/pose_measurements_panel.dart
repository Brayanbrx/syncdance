import 'package:flutter/material.dart';

import '../pose/pose_measurements.dart';
import 'body_features_panel.dart';

class PoseMeasurementsPanel extends StatelessWidget {
  const PoseMeasurementsPanel({
    required this.measurements,
    required this.onRecalibrate,
    super.key,
  });
  final PoseMeasurements measurements;
  final VoidCallback onRecalibrate;

  @override
  Widget build(BuildContext context) {
    final message = switch (measurements.quality) {
      PoseQuality.noPerson => 'Colócate frente a la cámara.',
      PoseQuality.bodyNotVisible =>
        'Muestra cabeza, brazos y piernas completos.',
      PoseQuality.lowConfidence =>
        'Mejora la iluminación y deja las articulaciones visibles.',
      PoseQuality.tooClose =>
        'Deja más espacio alrededor del cuerpo; aléjate un poco.',
      PoseQuality.tooFar =>
        'Acércate un poco manteniendo todo el cuerpo visible.',
      PoseQuality.ready =>
        measurements.canMeasure
            ? 'Encuadre listo para medir.'
            : 'Mantente quieto y de frente para calibrar el encuadre.',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        if (measurements.quality == PoseQuality.ready &&
            !measurements.canMeasure)
          Padding(
            padding: const EdgeInsets.all(8),
            child: LinearProgressIndicator(
              value: measurements.calibrationProgress,
            ),
          ),
        if (measurements.canMeasure) ...[
          BodyFeaturesPanel(angles: measurements.angles),
          TextButton(
            onPressed: onRecalibrate,
            child: const Text('Recalibrar encuadre'),
          ),
        ],
      ],
    );
  }
}
