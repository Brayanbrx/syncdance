import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/features/training/game/dance_game.dart';
import 'package:syncdance_mobile/features/training/presentation/game_sounds.dart';

import 'master_playback_screen_test.dart' show TestPlayer;

/// A cue player that records what it plays instead of making sound.
class CuePlayer extends TestPlayer {
  CuePlayer(this.asset, this.log, {this.broken = false});
  final String asset;
  final List<String> log;
  final bool broken;

  @override
  Future<void> initialize() async {
    if (broken) throw const FileSystemException('Sin códec');
    await super.initialize();
  }

  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);

  @override
  Future<void> play() async {
    log.add(asset.split('/').last.replaceAll('.wav', ''));
    await super.play();
  }
}

/// Real [GameSounds] over recording players; the log holds the cue names.
GameSounds recordingSounds(List<String> log, {Set<String> broken = const {}}) =>
    GameSounds(
      create: (asset) => CuePlayer(
        asset,
        log,
        broken: broken.any((name) => asset.endsWith('/$name.wav')),
      ),
    );

void main() {
  tearDown(() => GameSounds.enabled = true);

  test('every rating has its cue and an unrated move stays silent', () {
    expect(soundFor(MoveRating.perfect), GameSound.perfect);
    expect(soundFor(MoveRating.miss), GameSound.miss);
    expect(soundFor(null), isNull);
  });

  test(
    'cues play from the start, can be muted, and missing ones skip',
    () async {
      final log = <String>[];
      final sounds = recordingSounds(log, broken: {'miss'});
      await sounds.load();
      sounds
        ..play(GameSound.tick)
        ..play(GameSound.miss) // failed to load: skipped, no error
        ..play(null);
      await pumpEventQueue();
      expect(log, ['tick']);

      GameSounds.enabled = false;
      sounds.play(GameSound.go);
      await pumpEventQueue();
      expect(log, ['tick']);

      GameSounds.enabled = true;
      sounds.dispose();
      sounds.play(GameSound.go);
      await pumpEventQueue();
      expect(log, ['tick']);
    },
  );

  test('every cue asset exists', () {
    for (final sound in GameSound.values) {
      final file = File('assets/sfx/${sound.name}.wav');
      expect(file.existsSync(), isTrue, reason: sound.name);
      // RIFF/WAVE header of a real file, not an empty placeholder.
      expect(file.readAsBytesSync().sublist(8, 12), 'WAVE'.codeUnits);
    }
  });
}
