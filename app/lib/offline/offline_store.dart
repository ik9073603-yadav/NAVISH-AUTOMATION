import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Simple JSON cache for GET responses, keyed by endpoint+params. Lets list
// screens render the last-known-good data when the network is down instead
// of an error or an endless spinner. Not a general-purpose local database —
// just enough to keep the shop-floor screens usable offline.
class OfflineStore {
  static Future<void> put(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cache:$key', jsonEncode(data));
  }

  static Future<dynamic> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cache:$key');
    if (raw == null) return null;
    return jsonDecode(raw);
  }
}
