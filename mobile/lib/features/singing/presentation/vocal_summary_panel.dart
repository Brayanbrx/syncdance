import 'package:flutter/material.dart';

import '../practice/vocal_practice.dart';
import '../reference/pitch_reference.dart';

/// The result of one singing practice: a few numbers and note by note.
class VocalSummaryPanel extends StatelessWidget {
  const VocalSummaryPanel({
    required this.summary,
    required this.onAgain,
    required this.onDone,
    super.key,
  });

  final VocalSummary summary;
  final VoidCallback onAgain, onDone;

  static String percent(int? value) => value == null ? '—' : '$value %';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heard = summary.notes.where((n) => n.heard).toList();
    final missed = heard.where((n) => !n.sung).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          summary.reachedEnd ? 'Terminaste' : 'Práctica interrumpida',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Score('General', summary.overall, emphasis: true),
            _Score('Afinación', summary.tuning),
            _Score('Notas cantadas', summary.coverage),
          ],
        ),
        const SizedBox(height: 12),
        Text(_advice(summary, missed)),
        const SizedBox(height: 16),
        if (heard.isNotEmpty) ...[
          Text('Nota por nota', style: theme.textTheme.titleMedium),
          for (final result in heard) _NoteTile(result),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onAgain,
          icon: const Icon(Icons.replay),
          label: const Text('Cantar otra vez'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onDone, child: const Text('Volver')),
      ],
    );
  }

  static String _advice(VocalSummary summary, int missed) {
    if (summary.tuning == null) {
      return 'No se oyó tu voz. Acerca el micrófono, canta un poco más fuerte '
          'y revisa que los audífonos no tapen el micrófono del teléfono.';
    }
    final parts = <String>[
      if (summary.outOfTune == 0)
        'Todas las notas que cantaste estuvieron afinadas.'
      else
        '${summary.outOfTune} '
            '${summary.outOfTune == 1 ? 'nota quedó desafinada' : 'notas quedaron desafinadas'}: '
            'escucha la guía y repítelas despacio.',
      if (missed > 0)
        'No se oyó tu voz en $missed '
            '${missed == 1 ? 'nota' : 'notas'}: respira antes y entra con la guía.',
    ];
    return parts.join(' ');
  }
}

class _Score extends StatelessWidget {
  const _Score(this.label, this.value, {this.emphasis = false});
  final String label;
  final int? value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            VocalSummaryPanel.percent(value),
            style: emphasis
                ? theme.textTheme.headlineMedium
                : theme.textTheme.titleLarge,
          ),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile(this.result);
  final NoteResult result;

  @override
  Widget build(BuildContext context) {
    final note = result.note;
    final cents = result.cents;
    final inTune = result.inTuneWithin(VocalPractice.centThreshold);
    final (icon, text) = switch ((result.sung, inTune, cents)) {
      (false, _, _) => (Icons.mic_off_outlined, 'No se oyó tu voz'),
      (true, true, _) => (Icons.check_circle, 'Afinada'),
      (true, false, final c?) when c < 0 => (
        Icons.arrow_upward,
        'Un poco baja (${c.round()} cents): sube',
      ),
      (true, false, final c?) => (
        Icons.arrow_downward,
        'Un poco alta (+${c.round()} cents): baja',
      ),
      _ => (Icons.help_outline, ''),
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: inTune == true ? Colors.green.shade700 : null),
      title: Text('${solfege(note.midi)} (${note.name})'),
      subtitle: Text(text),
      trailing: Text('${(note.startMs / 1000).toStringAsFixed(1)} s'),
    );
  }
}
