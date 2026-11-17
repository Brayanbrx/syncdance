import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/network/catalog_session.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';
import 'package:syncdance_mobile/features/singing/pitch/pitch_source.dart';
import 'package:syncdance_mobile/features/singing/practice/vocal_practice.dart';
import 'package:syncdance_mobile/features/singing/presentation/guide_player.dart';
import 'package:syncdance_mobile/features/singing/presentation/singing_practice_screen.dart';
import 'package:syncdance_mobile/features/singing/presentation/singing_screen.dart';
import 'package:syncdance_mobile/features/singing/reference/pitch_reference.dart';
import 'package:syncdance_mobile/features/singing/reference/voice_store.dart';

import 'pitch_reference_test.dart'
    show fixtureBytes, fixtureJson, fixtureReference, tampered;

class FakeSource implements PitchSource {
  FakeSource({this.allowed = true});
  final bool allowed;
  final controller = StreamController<PitchSample>();
  bool stopped = false, started = false;

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Stream<PitchSample> start() {
    started = true;
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    unawaited(controller.close());
  }
}

class FakePlayer extends ChangeNotifier implements GuidePlayer {
  FakePlayer({this.broken = false});
  final bool broken;
  int position = 0, duration = 0;
  bool playing = false, completed = false, disposed = false;
  double? volume;

  @override
  Future<void> open(File audio) async {
    if (broken) throw const FileSystemException('unreadable');
    duration = 11872;
  }

  @override
  Future<void> play() async => playing = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> setVolume(double value) async => volume = value;
  @override
  int get positionMs => position;
  @override
  int get durationMs => duration;
  @override
  bool get isPlaying => playing;
  @override
  bool get isCompleted => completed;
  @override
  Future<void> dispose() async {
    disposed = true;
    super.dispose();
  }

  void at(int ms) {
    position = ms;
    notifyListeners();
  }
}

/// A guide that takes its time to open, to leave the screen meanwhile.
class SlowPlayer extends FakePlayer {
  SlowPlayer(this.ready);
  final Future<void> ready;
  @override
  Future<void> open(File audio) async {
    await ready;
    duration = 11872;
  }
}

/// History in memory: disk persistence has its own test below.
class MemoryVoiceStore extends VoiceStore {
  MemoryVoiceStore() : super(Directory('unused'), 'test');
  final records = <VocalRecord>[];
  final saved = <SavedVoiceRoutine>[];
  @override
  Future<List<VocalRecord>> history() async => List.of(records);
  @override
  Future<void> addRecord(VocalRecord record) async => records.insert(0, record);
  @override
  Future<List<SavedVoiceRoutine>> readAll() async => List.of(saved);
  @override
  Future<SavedVoiceRoutine> save(
    String name,
    PitchReferenceMetadata metadata,
    List<int> reference,
    Stream<List<int>> audio,
  ) async {
    await audio.drain<void>();
    final routine = SavedVoiceRoutine(
      name,
      decodePitchReference(reference, metadata),
      File('guide.m4a'),
    );
    saved.add(routine);
    return routine;
  }
}

http.Response reply(Object? body, [int status = 200]) => http.Response.bytes(
  body is List<int> ? body : utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  final routine = SavedVoiceRoutine(
    'Arpegio de Do',
    fixtureReference(),
    File('guide.m4a'),
  );

  testWidgets('sing along: live cue, then the summary is kept', (tester) async {
    final source = FakeSource();
    final player = FakePlayer();
    final store = MemoryVoiceStore();
    var wall = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SingingPracticeScreen(
          routine: routine,
          store: store,
          createSource: () => source,
          createPlayer: () => player,
          clock: () => wall,
        ),
      ),
    );
    expect(find.textContaining('no se graba ni se envía'), findsOneWidget);
    await tester.tap(find.text('Bluetooth'));
    await tester.pump();
    await tester.tap(find.text('Empezar a cantar'));
    await tester.pump();
    await tester.pump();
    expect(player.playing, isTrue);
    expect(player.volume, 0.8);
    expect(find.text('Canta con la guía'), findsOneWidget);

    // Sing every note a semitone low for a while: the cue says go up.
    final reference = routine.reference;
    for (var guide = 0; guide < reference.durationMs; guide += 32) {
      wall = guide;
      player.at(guide);
      final note = reference.noteAt(guide - Headphones.bluetooth.latencyMs);
      final low = guide < 6000;
      source.controller.add(
        PitchSample(
          guide,
          note == null ? null : note.midi - (low ? 1 : 0),
          0.9,
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
      if (guide == 4512) expect(find.text('Sube un poco'), findsOneWidget);
    }
    player.completed = true;
    player.at(reference.durationMs);
    // Releasing the microphone completes on the real event loop.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    expect(find.text('Terminaste'), findsOneWidget);
    expect(source.stopped, isTrue);
    expect(player.disposed, isTrue);
    expect(store.records.single.routineName, 'Arpegio de Do');
    final summary = store.records.single;
    expect(summary.reachedEnd, isTrue);
    expect(summary.coverage, 100);
    expect(summary.outOfTune, greaterThan(0));
    expect(find.textContaining('Un poco baja'), findsWidgets);
    await tester.ensureVisible(find.text('Cantar otra vez'));
    await tester.pump();
    await tester.tap(find.text('Cantar otra vez'));
    await tester.pump();
    expect(find.text('Empezar a cantar'), findsOneWidget);
  });

  testWidgets('without the microphone it explains how to allow it', (
    tester,
  ) async {
    final player = FakePlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: SingingPracticeScreen(
          routine: routine,
          createSource: () => FakeSource(allowed: false),
          createPlayer: () => player,
        ),
      ),
    );
    await tester.tap(find.text('Empezar a cantar'));
    await tester.pump();
    expect(find.textContaining('Sin permiso de micrófono'), findsOneWidget);
    expect(player.playing, isFalse);
  });

  testWidgets('leaving while the guide opens never starts the microphone', (
    tester,
  ) async {
    final source = FakeSource();
    final opening = Completer<void>();
    final player = SlowPlayer(opening.future);
    await tester.pumpWidget(
      MaterialApp(
        home: SingingPracticeScreen(
          routine: routine,
          createSource: () => source,
          createPlayer: () => player,
        ),
      ),
    );
    await tester.tap(find.text('Empezar a cantar'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('Otra pantalla')));
    opening.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(source.started, isFalse);
    expect(player.playing, isFalse);
    expect(player.disposed, isTrue);
  });

  testWidgets('a guide that cannot be opened is released and explained', (
    tester,
  ) async {
    final source = FakeSource();
    final player = FakePlayer(broken: true);
    await tester.pumpWidget(
      MaterialApp(
        home: SingingPracticeScreen(
          routine: routine,
          createSource: () => source,
          createPlayer: () => player,
        ),
      ),
    );
    await tester.tap(find.text('Empezar a cantar'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(find.textContaining('No se pudo abrir'), findsOneWidget);
    expect(player.disposed, isTrue);
    expect(source.stopped, isTrue);
  });

  testWidgets('the section lists singing, downloads once and opens it', (
    tester,
  ) async {
    final requests = <String>[];
    final api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient((request) async {
        final url = request.url;
        requests.add('${url.path}?${url.query}');
        if (url.path.endsWith('/routines/')) {
          expect(url.queryParameters['kind'], 'SING');
          return reply({
            'results': [
              {
                'id': 41,
                'name': 'Arpegio de Do',
                'kind': 'SING',
                'difficulty': 'BEGINNER',
                'duration_ms': 11872,
                'description': 'Salta por las notas del acorde.',
              },
              // A server that ignored the filter: never listed here.
              {'id': 7, 'name': 'Paso básico', 'kind': 'DANCE'},
            ],
            'next': null,
          });
        }
        if (url.path.endsWith('/41/reference/')) return reply(fixtureJson());
        if (url.path.endsWith('/download/')) return reply(fixtureBytes());
        if (url.path.endsWith('/41/references/3/video/')) {
          return http.Response.bytes([1, 2, 3], 200);
        }
        return reply({}, 404);
      }),
    );
    addTearDown(api.close);
    final store = MemoryVoiceStore();
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SingingScreen(
          session: CatalogSession(api)
            ..account = const Account(1, 'ana', 'token'),
          store: store,
          openPractice: (routine, _) {
            opened.add(routine.name);
            return const Scaffold(body: Text('Practicando'));
          },
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Arpegio de Do'), findsOneWidget);
    expect(find.text('Paso básico'), findsNothing);
    expect(find.text('Usa audífonos'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Cantar «Arpegio de Do»'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(opened, ['Arpegio de Do']);
    expect(find.text('Practicando'), findsOneWidget);
    expect(store.saved.single.reference.metadata.version, 3);

    // Back and again: already saved, nothing downloaded twice.
    Navigator.of(tester.element(find.text('Practicando'))).pop();
    await tester.pumpAndSettle();
    final downloads = requests.where((r) => r.contains('/download/')).length;
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Cantar «Arpegio de Do»'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(requests.where((r) => r.contains('/download/')).length, downloads);
    expect(opened, ['Arpegio de Do', 'Arpegio de Do']);
  });

  group('on disk', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('voice-'));
    tearDown(() => root.delete(recursive: true));

    test('melody and audio are kept only when their hashes match', () async {
      final audio = utf8.encode('guide audio bytes');
      final audioHash = sha256.convert(audio).toString();
      final (bytes, metadata) = tampered(
        (artifact) => artifact['source_sha256'] = audioHash,
      );
      final json = metadata.toJson()..['source_sha256'] = audioHash;
      final matching = PitchReferenceMetadata.fromJson(json);
      final store = VoiceStore(root, 'server|1');

      await expectLater(
        store.save('Arpegio', matching, bytes, Stream.value([9, 9, 9])),
        throwsA(isA<Exception>()),
      );
      expect(await store.readAll(), isEmpty);

      final saved = await store.save(
        'Arpegio',
        matching,
        bytes,
        Stream.value(audio),
      );
      expect(await saved.audio.readAsBytes(), audio);
      final listed = await store.readAll();
      expect(listed.single.name, 'Arpegio');
      expect(listed.single.reference.notes.length, 7);

      // A damaged audio file is not offered for practice.
      await saved.audio.writeAsBytes([0]);
      expect(await store.readAll(), isEmpty);
      // Another account never sees it.
      expect(await VoiceStore(root, 'server|2').readAll(), isEmpty);
    });

    test('a new version replaces the older one on the phone', () async {
      final store = VoiceStore(root, 'server|1');
      Future<SavedVoiceRoutine> keep(
        int version,
        List<int> audio, {
        int routine = 41,
      }) {
        final hash = sha256.convert(audio).toString();
        final (bytes, metadata) = tampered((a) => a['source_sha256'] = hash);
        final json = metadata.toJson()
          ..['source_sha256'] = hash
          ..['version'] = version
          ..['routine'] = routine;
        return store.save(
          'Arpegio',
          PitchReferenceMetadata.fromJson(json),
          bytes,
          Stream.value(audio),
        );
      }

      final old = await keep(3, utf8.encode('first guide'));
      final other = await keep(3, utf8.encode('first guide'), routine: 4);
      final newer = await keep(4, utf8.encode('second guide'));

      expect(await old.audio.exists(), isFalse);
      expect(await newer.audio.exists(), isTrue);
      expect(await other.audio.exists(), isTrue); // another routine stays
      final listed = await store.readAll();
      expect(
        listed.map(
          (r) => (r.reference.metadata.routineId, r.reference.metadata.version),
        ),
        unorderedEquals([(41, 4), (4, 3)]),
      );
    });

    test('the history keeps the newest and skips unreadable records', () async {
      final store = VoiceStore(root, 'server|1');
      final summary = VocalSummary(
        notes: const [],
        tuning: 80,
        coverage: 90,
        overall: 72,
        reachedEnd: true,
        latencyMs: 120,
      );
      for (var i = 0; i < VoiceStore.maxHistory + 3; i++) {
        await store.addRecord(
          VocalRecord.of(
            'Arpegio',
            fixtureReference(),
            summary,
            DateTime.utc(2026, 11, 17, 0, 0, i),
          ),
        );
      }
      final history = await store.history();
      expect(history.length, VoiceStore.maxHistory);
      expect(history.first.finishedAt, DateTime.utc(2026, 11, 17, 0, 3, 22));
      expect(history.first.overall, 72);

      final file = File('${store.directory.path}/history.json');
      final raw = jsonDecode(await file.readAsString()) as List;
      raw[1] = {'summary_version': 'vocal-summary-v0'};
      await file.writeAsString(jsonEncode(raw));
      expect((await store.history()).length, VoiceStore.maxHistory - 1);
      await file.writeAsString('not json');
      expect(await store.history(), isEmpty);
    });
  });
}
