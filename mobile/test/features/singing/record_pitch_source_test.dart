import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:syncdance_mobile/features/singing/pitch/adapters/record_pitch_source.dart';

/// The plugin's recorder without a phone: what the adapter asks of it.
class FakeRecorder implements AudioRecorder {
  final pcm = StreamController<Uint8List>();
  bool recording = false, disposed = false;
  int disposals = 0;

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    recording = true;
    return pcm.stream;
  }

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<String?> stop() async {
    recording = false;
    return null;
  }

  @override
  Future<void> dispose() async {
    recording = false;
    disposed = true;
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('stopping frees the native recorder, once, and the source', () async {
    final recorder = FakeRecorder();
    final source = RecordPitchSource(recorder: recorder);
    final samples = source.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(recorder.recording, isTrue);

    await samples.cancel(); // the stream's cancel stops the capture
    expect(recorder.recording, isFalse);
    expect(recorder.disposed, isTrue);
    await source.stop();
    expect(recorder.disposals, 1);
    expect(source.start, throwsStateError);
  });

  test('a source that never started is freed too', () async {
    // The permission was refused: no capture, but the recorder exists.
    final recorder = FakeRecorder();
    final source = RecordPitchSource(recorder: recorder);
    expect(await source.requestPermission(), isTrue);
    await source.stop();
    expect(recorder.disposed, isTrue);
  });
}
