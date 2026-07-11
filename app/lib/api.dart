import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class Api {
  static String? _token;

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
  }

  static Future<void> _saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  static bool get isLoggedIn => _token != null;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Login failed');
    await _saveToken(data['token']);
    return data;
  }

  static Future<Map<String, dynamic>> me() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/auth/me'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load profile');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> myTasks() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/tasks/my'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load tasks');
    return jsonDecode(res.body);
  }

  static Future<void> markDone(String taskId) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/tasks/$taskId/done'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to mark done');
  }

  static Future<void> markStuck(String taskId, String reason) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/tasks/$taskId/stuck'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    if (res.statusCode != 200) throw Exception('Failed to mark stuck');
  }

  static Future<List<dynamic>> notifications() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/tasks/notifications'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load notifications');
    return jsonDecode(res.body);
  }
}