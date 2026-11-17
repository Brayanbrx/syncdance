import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncdance_mobile/core/errors/error_reporter.dart';
import 'package:syncdance_mobile/core/update/app_update.dart';

void main() {
  late List<http.Request> sent;
  ErrorReporter reporter({
    InstalledVersion? installed = const InstalledVersion('1.1.0', 2),
    bool offline = false,
  }) => ErrorReporter(
    apiBase: 'https://syncdance.example/api',
    osVersion: 'Android 13',
    installed: () async => installed,
    client: MockClient((request) async {
      if (offline) throw http.ClientException('offline');
      sent.add(request);
      return http.Response('', 204);
    }),
  );
  setUp(() => sent = []);

  StackTrace stackAt(String place) => StackTrace.fromString(
    '#0      $place (package:syncdance_mobile/a.dart:10)\n'
    '#1      main (package:syncdance_mobile/main.dart:5)\n',
  );

  test('sends the kind, the first stack lines and the versions', () async {
    await reporter().report(
      const FormatException('Resumen local inválido.'),
      stackAt('SavedSession.fromJson'),
    );
    final request = sent.single;
    expect(request.url.toString(), 'https://syncdance.example/api/app/errors/');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['app_version'], '1.1.0+2');
    expect(body['os_version'], 'Android 13');
    expect(body['kind'], 'FormatException');
    expect(body['message'], contains('Resumen local inválido.'));
    expect((body['stack'] as String).split('\n'), hasLength(2));
    expect(body.keys, isNot(contains('account')));
  });

  test('each place reports once and a run reports at most ten', () async {
    final errors = reporter();
    await errors.report(StateError('x'), stackAt('A.run'));
    await errors.report(StateError('again'), stackAt('A.run'));
    for (var i = 0; i < 20; i++) {
      await errors.report(StateError('x'), stackAt('Place$i.run'));
    }
    expect(sent, hasLength(ErrorReporter.maxPerRun));
  });

  test('reporting never fails, even offline or without a version', () async {
    await reporter(offline: true).report(StateError('x'), null);
    await reporter(installed: null).report(StateError('x'), null);
    expect(jsonDecode(sent.single.body)['app_version'], 'desconocida');
  });

  test('messages lose e-mails, tokens and long numbers', () {
    final clean = ErrorReporter.scrub(
      'ana.perez@example.com falló con Bearer eyJhbGciOiJIUzI1NiJ9.abc '
      'en 3f2b8c1e5d4a4b6f9a7e2c1d0e9f8a7b3f2b y 70123456',
    );
    expect(clean, isNot(contains('ana.perez')));
    expect(clean, isNot(contains('eyJ')));
    expect(clean, isNot(contains('3f2b8c1e')));
    expect(clean, isNot(contains('70123456')));
    expect(clean, contains('<correo>'));
    expect(ErrorReporter.scrub('x' * 1000).length, lessThanOrEqualTo(301));
  });
}
