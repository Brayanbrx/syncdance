import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// The guide audio, behind an interface so the practice screen can be tested
/// without the platform player.
abstract class GuidePlayer implements Listenable {
  Future<void> open(File audio);
  Future<void> play();
  Future<void> pause();
  Future<void> setVolume(double volume);
  int get positionMs;
  int get durationMs;
  bool get isPlaying;

  /// Reached the end of the audio.
  bool get isCompleted;
  Future<void> dispose();
}

/// ExoPlayer through `video_player`: it plays audio-only files too.
class VideoGuidePlayer extends ChangeNotifier implements GuidePlayer {
  VideoPlayerController? _controller;

  @override
  Future<void> open(File audio) async {
    final controller = VideoPlayerController.file(
      audio,
      // The microphone runs at the same time: never pause other audio.
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await controller.initialize();
    controller.addListener(notifyListeners);
    _controller = controller;
  }

  VideoPlayerValue? get _value => _controller?.value;

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> setVolume(double volume) async =>
      _controller?.setVolume(volume.clamp(0.0, 1.0));

  @override
  int get positionMs => _value?.position.inMilliseconds ?? 0;

  @override
  int get durationMs => _value?.duration.inMilliseconds ?? 0;

  @override
  bool get isPlaying => _value?.isPlaying ?? false;

  @override
  bool get isCompleted => _value?.isCompleted ?? false;

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(notifyListeners);
    await controller?.dispose();
    super.dispose();
  }
}
