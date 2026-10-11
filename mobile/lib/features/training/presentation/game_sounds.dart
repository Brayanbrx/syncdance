import 'dart:async';

import 'package:video_player/video_player.dart';

import '../game/dance_game.dart';

/// Original synthesized cues in `assets/sfx/` (`tool/generate_sfx.py`).
enum GameSound { tick, go, perfect, great, good, miss }

/// Unrated moves stay silent: not being seen is not a mistake.
GameSound? soundFor(MoveRating? rating) => switch (rating) {
  MoveRating.perfect => GameSound.perfect,
  MoveRating.great => GameSound.great,
  MoveRating.good => GameSound.good,
  MoveRating.miss => GameSound.miss,
  null => null,
};

/// Countdown and rating cues for a player 2–3 m from the phone. They reuse
/// `video_player` in mix mode: a cue never takes audio focus, so the master
/// keeps playing. Best effort: a cue that fails to load is skipped and the
/// game never waits for one.
class GameSounds {
  GameSounds({VideoPlayerController Function(String asset)? create})
    : _create = create ?? _asset;

  static VideoPlayerController _asset(String asset) =>
      VideoPlayerController.asset(
        asset,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

  /// One switch for the game and the drill while the app is open.
  static bool enabled = true;

  /// Under the music, not over it.
  static const volume = 0.7;

  final VideoPlayerController Function(String asset) _create;
  final _players = <GameSound, VideoPlayerController>{};
  bool _disposed = false;

  Future<void> load() async {
    for (final sound in GameSound.values) {
      if (_disposed) return;
      final player = _create('assets/sfx/${sound.name}.wav');
      try {
        await player.initialize();
        await player.setVolume(volume);
        if (_disposed) {
          await player.dispose();
          return;
        }
        _players[sound] = player;
      } catch (_) {
        unawaited(player.dispose().catchError((Object _) {}));
      }
    }
  }

  void play(GameSound? sound) {
    final player = _players[sound];
    if (!enabled || _disposed || player == null) return;
    unawaited(() async {
      try {
        await player.seekTo(Duration.zero);
        await player.play();
      } catch (_) {}
    }());
  }

  void dispose() {
    _disposed = true;
    for (final player in _players.values) {
      unawaited(player.dispose().catchError((Object _) {}));
    }
    _players.clear();
  }
}
