import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// App-wide theme mode, local to the device (not a backend field) — read by
// NavishApp's MaterialApp, written by Settings > Appearance.
class ThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('themeMode');
    mode.value = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', m.name);
  }
}
