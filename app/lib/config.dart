import 'package:flutter/foundation.dart';

// Overrides every platform default below when provided, e.g.:
//   flutter run --dart-define=API_BASE=http://192.168.1.21:4000
// This is the only way to reach a real physical device's LAN-hosted backend —
// there's no way to distinguish "real Android device" from "Android emulator"
// at runtime, so a physical device MUST pass this explicitly.
const String _apiBaseOverride = String.fromEnvironment('API_BASE');

class Config {
  // Web (Chrome) uses localhost. Android emulator can't reach the host machine
  // via localhost — 10.0.2.2 is the emulator's alias for the host's loopback.
  // A real device on the same LAN needs the host's actual IP, passed via
  // --dart-define=API_BASE=... (see above) since it can't be inferred.
  static String get apiBase {
    if (_apiBaseOverride.isNotEmpty) return _apiBaseOverride;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:4000';
    }
    return 'http://localhost:4000';
  }
}
