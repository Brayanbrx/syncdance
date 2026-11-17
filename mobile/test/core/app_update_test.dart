import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/config/api_config.dart';
import 'package:syncdance_mobile/core/update/app_update.dart';
import 'package:syncdance_mobile/core/update/update_banner.dart';

Map<String, dynamic> latest({int code = 3, String name = '1.2.0'}) => {
  'version_name': name,
  'version_code': code,
  'size_bytes': 31457280,
  'sha256': 'a' * 64,
  'notes': 'Pasos del instructor.',
  'min_android': '7.0',
  'published_at': '2026-11-16T12:00:00Z',
  'download_url': '/api/app/download/',
};

void main() {
  group('update check', () {
    final requests = <Uri>[];
    UpdateChecker checker(
      http.Response Function() answer, {
      InstalledVersion? installed = const InstalledVersion('1.1.0', 2),
    }) => UpdateChecker(
      apiBase: 'https://syncdance.example/api/',
      client: MockClient((request) async {
        requests.add(request.url);
        return answer();
      }),
      installed: () async => installed,
    );
    setUp(requests.clear);

    test('a newer published APK is offered', () async {
      final release = await checker(
        () => http.Response(jsonEncode(latest()), 200),
      ).newer();
      expect(
        requests.single.toString(),
        'https://syncdance.example/api/app/latest/',
      );
      expect(release!.versionName, '1.2.0');
      expect(release.downloadPath, '/api/app/download/');
      expect(release.sizeBytes, 31457280);
    });

    test('the same or an older version is not an update', () async {
      for (final code in [1, 2]) {
        final response = jsonEncode(latest(code: code));
        expect(
          await checker(() => http.Response(response, 200)).newer(),
          isNull,
        );
      }
    });

    test('no release, bad answers or no network are silent', () async {
      expect(await checker(() => http.Response('{}', 404)).newer(), isNull);
      expect(await checker(() => http.Response('<html>', 200)).newer(), isNull);
      final remote = jsonEncode({
        ...latest(),
        'download_url': 'https://elsewhere.example/app.apk',
      });
      expect(await checker(() => http.Response(remote, 200)).newer(), isNull);
      expect(
        await checker(() => throw http.ClientException('offline')).newer(),
        isNull,
      );
    });

    test('without the installed version nothing is asked', () async {
      final release = await checker(
        () => http.Response(jsonEncode(latest()), 200),
        installed: null,
      ).newer();
      expect(release, isNull);
      expect(requests, isEmpty);
    });
  });

  group('update banner', () {
    Future<List<String>> show(WidgetTester tester, AppRelease? release) async {
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UpdateBanner(
              check: () async => release,
              openPage: (path) async {
                opened.add(path);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      return opened;
    }

    testWidgets('offers the download and can be put off', (tester) async {
      final opened = await show(tester, AppRelease.tryParse(latest()));
      expect(find.text('Hay una versión nueva: 1.2.0'), findsOneWidget);
      expect(find.textContaining('(30 MB)'), findsOneWidget);
      expect(find.text('Pasos del instructor.'), findsOneWidget);
      await tester.tap(find.text('Descargar'));
      await tester.pump();
      expect(opened, ['/api/app/download/']);
      await tester.tap(find.text('Ahora no'));
      await tester.pump();
      expect(find.textContaining('versión nueva'), findsNothing);
    });

    testWidgets('nothing shows when the app is up to date', (tester) async {
      await show(tester, null);
      expect(find.byType(Card), findsNothing);
    });
  });

  test('a release build needs an HTTPS server', () {
    expect(
      ApiConfig.releaseProblem(release: true, url: 'http://10.0.2.2:8000/api'),
      contains('no tiene configurado el servidor'),
    );
    expect(
      ApiConfig.releaseProblem(
        release: true,
        url: 'https://syncdance.example/api',
      ),
      isNull,
    );
    // Debug builds talk to the local stack over HTTP.
    expect(
      ApiConfig.releaseProblem(release: false, url: 'http://10.0.2.2:8000/api'),
      isNull,
    );
  });
}
