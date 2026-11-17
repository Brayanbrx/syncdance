import 'package:flutter/material.dart';

import '../practice/vocal_practice.dart';
import '../reference/pitch_reference.dart';

/// A point the student sang, in guide time.
class TrailPoint {
  const TrailPoint(this.atMs, this.midi, this.onPitch);
  final int atMs;
  final double midi;
  final bool onPitch;
}

/// The melody as bars that scroll toward a "now" line, with the student's
/// pitch drawn as dots: higher on screen is a higher note.
class PitchRoll extends CustomPainter {
  PitchRoll({
    required this.reference,
    required this.now,
    required this.trail,
    required this.colors,
  }) : super(repaint: now);

  final PitchReference reference;

  /// Guide time being sung (already latency-corrected).
  final ValueNotifier<int> now;
  final List<TrailPoint> trail;
  final ColorScheme colors;

  static const pastMs = 2500, futureMs = 3500;

  @override
  void paint(Canvas canvas, Size size) {
    final (lowest, highest) = reference.range;
    final low = lowest.floorToDouble() - 2, high = highest.ceilToDouble() + 2;
    final row = size.height / (high - low);
    double y(double midi) => size.height - (midi.clamp(low, high) - low) * row;
    final start = now.value - pastMs;
    final scale = size.width / (pastMs + futureMs);
    double x(int ms) => (ms - start) * scale;

    final grid = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var midi = low; midi <= high; midi++) {
      canvas.drawLine(Offset(0, y(midi)), Offset(size.width, y(midi)), grid);
    }

    for (final note in reference.notes) {
      if (note.endMs < start || note.startMs > now.value + futureMs) continue;
      final current = note.startMs <= now.value && now.value < note.endMs;
      final past = note.endMs <= now.value;
      final rect = RRect.fromLTRBR(
        x(note.startMs),
        y(note.midi) - row * 0.35,
        x(note.endMs),
        y(note.midi) + row * 0.35,
        Radius.circular(row * 0.35),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = past
              ? colors.outline.withValues(alpha: 0.35)
              : current
              ? colors.primary
              : colors.primary.withValues(alpha: 0.45),
      );
      if (rect.width > 28 && row > 10) {
        final label = TextPainter(
          text: TextSpan(
            text: solfege(note.midi),
            style: TextStyle(
              color: current ? colors.onPrimary : colors.onSurface,
              fontSize: (row * 0.55).clamp(9.0, 14.0),
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: rect.width - 8);
        label.paint(
          canvas,
          Offset(rect.left + 6, rect.center.dy - label.height / 2),
        );
      }
    }

    canvas.drawLine(
      Offset(x(now.value), 0),
      Offset(x(now.value), size.height),
      Paint()
        ..color = colors.onSurface.withValues(alpha: 0.6)
        ..strokeWidth = 2,
    );

    for (final point in trail) {
      if (point.atMs < start || point.atMs > now.value) continue;
      canvas.drawCircle(
        Offset(x(point.atMs), y(point.midi)),
        3.5,
        Paint()..color = point.onPitch ? Colors.green : colors.tertiary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PitchRoll old) =>
      old.reference != reference || old.colors != colors;
}

/// Words for the singer: short, about one thing.
String cueText(VocalCue? cue) => switch (cue) {
  VocalCue.higher => 'Sube un poco',
  VocalCue.lower => 'Baja un poco',
  VocalCue.onPitch => '¡Afinado!',
  null => 'Canta con la guía',
};
