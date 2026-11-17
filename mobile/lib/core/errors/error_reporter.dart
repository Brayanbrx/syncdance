import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../update/app_update.dart';

/// Sends the errors the release APK hits to the server (`POST
/// /api/app/errors/`): the error type, its first stack lines and the app and
/// system versions. Never the account, images or poses. Each place reports
/// once per run, at most [maxPerRun] in total, and reporting never throws.
class ErrorReporter {
  ErrorReporter({
    String? apiBase,
    this.client,
    Future<InstalledVersion?> Function()? installed,
    String? osVersion,
  }) : _apiBase = apiBase ?? ApiConfig.baseUrl,
       _installed = installed ?? InstalledVersion.read,
       _osVersion = osVersion ?? _platformVersion();

  static const maxPerRun = 10;
  static const stackLines = 12;

  final String _apiBase;
  final Future<InstalledVersion?> Function() _installed;
  final String _osVersion;

  /// Injected in tests; otherwise one client per report, closed after it.
  final http.Client? client;
  final _sent = <String>{};

  static String _platformVersion() {
    try {
      final version = Platform.operatingSystemVersion;
      return version.length > 120 ? version.substring(0, 120) : version;
    } catch (_) {
      return '';
    }
  }

  /// Hooks Flutter's and the platform's error handlers, keeping the ones
  /// already set (debug printing still happens).
  void install() {
    final flutter = FlutterError.onError;
    FlutterError.onError = (details) {
      flutter?.call(details);
      unawaited(report(details.exception, details.stack));
    };
    final platform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack));
      return platform?.call(error, stack) ?? false;
    };
  }

  Future<void> report(Object error, StackTrace? stack) async {
    final kind = error.runtimeType.toString();
    final lines = (stack?.toString() ?? '')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(stackLines)
        .toList();
    final place = '$kind|${lines.isEmpty ? '' : lines.first}';
    if (_sent.length >= maxPerRun || !_sent.add(place)) return;
    final web = client ?? http.Client();
    try {
      final installed = await _installed();
      final base = _apiBase.replaceFirst(RegExp(r'/+$'), '');
      await web
          .post(
            Uri.parse('$base/app/errors/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'app_version': installed == null
                  ? 'desconocida'
                  : '${installed.name}+${installed.code}',
              'os_version': _osVersion,
              'kind': kind.length > 120 ? kind.substring(0, 120) : kind,
              'message': scrub(error.toString()),
              'stack': lines.join('\n'),
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Reporting is best effort: never a second failure.
    } finally {
      if (client == null) web.close();
    }
  }

  /// Error texts may quote what the app was handling: drop anything that
  /// looks like an e-mail, a token or a long number, and keep it short.
  static String scrub(String message) {
    final clean = message
        .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '<correo>')
        .replaceAll(
          RegExp(r'Bearer\s+\S+', caseSensitive: false),
          'Bearer <token>',
        )
        .replaceAll(RegExp(r'[A-Za-z0-9_\-]{32,}'), '<id>')
        .replaceAll(RegExp(r'\d{6,}'), '<número>');
    return clean.length > 300 ? '${clean.substring(0, 300)}…' : clean;
  }
}
