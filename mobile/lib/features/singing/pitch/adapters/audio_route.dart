import 'package:flutter/services.dart';

/// Where the phone plays the guide now.
enum GuideOutput {
  wired('Audífonos con cable', 120),
  bluetooth('Audífonos Bluetooth', 300),
  speaker('Parlante del teléfono', 120),

  /// The phone could not tell; the echo check before singing still guards.
  unknown('Salida de audio desconocida', 120);

  const GuideOutput(this.label, this.latencyMs);
  final String label;

  /// Guide out, ears, voice, microphone and detector (provisional).
  final int latencyMs;

  /// Singing together with the guide needs the guide out of the room.
  bool get allowsTogether => this != GuideOutput.speaker;
}

/// Asks the phone where media sound goes; injectable for tests.
abstract class AudioRoute {
  Future<GuideOutput> current();
}

/// Android's `AudioManager` through `MainActivity` (channel
/// `ai.syncdance/audio_route`). Any failure is [GuideOutput.unknown].
class PlatformAudioRoute implements AudioRoute {
  const PlatformAudioRoute();

  static const _channel = MethodChannel('ai.syncdance/audio_route');

  @override
  Future<GuideOutput> current() async {
    try {
      final output = await _channel
          .invokeMethod<String>('output')
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      return switch (output) {
        'wired' => GuideOutput.wired,
        'bluetooth' => GuideOutput.bluetooth,
        'speaker' => GuideOutput.speaker,
        _ => GuideOutput.unknown,
      };
    } on PlatformException {
      return GuideOutput.unknown;
    } on MissingPluginException {
      return GuideOutput.unknown;
    }
  }
}
