import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:syncdance_mobile/features/routines/reference/catalog_api.dart';
import 'package:syncdance_mobile/features/routines/reference/master_video_cache.dart';
import 'package:syncdance_mobile/features/routines/reference/motion_reference.dart';
import 'package:syncdance_mobile/features/routines/reference/reference_cache.dart';
import 'package:syncdance_mobile/features/training/presentation/master_playback_screen.dart';
import 'package:syncdance_mobile/features/training/history/session_store.dart';
import 'package:syncdance_mobile/features/training/history/saved_session.dart';
import 'package:video_player/video_player.dart';

import '../routines/reference_test_samples.dart';

class MemorySessionStore extends SessionStore {
  MemorySessionStore() : super(Directory('unused'), 'test');
  final records = <String, SavedSession>{};
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<void> save(SavedSession session) async {
    await pending?.future;
    if (fail) throw const FileSystemException('Full');
    records[session.id] = session;
  }

  final sync = <String, SyncStatus>{};
  @override
  Future<SessionHistory> readAll() async =>
      SessionHistory(records.values.toList(), 0, sync: sync);
  @override
  Future<void> remove(String id) async {
    records.remove(id);
    sync.remove(id);
  }

  @override
  Future<void> markSync(String id, SyncState state, {String? reason}) async =>
      sync[id] = SyncStatus(state, reason: reason);
  @override
  Future<void> clearSync(String id) async => sync.remove(id);
}

class LocalVideo extends MasterVideoCache {
  LocalVideo({this.present = true}) : super(Directory('unused'));
  bool present;
  @override
  Future<File?> read(ReferenceMetadata metadata) async =>
      present ? File('master.mp4') : null;
  @override
  Future<void> remove(ReferenceMetadata metadata) async {
    present = false;
  }
}

class TestPlayer extends VideoPlayerController {
  TestPlayer({
    this.duration = const Duration(milliseconds: 250),
    this.initializing,
  }) : super.file(File('master.mp4'));
  final Duration duration;
  final Completer<void>? initializing;
  bool disposed = false;
  @override
  Future<void> initialize() async {
    await initializing?.future;
    if (!disposed) {
      value = VideoPlayerValue(
        duration: duration,
        size: const Size(320, 180),
        isInitialized: true,
      );
    }
  }

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true, isCompleted: false);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    value = value.copyWith(position: position, isCompleted: false);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    value = value.copyWith(playbackSpeed: speed);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

void main() {
  late CatalogApi api;
  late SavedReference saved;
  setUp(() {
    api = CatalogApi(
      'http://localhost:8000/api',
      client: MockClient(
        (_) async => throw StateError('Offline test must not request network'),
      ),
    );
    saved = SavedReference(
      'Maestro demo',
      decodeReference(referenceBytes(), metadata()),
    );
  });
  tearDown(() => api.close());

  Future<void> open(
    WidgetTester tester,
    TestPlayer player, {
    LocalVideo? cache,
    MemorySessionStore? store,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MasterPlaybackScreen(
          saved: saved,
          api: api,
          account: const Account(1, 'demo', 'token'),
          cache: cache ?? LocalVideo(),
          createController: (_) => player,
          sessionStore: store ?? MemorySessionStore(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'learn mode slows the master and the practice keeps that speed',
    (tester) async {
      final player = TestPlayer();
      final store = MemorySessionStore();
      await open(tester, player, store: store);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('0,5×'));
      await tester.tap(find.text('0,5×'));
      await tester.pumpAndSettle();
      expect(player.value.playbackSpeed, 0.5);
      expect(find.textContaining('Modo aprender'), findsOneWidget);
      await tester.ensureVisible(find.text('Practicar con cámara'));
      await tester.tap(find.text('Practicar con cámara'));
      await tester.pumpAndSettle();
      // The master cannot be deleted by accident while practising.
      await tester.ensureVisible(find.text('Eliminar video guardado'));
      await tester.tap(find.text('Eliminar video guardado'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar video del maestro'), findsNothing);
      // The speed cannot change during a practice.
      await tester.ensureVisible(find.text('1×'));
      await tester.tap(find.text('1×'));
      await tester.pumpAndSettle();
      expect(player.value.playbackSpeed, 0.5);
      await tester.ensureVisible(find.text('Finalizar práctica'));
      await tester.tap(find.text('Finalizar práctica'));
      await tester.pumpAndSettle();
      expect(store.records.values.single.summary.playbackSpeed, 0.5);
      expect(find.textContaining('velocidad 0,5×'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final automatic in [false, true]) {
    testWidgets(
      'practice summary finishes and repeat resets it: automatic=$automatic',
      (tester) async {
        final player = TestPlayer();
        final store = MemorySessionStore();
        await open(tester, player, store: store);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Practicar con cámara'));
        await tester.tap(find.text('Practicar con cámara'));
        await tester.pumpAndSettle();
        expect(player.value.position, Duration.zero);
        expect(player.value.isPlaying, isFalse);
        if (automatic) {
          player.value = player.value.copyWith(isCompleted: true);
        } else {
          await tester.ensureVisible(find.text('Finalizar práctica'));
          await tester.tap(find.text('Finalizar práctica'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Resumen de práctica'), findsOneWidget);
        expect(
          find.text('Similitud: —. Sin comparaciones válidas.'),
          findsOneWidget,
        );
        expect(find.textContaining('Tu cámara'), findsNothing);
        expect(store.records.length, 1);
        expect(store.records.values.single.summary.reachedVideoEnd, automatic);
        expect(
          find.textContaining('Resumen guardado en el historial'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Repetir práctica'));
        await tester.tap(find.text('Repetir práctica'));
        await tester.pumpAndSettle();
        expect(find.text('Resumen de práctica'), findsNothing);
        expect(find.text('Finalizar práctica'), findsOneWidget);
        expect(player.value.position, Duration.zero);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'failed save retains summary, blocks repeat and retries with same UUID',
    (tester) async {
      final store = MemorySessionStore()..fail = true;
      await open(tester, TestPlayer(), store: store);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Practicar con cámara'));
      await tester.tap(find.text('Practicar con cámara'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Finalizar práctica'));
      await tester.tap(find.text('Finalizar práctica'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudo guardar'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Repetir práctica'),
            )
            .onPressed,
        isNull,
      );
      store.fail = false;
      await tester.ensureVisible(find.text('Reintentar guardado'));
      await tester.tap(find.text('Reintentar guardado'));
      await tester.pumpAndSettle();
      expect(store.records.length, 1);
      expect(
        find.textContaining('Resumen guardado en el historial'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'back finishes practice and waits for durable save before leaving',
    (tester) async {
      final store = MemorySessionStore()..pending = Completer<void>();
      final player = TestPlayer();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MasterPlaybackScreen(
                      saved: saved,
                      api: api,
                      account: const Account(1, 'demo', 'token'),
                      cache: LocalVideo(),
                      sessionStore: store,
                      createController: (_) => player,
                    ),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Practicar con cámara'));
      await tester.tap(find.text('Practicar con cámara'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Resumen de práctica'), findsOneWidget);
      expect(find.text('Guardando resumen…'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(player.disposed, isFalse);
      store.pending!.complete();
      await tester.pumpAndSettle();
      expect(store.records.length, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Abrir'), findsOneWidget);
      expect(player.disposed, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'offline playback follows video position, hides gaps/buffering and never resumes automatically',
    (tester) async {
      final player = TestPlayer();
      await open(tester, player);
      await tester.pumpAndSettle();
      expect(find.text('Medidas del maestro'), findsOneWidget);
      await tester.tap(find.text('Reproducir'));
      await tester.pumpAndSettle();
      expect(player.value.isPlaying, isTrue);
      await player.seekTo(const Duration(milliseconds: 83));
      await tester.pump();
      expect(
        find.textContaining('no tiene medidas utilizables'),
        findsOneWidget,
      );
      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();
      expect(player.value.position, Duration.zero);
      expect(player.value.isPlaying, isFalse);
      expect(find.text('Medidas del maestro'), findsOneWidget);
      player.value = player.value.copyWith(isBuffering: true);
      await tester.pump();
      expect(find.text('Medidas del maestro'), findsNothing);
      player.value = player.value.copyWith(isBuffering: false);
      await player.play();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(player.value.isPlaying, isFalse);
      expect(find.text('Medidas del maestro'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(player.value.isPlaying, isFalse);
      player.value = player.value.copyWith(isCompleted: true);
      await tester.pump();
      expect(find.text('Medidas del maestro'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(player.disposed, isTrue);
    },
  );

  testWidgets(
    'duration mismatch blocks playback and saved video can be removed',
    (tester) async {
      final player = TestPlayer(duration: const Duration(seconds: 10));
      final cache = LocalVideo();
      await open(tester, player, cache: cache);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('duración del video no coincide'),
        findsOneWidget,
      );
      expect(find.text('Reproducir'), findsNothing);
      expect(player.disposed, isTrue);
      await tester.tap(find.text('Eliminar video guardado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(cache.present, isTrue);
      await tester.tap(find.text('Eliminar video guardado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(cache.present, isFalse);
      expect(find.text('Descargar video y abrir'), findsOneWidget);
    },
  );

  testWidgets(
    'missing video waits for explicit download; disposal during init is safe',
    (tester) async {
      final pending = Completer<void>();
      final player = TestPlayer(initializing: pending);
      await open(tester, player, cache: LocalVideo(present: false));
      await tester.pumpAndSettle();
      expect(find.text('Descargar video y abrir'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await open(tester, player);
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(player.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
