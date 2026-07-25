import 'package:flutter/foundation.dart';

// Overrides every platform default below when provided, e.g.:
//   flutter run --dart-define=API_BASE=http://192.168.1.21:4000
// This is the only way to reach a real physical device's LAN-hosted backend —
// there's no way to distinguish "real Android device" from "Android emulator"
// at runtime, so a physical device MUST pass this explicitly.
const String _apiBaseOverride = String.fromEnvironment('API_BASE');

// The deployed backend — the release default so a built APK works out of
// the box for anyone it's shared with, with no local server required.
const String _productionApiBase = 'https://navish-automation.onrender.com';

class Config {
  // Web (Chrome) uses localhost. Android emulator can't reach the host machine
  // via localhost — 10.0.2.2 is the emulator's alias for the host's loopback.
  // A real device on the same LAN needs the host's actual IP, passed via
  // --dart-define=API_BASE=... (see above) since it can't be inferred.
  static String get apiBase {
    if (_apiBaseOverride.isNotEmpty) return _apiBaseOverride;
    // Release builds (flutter build apk --release) default to the deployed
    // backend. Debug/profile builds (flutter run) keep hitting your local
    // dev server, same as always — override with --dart-define=API_BASE=...
    // for a physical device on your LAN or any other target.
    if (kReleaseMode) return _productionApiBase;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:4000';
    }
    return 'http://localhost:4000';
  }
}
