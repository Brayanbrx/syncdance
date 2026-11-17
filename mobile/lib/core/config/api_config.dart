import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class ApiConfig {
  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    return (dotenv.isInitialized ? dotenv.env['API_BASE_URL'] : null) ??
        'http://10.0.2.2:8000/api';
  }

  /// The web (privacy policy, terms, account pages). In production it is the
  /// API's own host; in development Django (8000) has no web pages, so set
  /// WEB_BASE_URL to the nginx port (e.g. http://10.0.2.2:8085).
  static String get webBaseUrl {
    const override = String.fromEnvironment('WEB_BASE_URL');
    if (override.isNotEmpty) return override;
    final configured = dotenv.isInitialized ? dotenv.env['WEB_BASE_URL'] : null;
    return configured ?? webFromApi(baseUrl);
  }

  /// Why this build cannot reach its server, or null. A release APK must
  /// use HTTPS: Android blocks plain HTTP outside debug builds, so a missing
  /// or wrong `--dart-define=API_BASE_URL` would only show network errors.
  static String? releaseProblem({bool release = kReleaseMode, String? url}) {
    final api = url ?? baseUrl;
    if (!release || api.startsWith('https://')) return null;
    return 'Esta copia de la app no tiene configurado el servidor. '
        'Descarga la versión oficial desde la página de SyncDance.';
  }

  /// `https://host/api` -> `https://host`.
  static String webFromApi(String api) =>
      api.replaceFirst(RegExp(r'/api/?$'), '');
}
