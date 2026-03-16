import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DesktopIsland {
  DesktopIsland._();

  static const MethodChannel _channel = MethodChannel('notes_bridge/island');

  static Future<void> show({
    required String title,
    required String body,
    int durationMs = 2600,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await _channel.invokeMethod<void>('show', <String, Object>{
          'title': title,
          'body': body,
          'durationMs': durationMs,
        });
      } catch (_) {
        // Ignore desktop channel errors to keep app flow stable.
      }
    }
  }
}
