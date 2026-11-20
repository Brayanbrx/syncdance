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
import 'package:syncdance_mobile/features/singing/pitch/adapters/audio_route.dart';
import 'package:syncdance_mobile/features/singing/pitch/pitch_source.dart';
import 'package:syncdance_mobile/features/singing/practice/vocal_practice.dart';
import 'package:syncdance_mobile/features/singing/practice/vocal_turns.dart';
import 'package:syncdance_mobile/features/singing/presentation/guide_player.dart';
import 'package:syncdance_mobile/features/singing/presentation/singing_practice_screen.dart';
import 'package:syncdance_mobile/features/singing/presentation/singing_screen.dart';
import 'package:syncdance_mobile/features/singing/presentation/tuner_screen.dart';
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
  double speed = 1.0;
  final seeks = <int>[];

  @override
  Future<void> open(File audio) async {
    if (broken) throw const FileSystemException('unreadable');
    duration = 11872;
  }

  @override
  Future<void> play() async {
    playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    playing = false;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double value) async => volume = value;
  @override
  Future<void> setSpeed(double value) async => speed = value;
  @override
  Future<void> seekTo(int ms) async {
    seeks.add(ms);
    position = ms;
    completed = false;
    notifyListeners();
  }

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

class FakeRoute implements AudioRoute {
  FakeRoute(this.output);
  GuideOutput output;
  @override
  Future<GuideOutput> current() async => output;
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

/// A practice screen with fakes, driven in 32 ms steps of wall time.
class Rig {
  Rig(this.tester, this.routine, {GuideOutput output = GuideOutput.wired})
    : route = FakeRoute(output);
  final WidgetTester tester;
  final SavedVoiceRoutine routine;
  final FakeRoute route;
  final store = MemoryVoiceStore();
  final sources = <FakeSource>[];
  final players = <FakePlayer>[];
  var wall = 0;

  FakePlayer get player => players.last;
  PitchReference get reference => routine.reference;

  Future<void> open() async {
    await tester.pumpWidget(
      MaterialApp(
        home: SingingPracticeScreen(
          routine: routine,
          store: store,
          createSource: () {
            final source = FakeSource();
            sources.add(source);
            return source;
          },
          createPlayer: () {
            final player = FakePlayer();
            players.add(player);
            return player;
          },
          audioRoute: route,
          clock: () => wall,
        ),
      ),
    );
    await tester.pump(); // the headphones check
  }

  Future<void> tap(String text) async {
    await tester.ensureVisible(find.text(text).first);
    await tester.pump();
    await tester.tap(find.text(text).first);
    await tester.pump();
    await tester.pump();
  }

  /// What the guide sings at its position: the microphone hears it when it
  /// leaks.
  double? guide() => reference.noteAt(player.position)?.midi;

  /// Advances up to [ms]. While the guide plays the microphone hears
  /// [whilePlaying]; otherwise [voice] (null: silence).
  Future<void> run(
    int ms, {
    double? Function()? whilePlaying,
    double? Function(int wall)? voice,
    bool Function()? until,
  }) async {
    for (var t = 0; t < ms; t += 32) {
      wall += 32;
      final player = players.lastOrNull;
      final playing = player != null && !player.disposed && player.playing;
      if (playing) {
        final next = player.position + (32 * player.speed).round();
        if (next >= player.duration) player.completed = true;
        player.at(next.clamp(0, player.duration));
      }
      final source = sources.lastOrNull;
      if (source != null && source.started && !source.stopped) {
        source.controller.add(
          PitchSample(
            wall,
            playing ? whilePlaying?.call() : voice?.call(wall),
            0.9,
          ),
        );
      }
      await tester.pump(const Duration(milliseconds: 33));
      if (until?.call() ?? false) return;
    }
  }

  /// Releasing the microphone completes on the real event loop.
  Future<void> settle() async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  bool shows(String text) => find.textContaining(text).evaluate().isNotEmpty;
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

  testWidgets('with the guide: first note, echo check, cues and summary', (
    tester,
  ) async {
    final rig = Rig(tester, routine);
    await rig.open();
    expect(find.textContaining('no se graba ni se envía'), findsOneWidget);
    expect(find.text('Audífonos con cable'), findsOneWidget);
    await rig.tap('Con la guía');
    await rig.tap('Normal');
    await rig.tap('Empezar a cantar');

    // The first note alone, while the student keeps quiet.
    final first = rig.reference.notes.first;
    expect(find.text('Escucha tu primera nota'), findsOneWidget);
    expect(rig.player.seeks, [first.startMs]);
    expect(rig.player.playing, isTrue);
    expect(rig.player.volume, 0.8);
    expect(rig.player.speed, 1.0);
    await rig.run(3000, until: () => !rig.shows('Escucha tu primera nota'));
    expect(rig.player.seeks.last, 0); // then the whole guide, count-in first
    expect(rig.player.volume, 0.8); // muted only to stop the first note

    // Every note a semitone low for a while: the cue says go up.
    var sawUp = false;
    await rig.run(
      20000,
      whilePlaying: () {
        final at = rig.player.position - GuideOutput.wired.latencyMs;
        final note = rig.reference.noteAt(at);
        if (note == null) return null;
        return note.midi - (rig.player.position < 6000 ? 1 : 0);
      },
      until: () {
        sawUp |= rig.shows('Sube');
        return rig.player.disposed;
      },
    );
    await rig.settle();
    expect(sawUp, isTrue);

    expect(find.text('Terminaste'), findsOneWidget);
    expect(rig.sources.single.stopped, isTrue);
    final record = rig.store.records.single;
    expect(record.routineName, 'Arpegio de Do');
    expect(record.reachedEnd, isTrue);
    expect(record.mode, PracticeMode.together);
    expect(record.coverage, 100);
    expect(record.outOfTune, greaterThan(0));
    expect(find.textContaining('Baja (-100 cents): sube'), findsWidgets);
    await rig.tap('Cantar otra vez');
    expect(find.text('Empezar a cantar'), findsOneWidget);
  });

  testWidgets('a microphone that hears the guide stops before scoring', (
    tester,
  ) async {
    final rig = Rig(tester, routine);
    await rig.open();
    await rig.tap('Con la guía');
    await rig.tap('Empezar a cantar');
    // Nobody sings; the guide leaks from the headphones into the microphone.
    await rig.run(3000, whilePlaying: rig.guide);
    await rig.settle();

    expect(find.textContaining('El micrófono oyó la guía'), findsOneWidget);
    expect(rig.store.records, isEmpty); // no score from the guide's voice
    expect(rig.player.disposed, isTrue);
    expect(rig.sources.single.stopped, isTrue);
    final modes = tester.widget<SegmentedButton<PracticeMode>>(
      find.byType(SegmentedButton<PracticeMode>),
    );
    expect(modes.selected, {PracticeMode.echo});
  });

  testWidgets('without headphones, singing with the guide is not offered', (
    tester,
  ) async {
    final rig = Rig(tester, routine, output: GuideOutput.speaker);
    await rig.open();
    expect(find.text('Parlante del teléfono'), findsOneWidget);
    final modes = tester.widget<SegmentedButton<PracticeMode>>(
      find.byType(SegmentedButton<PracticeMode>),
    );
    expect(modes.segments[1].enabled, isFalse);
    expect(modes.selected, {PracticeMode.echo});
  });

  testWidgets('unplugging the headphones mid-song stops the practice', (
    tester,
  ) async {
    final rig = Rig(tester, routine);
    await rig.open();
    await rig.tap('Con la guía');
    await rig.tap('Empezar a cantar');
    await rig.run(3000, until: () => !rig.shows('Escucha tu primera nota'));
    rig.route.output = GuideOutput.speaker;
    await rig.run(3000, until: () => rig.player.disposed);
    await rig.settle();
    expect(
      find.textContaining('Se desconectaron los audífonos'),
      findsOneWidget,
    );
    expect(find.text('Práctica interrumpida'), findsOneWidget);
  });

  testWidgets("echo: only the student's turn counts, then a note drill", (
    tester,
  ) async {
    final rig = Rig(tester, routine, output: GuideOutput.speaker);
    await rig.open();
    await rig.tap('Normal');
    await rig.tap('Empezar a cantar');
    expect(find.text('Escucha…'), findsOneWidget);
    expect(find.text('Frase 1 de 2'), findsOneWidget);
    expect(rig.player.seeks, [0]);

    // The guide comes out of the speaker into the microphone the whole time
    // it sings. The student keeps quiet in the first turn and sings the
    // second one right.
    final turns = echoTurns(rig.reference);
    var pauses = 0, turnStart = 0;
    var wasPlaying = true, sawSilence = false, sawGood = false;
    double? student(int wall) {
      if (pauses < 2) return null;
      final timeline =
          turns[1].startMs -
          turnLeadInMs(rig.reference) +
          (wall - turnStart) -
          SingingPracticeScreen.micLatencyMs;
      return rig.reference.noteAt(timeline)?.midi;
    }

    await rig.run(
      40000,
      whilePlaying: rig.guide,
      voice: student,
      until: () {
        final playing = !rig.player.disposed && rig.player.playing;
        if (wasPlaying && !playing) {
          pauses++;
          turnStart = rig.wall;
        }
        wasPlaying = playing;
        sawSilence |= rig.shows('No se oyó tu voz');
        sawGood |= rig.shows('¡Muy bien, todas afinadas!');
        return rig.player.disposed;
      },
    );
    await rig.settle();
    expect(rig.player.seeks, [0, turns[1].listenFromMs]);
    expect(sawSilence, isTrue);
    expect(sawGood, isTrue);

    expect(find.text('Terminaste'), findsOneWidget);
    final record = rig.store.records.single;
    expect(record.mode, PracticeMode.echo);
    expect(record.tuning, 100);
    int length(List<int> indices) =>
        indices.fold(0, (sum, i) => sum + rig.reference.notes[i].durationMs);
    final sung = length(turns[1].indices);
    expect(
      record.coverage,
      (100 * sung / (sung + length(turns[0].indices))).round(),
    );
    expect(find.textContaining('No se oyó tu voz en 4 notas'), findsOneWidget);

    // Practice the first note alone: three times, held, out of the history.
    await rig.tap('Practicar Do');
    expect(find.text('Intento 1 de 3'), findsOneWidget);
    await rig.run(
      30000,
      whilePlaying: rig.guide,
      voice: (_) => 60.0,
      until: () => rig.players.length == 2 && rig.player.disposed,
    );
    await rig.settle();
    expect(
      find.textContaining('Afinada en todos los intentos'),
      findsOneWidget,
    );
    expect(find.text('Intento 3'), findsOneWidget);
    expect(rig.store.records.length, 1);
    await rig.tap('Volver al resumen');
    expect(find.text('Terminaste'), findsOneWidget);
  });

  testWidgets('the tuner names the nearest note and lets the mic go', (
    tester,
  ) async {
    final source = FakeSource();
    await tester.pumpWidget(
      MaterialApp(home: TunerScreen(createSource: () => source)),
    );
    await tester.tap(find.text('Empezar a escuchar'));
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      source.controller.add(PitchSample(i * 32, 64.2, 0.9));
    }
    await tester.pump();
    expect(find.text('Mi'), findsOneWidget);
    expect(find.text('E4'), findsOneWidget);
    for (var i = 0; i < 25; i++) {
      source.controller.add(PitchSample(200 + i * 32, null, 0));
    }
    await tester.pump();
    expect(find.text('Canta una nota…'), findsOneWidget);
    await tester.tap(find.text('Detener'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(source.stopped, isTrue);
    expect(find.text('Empezar a escuchar'), findsOneWidget);
  });

  testWidgets('without the microphone it explains how to allow it', (
    tester,
  ) async {
    final player = FakePlayer();
    final source = FakeSource(allowed: false);
    await tester.pumpWidget(
      MaterialApp(
        home: SingingPracticeScreen(
          routine: routine,
          createSource: () => source,
          createPlayer: () => player,
          audioRoute: FakeRoute(GuideOutput.unknown),
        ),
      ),
    );
    await tester.tap(find.text('Empezar a cantar'));
    await tester.pump();
    expect(find.textContaining('Sin permiso de micrófono'), findsOneWidget);
    expect(player.playing, isFalse);
    // The source is freed even though it never captured.
    expect(source.stopped, isTrue);
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
          audioRoute: FakeRoute(GuideOutput.unknown),
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
    expect(source.stopped, isTrue);
  });

  testWidgets('going to the background while the guide opens starts nothing', (
    tester,
  ) async {
    final source = FakeSource();
    final opening = Completer<void>();
    final player = SlowPlayer(opening.future);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SingingPracticeScreen(
          routine: routine,
          createSource: () => source,
          createPlayer: () => player,
          audioRoute: FakeRoute(GuideOutput.unknown),
        ),
      ),
    );
    await tester.tap(find.text('Empezar a cantar'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    opening.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(source.started, isFalse);
    expect(player.playing, isFalse);
    expect(player.disposed, isTrue);
    expect(source.stopped, isTrue);

    // Back in the app, it can start again.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    final start = find.ancestor(
      of: find.text('Empezar a cantar'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
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
          audioRoute: FakeRoute(GuideOutput.unknown),
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
    // Newest first. The best mark compares like with like: the newest was
    // repeated after the guide at 0,75×, so only those count; a v1 score
    // (older rules) and one sung with the guide do not.
    VocalRecord record(int overall, PracticeMode mode, double speed) =>
        VocalRecord(
          routineId: 41,
          routineName: 'Arpegio de Do',
          version: 3,
          finishedAt: DateTime.utc(2026, 11, 20),
          overall: overall,
          tuning: overall,
          coverage: 100,
          outOfTune: 0,
          reachedEnd: true,
          mode: mode,
          speed: speed,
        );
    store.records.addAll([
      record(60, PracticeMode.echo, 0.75),
      record(90, PracticeMode.together, 1.0),
      record(70, PracticeMode.echo, 0.75),
      VocalRecord(
        routineId: 41,
        routineName: 'Arpegio de Do',
        version: 3,
        finishedAt: DateTime.utc(2026, 11, 17),
        overall: 100,
        tuning: 100,
        coverage: 100,
        outOfTune: 0,
        reachedEnd: true,
        summaryVersion: 'vocal-summary-v1',
      ),
    ]);
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
    expect(find.text('70 %'), findsOneWidget);
    expect(find.text('Escucha y repite'), findsOneWidget);
    expect(find.text('Afinador'), findsOneWidget);

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

  testWidgets(
    'pulling to refresh during a download does not free the buttons',
    (tester) async {
      final guide = StreamController<List<int>>();
      var listings = 0;
      http.StreamedResponse streamed(http.Response response) =>
          http.StreamedResponse(
            Stream.value(response.bodyBytes),
            response.statusCode,
          );
      final api = CatalogApi(
        'http://localhost:8000/api',
        client: MockClient.streaming((request, _) async {
          final url = request.url;
          if (url.path.endsWith('/routines/')) {
            listings++;
            return streamed(
              reply({
                'results': [
                  {'id': 41, 'name': 'Arpegio de Do', 'kind': 'SING'},
                ],
                'next': null,
              }),
            );
          }
          if (url.path.endsWith('/41/reference/')) {
            return streamed(reply(fixtureJson()));
          }
          if (url.path.endsWith('/download/')) {
            return streamed(reply(fixtureBytes()));
          }
          return http.StreamedResponse(guide.stream, 200);
        }),
      );
      addTearDown(api.close);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SingingScreen(
            session: CatalogSession(api)
              ..account = const Account(1, 'ana', 'token'),
            store: MemoryVoiceStore(),
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
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Cantar «Arpegio de Do»'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.textContaining('Descargando la guía'), findsOneWidget);

      await tester.fling(
        find.text('Escucha y repite'),
        const Offset(0, 300),
        1000,
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(listings, 1);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.play_circle_fill),
            )
            .onPressed,
        isNull,
      );

      await tester.runAsync(() async {
        guide.add([1, 2, 3]);
        await guide.close();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(opened, ['Arpegio de Do']);
    },
  );

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

    test('older records stay readable but are not a mark to beat', () async {
      final store = VoiceStore(root, 'server|1');
      await Directory(store.directory.path).create(recursive: true);
      final file = File('${store.directory.path}/history.json');
      await file.writeAsString(
        jsonEncode([
          {
            'summary_version': 'vocal-summary-v1',
            'routine': 41,
            'routine_name': 'Arpegio',
            'version': 3,
            'finished_at': '2026-11-17T00:00:00.000Z',
            'overall': 100,
            'tuning': 100,
            'coverage': 100,
            'out_of_tune': 0,
            'reached_end': true,
          },
        ]),
      );
      final summary = VocalSummary(
        notes: const [],
        tuning: 80,
        coverage: 90,
        overall: 72,
        reachedEnd: true,
        latencyMs: 80,
        mode: PracticeMode.echo,
        speed: 0.75,
      );
      await store.addRecord(
        VocalRecord.of(
          'Arpegio',
          fixtureReference(),
          summary,
          DateTime.utc(2026, 11, 20),
        ),
      );
      final history = await store.history();
      expect(history.length, 2);
      expect(
        (history[0].isCurrent, history[0].mode, history[0].speed),
        (true, PracticeMode.echo, 0.75),
      );
      // Rewritten with the new one, the old record keeps its own rules.
      expect(
        (history[1].isCurrent, history[1].mode, history[1].speed),
        (false, PracticeMode.together, 1.0),
      );
      final raw = jsonDecode(await file.readAsString()) as List;
      expect((raw[1] as Map)['summary_version'], 'vocal-summary-v1');
    });
  });
}
