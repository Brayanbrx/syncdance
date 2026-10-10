import 'package:flutter/material.dart';

import '../comparison/follow_mode.dart';
import '../comparison/session_summary.dart';

class SessionSummaryPanel extends StatelessWidget {
  const SessionSummaryPanel({
    required this.summary,
    required this.referenceVersion,
    super.key,
  });
  final SessionSummary summary;
  final int referenceVersion;

  String _seconds(int ms) => (ms / 1000).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen de práctica',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            '${summary.reachedVideoEnd ? 'Fin del video' : 'Práctica finalizada'} · referencia v$referenceVersion',
          ),
          Text(
            '${summary.followMode == FollowMode.mirror ? 'Seguido como espejo' : 'Seguido con los mismos lados'}'
            '${summary.playbackSpeed == 1.0 ? '' : ' · velocidad ${summary.playbackSpeed.toString().replaceAll('.', ',')}×'}',
          ),
          const SizedBox(height: 12),
          Text(
            summary.score == null
                ? 'Similitud: —. Sin comparaciones válidas.'
                : 'Similitud en tramos evaluados: ${summary.score!.toStringAsFixed(0)}/100',
          ),
          if (summary.meanErrorDegrees != null)
            Text(
              'Diferencia media: ${summary.meanErrorDegrees!.toStringAsFixed(1)}°',
            ),
          if (summary.meanPositionError != null) ...[
            Text(
              'Diferencia de posiciones: ${summary.meanPositionError!.toStringAsFixed(2)} largos de torso',
            ),
            Text(
              'Ángulos: ${summary.angleScore!.toStringAsFixed(0)}/100 · Posiciones: ${summary.positionScore!.toStringAsFixed(0)}/100',
            ),
          ],
          Text(
            'Cobertura estimada: ${(summary.coverage * 100).toStringAsFixed(1)} %',
          ),
          Text(
            '${_seconds(summary.evaluatedMs)} de ${_seconds(summary.durationMs)} s de la rutina con evidencia.',
          ),
          const Text(
            'Los tramos sin datos no cuentan como cero. Repetir un tramo conserva su primera comparación válida.',
          ),
          if (summary.coverage < 1)
            const Text(
              'Resultado parcial: interpreta la similitud junto con la cobertura.',
            ),
          const SizedBox(height: 12),
          const Text('Avisos más frecuentes'),
          if (summary.feedback.isEmpty)
            const Text(
              'Sin avisos persistentes registrados. Esto no implica ausencia de errores.',
            ),
          for (final cue in summary.feedback.take(3))
            Text('${cue.message} · ${cue.count} avisos'),
          const Text(
            'Se cuentan avisos mostrados, no todos los errores ni su duración.',
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Por tramos de video'),
            children: [
              for (final segment in summary.segments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${_seconds(segment.startMs)}–${_seconds(segment.endMs)} s: '
                    '${segment.score == null ? '—' : '${segment.score!.toStringAsFixed(0)}/100'} · '
                    '${(segment.coverage * 100).toStringAsFixed(1)} % evaluado',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Similitud experimental de ángulos y posiciones, con igual peso. Al servidor solo llega este resumen, nunca imágenes ni poses.',
          ),
        ],
      ),
    ),
  );
}
