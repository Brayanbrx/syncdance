import 'package:flutter/material.dart';

import '../practice/vocal_practice.dart';
import '../reference/pitch_reference.dart';

/// The result of one singing practice: a few numbers and note by note, with
/// a way to practice each note that was not in tune.
class VocalSummaryPanel extends StatelessWidget {
  const VocalSummaryPanel({
    required this.summary,
    required this.onAgain,
    required this.onDone,
    this.onPractice,
    this.busy = false,
    super.key,
  });

  final VocalSummary summary;
  final VoidCallback onAgain, onDone;

  /// Drill the note at this position of the melody.
  final ValueChanged<int>? onPractice;
  final bool busy;

  static String percent(int? value) => value == null ? '—' : '$value %';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          summary.reachedEnd ? 'Terminaste' : 'Práctica interrumpida',
          style: theme.textTheme.titleLarge,
        ),
        Text(
          '${modeLabel(summary.mode)} · ${speedLabel(summary.speed)}',
          style: theme.textTheme.bodySmall,
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
        Text(advice(summary)),
        const SizedBox(height: 16),
        if (summary.notes.any((n) => n.heard)) ...[
          Text('Nota por nota', style: theme.textTheme.titleMedium),
          for (var i = 0; i < summary.notes.length; i++)
            if (summary.notes[i].heard)
              _NoteTile(
                summary.notes[i],
                onPractice:
                    onPractice == null ||
                        busy ||
                        summary.notes[i].grade == NoteGrade.inTune
                    ? null
                    : () => onPractice!(i),
              ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : onAgain,
          icon: const Icon(Icons.replay),
          label: const Text('Cantar otra vez'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: busy ? null : onDone,
          child: const Text('Volver'),
        ),
      ],
    );
  }

  static String advice(VocalSummary summary) {
    if (summary.tuning == null) {
      return 'No se oyó tu voz. Acerca el micrófono, canta un poco más fuerte '
          'y revisa que los audífonos no tapen el micrófono del teléfono.';
    }
    final sung = summary.notes.where((n) => n.sung).length;
    final parts = <String>[
      if (summary.inTune == sung)
        'Todas las notas que cantaste estuvieron afinadas.'
      else ...[
        if (summary.close > 0)
          '${summary.close} '
              '${summary.close == 1 ? 'nota quedó' : 'notas quedaron'} '
              'cerca, pero se oyen un poco fuera.',
        if (summary.outOfTune > 0)
          '${summary.outOfTune} '
              '${summary.outOfTune == 1 ? 'nota quedó desafinada' : 'notas quedaron desafinadas'}.',
        'Toca «Practicar» en una nota para repetirla sola, despacio.',
      ],
      if (summary.missed > 0)
        'No se oyó tu voz en ${summary.missed} '
            '${summary.missed == 1 ? 'nota' : 'notas'}: respira antes y entra '
            'a tiempo.',
    ];
    return parts.join(' ');
  }
}

String modeLabel(PracticeMode mode) => switch (mode) {
  PracticeMode.echo => 'Escucha y repite',
  PracticeMode.together => 'Con la guía',
  PracticeMode.drill => 'Una nota',
};

String speedLabel(double speed) => speed == 1
    ? 'velocidad normal'
    : 'a ${speed.toString().replaceAll('.', ',')}×';

/// What a sung note sounded like, in words for the student.
(IconData, String) gradeText(NoteResult result) {
  final cents = result.cents;
  return switch ((result.sung, result.grade, cents)) {
    (false, _, _) => (Icons.mic_off_outlined, 'No se oyó tu voz'),
    (true, NoteGrade.inTune, final c?) => (
      Icons.check_circle,
      'Afinada (${_signed(c)} cents)',
    ),
    (true, NoteGrade.close, final c?) when c < 0 => (
      Icons.north_east,
      'Casi: un poco baja (${_signed(c)} cents), sube un poquito',
    ),
    (true, NoteGrade.close, final c?) => (
      Icons.south_east,
      'Casi: un poco alta (${_signed(c)} cents), baja un poquito',
    ),
    (true, NoteGrade.off, final c?) when c < 0 => (
      Icons.arrow_upward,
      'Baja (${_signed(c)} cents): sube',
    ),
    (true, NoteGrade.off, final c?) => (
      Icons.arrow_downward,
      'Alta (${_signed(c)} cents): baja',
    ),
    _ => (Icons.help_outline, ''),
  };
}

String _signed(double cents) {
  final value = cents.round();
  return value > 0 ? '+$value' : '$value';
}

Color? gradeColor(NoteResult result) => switch (result.grade) {
  NoteGrade.inTune => Colors.green.shade700,
  NoteGrade.close => Colors.amber.shade800,
  _ => null,
};

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
  const _NoteTile(this.result, {this.onPractice});
  final NoteResult result;
  final VoidCallback? onPractice;

  @override
  Widget build(BuildContext context) {
    final note = result.note;
    final (icon, text) = gradeText(result);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: gradeColor(result)),
      title: Text('${solfege(note.midi)} (${note.name})'),
      subtitle: Text('$text · ${(note.startMs / 1000).toStringAsFixed(1)} s'),
      trailing: onPractice == null
          ? null
          : TextButton(
              onPressed: onPractice,
              child: Text('Practicar ${solfege(note.midi)}'),
            ),
    );
  }
}

/// The note drill's attempts, one after the other.
class DrillPanel extends StatelessWidget {
  const DrillPanel({
    required this.note,
    required this.attempts,
    required this.onAgain,
    required this.onBack,
    this.busy = false,
    super.key,
  });

  final SungNote note;
  final List<NoteResult> attempts;
  final VoidCallback onAgain, onBack;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inTune = attempts.where((a) => a.grade == NoteGrade.inTune).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Practicar ${solfege(note.midi)} (${note.name})',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          attempts.isEmpty
              ? 'No llegaste a cantar ningún intento.'
              : inTune == attempts.length
              ? '¡Afinada en todos los intentos! Vuelve a la canción completa.'
              : 'Afinada en $inTune de ${attempts.length} intentos. Escucha '
                    'la nota, imagínala y entra suave, sin empujar.',
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < attempts.length; i++)
          Builder(
            builder: (context) {
              final (icon, text) = gradeText(attempts[i]);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: gradeColor(attempts[i])),
                title: Text('Intento ${i + 1}'),
                subtitle: Text(text),
              );
            },
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : onAgain,
          icon: const Icon(Icons.replay),
          label: const Text('Practicar otra vez'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: busy ? null : onBack,
          child: const Text('Volver al resumen'),
        ),
      ],
    );
  }
}
