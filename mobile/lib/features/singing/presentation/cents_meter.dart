import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../practice/vocal_practice.dart';

/// A needle from a semitone low to a semitone high: green in tune, amber
/// close. It moves with every sample, while the words above it change slowly.
class CentsMeter extends StatelessWidget {
  const CentsMeter({required this.cents, super.key});

  /// Distance to the note; null hides the needle (no voice).
  final ValueListenable<double?> cents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Distancia a la nota: a la izquierda baja, a la derecha alta',
      child: SizedBox(
        height: 48,
        child: CustomPaint(
          size: Size.infinite,
          painter: _MeterPainter(
            cents,
            theme.colorScheme,
            theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.cents, this.colors, this.labels) : super(repaint: cents);

  final ValueListenable<double?> cents;
  final ColorScheme colors;
  final TextStyle labels;

  static const range = 100.0;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.width / 2;
    double x(double value) =>
        middle + value.clamp(-range, range) / range * (middle - 8);
    const top = 6.0, height = 14.0;
    RRect band(double from, double to) => RRect.fromLTRBR(
      x(from),
      top,
      x(to),
      top + height,
      const Radius.circular(height / 2),
    );

    canvas.drawRRect(
      band(-range, range),
      Paint()..color = colors.outlineVariant.withValues(alpha: 0.5),
    );
    canvas.drawRRect(
      band(-VocalPractice.closeCents, VocalPractice.closeCents),
      Paint()..color = Colors.amber.withValues(alpha: 0.45),
    );
    canvas.drawRRect(
      band(-VocalPractice.inTuneCents, VocalPractice.inTuneCents),
      Paint()..color = Colors.green.withValues(alpha: 0.55),
    );
    canvas.drawLine(
      Offset(middle, top - 3),
      Offset(middle, top + height + 3),
      Paint()
        ..color = colors.onSurface
        ..strokeWidth = 2,
    );

    void label(String text, Alignment side) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labels),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = switch (side) {
        Alignment.centerLeft => 0.0,
        Alignment.centerRight => size.width - painter.width,
        _ => middle - painter.width / 2,
      };
      painter.paint(canvas, Offset(left, top + height + 4));
    }

    // The pitch, not an order: "Bajo" means the voice is under the note.
    label('Bajo', Alignment.centerLeft);
    label('Afinado', Alignment.center);
    label('Alto', Alignment.centerRight);

    final value = cents.value;
    if (value == null) return;
    final color = switch (gradeOf(value)) {
      NoteGrade.inTune => Colors.green.shade800,
      NoteGrade.close => Colors.amber.shade900,
      NoteGrade.off => colors.error,
    };
    canvas.drawCircle(
      Offset(x(value), top + height / 2),
      height * 0.75,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _MeterPainter old) =>
      old.cents != cents || old.colors != colors;
}
