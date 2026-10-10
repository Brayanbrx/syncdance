import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class ApiConfig {
  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    return (dotenv.isInitialized ? dotenv.env['API_BASE_URL'] : null) ??
        'http://10.0.2.2:8000/api';
  }
}
