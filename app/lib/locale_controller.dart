import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// App-wide language, local to the device (mirrors theme_controller.dart's
// pattern) — read by NavishApp's MaterialApp, written by Profile >
// Preferences. Loaded before login so the login screen itself already
// reflects the last-picked language; kept in sync with the user's saved
// 'language' profile field once they're signed in.
class LocaleController {
  static final ValueNotifier<Locale> locale = ValueNotifier(const Locale('en'));

  static String _normalize(String? code) => code == 'hi' ? 'hi' : 'en';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    locale.value = Locale(_normalize(prefs.getString('language')));
  }

  static Future<void> set(String languageCode) async {
    final code = _normalize(languageCode);
    locale.value = Locale(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', code);
  }

  // Called after fetching the signed-in user's profile — keeps this
  // device's locale aligned with the server-side preference without
  // requiring the user to re-toggle it on every device.
  static Future<void> syncFromProfile(String? profileLanguage) async {
    if (profileLanguage == null) return;
    final code = _normalize(profileLanguage);
    if (locale.value.languageCode == code) return;
    await set(code);
  }
}
