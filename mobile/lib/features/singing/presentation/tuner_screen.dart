import 'dart:async';

import 'package:flutter/material.dart';

import '../pitch/adapters/record_pitch_source.dart';
import '../pitch/pitch_source.dart';
import '../reference/pitch_reference.dart';
import 'cents_meter.dart';

/// "Afinador": sing any note and hold it; the needle shows how close it is
/// to the nearest note. A warm-up, and a check that the microphone hears the
/// student before a practice. Nothing is recorded or kept.
class TunerScreen extends StatefulWidget {
  const TunerScreen({this.createSource, super.key});

  final PitchSource Function()? createSource;

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> with WidgetsBindingObserver {
  PitchSource? _source;
  StreamSubscription<PitchSample>? _samples;
  bool _listening = false, _starting = false;
  String? _message;
  double? _note;
  final _cents = ValueNotifier<double?>(null);
  final _recent = <double>[];
  int _silent = 0;

  /// Samples without voice (~600 ms) before the note clears.
  static const _forgetAfter = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop(notify: false));
    _cents.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _message = null;
    });
    final source = (widget.createSource ?? RecordPitchSource.new)();
    try {
      final allowed = await source.requestPermission();
      if (!mounted) {
        await source.stop();
        return;
      }
      if (!allowed) {
        unawaited(source.stop());
        setState(() {
          _starting = false;
          _message =
              'Sin permiso de micrófono no se puede oír tu voz. Actívalo en '
              'los ajustes del teléfono.';
        });
        return;
      }
      _source = source;
      _samples = source.start().listen(
        _onSample,
        onError: (Object _) {
          _message = 'El micrófono dejó de responder.';
          unawaited(_stop());
        },
      );
      setState(() {
        _starting = false;
        _listening = true;
      });
    } catch (_) {
      await source.stop();
      if (mounted) {
        setState(() {
          _starting = false;
          _message = 'No se pudo abrir el micrófono.';
        });
      }
    }
  }

  Future<void> _stop({bool notify = true}) async {
    final samples = _samples, source = _source;
    _samples = null;
    _source = null;
    _recent.clear();
    await samples?.cancel();
    await source?.stop();
    if (notify && mounted) {
      setState(() {
        _listening = false;
        _note = null;
      });
      _cents.value = null;
    }
  }

  void _onSample(PitchSample sample) {
    final midi = sample.midi;
    if (midi == null) {
      if (++_silent >= _forgetAfter && _note != null) {
        _recent.clear();
        _cents.value = null;
        setState(() => _note = null);
      }
      return;
    }
    _silent = 0;
    _recent.add(midi);
    if (_recent.length > 5) _recent.removeAt(0);
    final sorted = [..._recent]..sort();
    final centered = sorted[sorted.length >> 1];
    final note = centered.roundToDouble();
    _cents.value = (centered - note) * 100;
    if (note != _note) setState(() => _note = note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = _note;
    return Scaffold(
      appBar: AppBar(title: const Text('Afinador')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_message != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
              ),
            const Text(
              'Canta una nota cómoda y sostenla con una vocal abierta, como '
              '«a». Si la aguja queda en el verde, estás afinado. Úsalo para '
              'calentar y para comprobar que el micrófono te oye.',
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                note == null
                    ? (_listening ? 'Canta una nota…' : '—')
                    : solfege(note),
                style: theme.textTheme.displayMedium,
              ),
            ),
            Center(
              child: Text(
                note == null ? ' ' : noteName(note),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 24),
            CentsMeter(cents: _cents),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _starting
                  ? null
                  : _listening
                  ? () => _stop()
                  : _start,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Text(_listening ? 'Detener' : 'Empezar a escuchar'),
            ),
            const SizedBox(height: 8),
            Text(
              'Tu voz se mide en este teléfono y no se graba ni se envía.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
