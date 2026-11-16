import 'package:flutter_test/flutter_test.dart';
import 'package:syncdance_mobile/core/config/api_config.dart';

void main() {
  test('the web lives on the API host without /api', () {
    expect(
      ApiConfig.webFromApi('https://syncdance.example/api'),
      'https://syncdance.example',
    );
    expect(
      ApiConfig.webFromApi('https://syncdance.example/api/'),
      'https://syncdance.example',
    );
    // Only a trailing /api segment is removed.
    expect(
      ApiConfig.webFromApi('https://api.example/v2'),
      'https://api.example/v2',
    );
  });
}
