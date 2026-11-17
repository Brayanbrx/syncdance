import 'dart:async';

import 'package:record/record.dart';

import '../pitch_source.dart';

/// Microphone through the `record` plugin: 16 kHz mono PCM, no processing.
///
/// Echo cancellation, noise suppression and automatic gain are off: they bend
/// a sung note. The voice-recognition source is the least processed one that
/// every Android phone offers. Bluetooth is left alone, so wireless headphones
/// keep playing the guide in good quality while the phone's own microphone
/// listens.
///
/// One capture per source: the plugin creates a native recorder as soon as
/// [AudioRecorder] is built, and [stop] frees it. A practice that never let
/// it go would leave one behind every time.
class RecordPitchSource implements PitchSource {
  RecordPitchSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  StreamSubscription<List<int>>? _subscription;
  StreamController<PitchSample>? _output;
  bool _released = false;

  static const config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    autoGain: false,
    echoCancel: false,
    noiseSuppress: false,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceRecognition,
      manageBluetooth: false,
    ),
  );

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Stream<PitchSample> start() {
    if (_released) throw StateError('source already released');
    if (_output != null) throw StateError('capture already running');
    final tracker = PcmPitchTracker();
    late final StreamController<PitchSample> output;
    output = StreamController<PitchSample>(
      onListen: () async {
        try {
          final pcm = await _recorder.startStream(config);
          _subscription = pcm.listen(
            (bytes) {
              for (final sample in tracker.add(bytes)) {
                if (!output.isClosed) output.add(sample);
              }
            },
            onError: output.addError,
            onDone: () => output.close(),
          );
        } catch (error, stack) {
          output.addError(error, stack);
          await output.close();
        }
      },
      onCancel: stop,
    );
    _output = output;
    return output.stream;
  }

  @override
  Future<void> stop() async {
    final subscription = _subscription, output = _output;
    _subscription = null;
    _output = null;
    await subscription?.cancel();
    if (!_released) {
      _released = true;
      try {
        // Stops a capture still starting too: the plugin runs its calls in
        // order, so this waits for the start and then ends it.
        await _recorder.dispose();
      } catch (_) {
        // Already released by the system (call, another app).
      }
    }
    // Never awaited: after the listener cancels, close() never completes.
    if (output != null && !output.isClosed) unawaited(output.close());
  }
}
