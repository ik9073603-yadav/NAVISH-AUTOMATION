import 'package:flutter/foundation.dart';

class Config {
  // Web (Chrome) uses localhost. Android emulator can't reach the host machine
  // via localhost — 10.0.2.2 is the emulator's alias for the host's loopback.
  static String get apiBase {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:4000';
    }
    return 'http://localhost:4000';
  }
}
