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

  /// `https://host/api` -> `https://host`.
  static String webFromApi(String api) =>
      api.replaceFirst(RegExp(r'/api/?$'), '');
}
