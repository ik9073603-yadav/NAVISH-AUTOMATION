import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'api.dart';
import 'firebase_options.dart';

// Real push delivery for the automation engine's chases/escalations/alerts.
// Web has no FCM setup here — every method below degrades to a no-op on web
// (and on any platform Firebase failed to init on) instead of crashing.
class PushService {
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  // Set on notification tap (background or cold start); HomeScreen consumes
  // this once it knows the user's role, to jump straight to the right tab.
  static final ValueNotifier<Map<String, dynamic>?> pendingTap = ValueNotifier(null);

  static bool _ready = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('Push notifications unavailable on this platform: $e');
      return;
    }
    _ready = true;

    await FirebaseMessaging.instance.requestPermission();

    // Foreground: FCM won't show a system banner itself, so show one in-app.
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('${n.title}\n${n.body}'),
          duration: const Duration(seconds: 4),
        ),
      );
    });

    // Background: user tapped the system notification while app was alive.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      pendingTap.value = message.data;
    });

    // Terminated: app was launched BY tapping the notification.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) pendingTap.value = initial.data;
  }

  static String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  static Future<void> registerToken() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await Api.registerDevice(token, platform: _platform);

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        Api.registerDevice(newToken, platform: _platform);
      });
    } catch (e) {
      debugPrint('Failed to register push token: $e');
    }
  }

  // Called on logout — a shared device shouldn't keep chasing the last user.
  static Future<void> unregisterToken() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await Api.unregisterDevice(token);
    } catch (e) {
      debugPrint('Failed to unregister push token: $e');
    }
  }
}
