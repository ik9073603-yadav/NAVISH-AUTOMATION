import 'dart:convert';
import 'dart:typed_data';
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

  // Shared ?status=&from=&to=&assigneeId= builder for the list endpoints.
  static Uri _listUri(
    String path, {
    String status = 'ACTIVE',
    DateTime? from,
    DateTime? to,
    String? assigneeId,
  }) {
    return Uri.parse('${Config.apiBase}$path').replace(queryParameters: {
      'status': status,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (assigneeId != null) 'assigneeId': assigneeId,
    });
  }

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

  static Future<List<dynamic>> myTasks({
    String status = 'ACTIVE',
    DateTime? from,
    DateTime? to,
  }) async {
    final res = await http.get(
      _listUri('/api/tasks/my', status: status, from: from, to: to),
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
  static Future<List<dynamic>> users() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/users'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load users');
    return jsonDecode(res.body);
  }

  static Future<void> addUser({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/users'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to add user');
    }
  }

  static Future<void> createTask({
    required String title,
    String? description,
    required List<String> assigneeIds,
    required DateTime dueAt,
    required String priority,
  }) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/tasks/bulk'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        if (description != null && description.isNotEmpty) 'description': description,
        'assigneeIds': assigneeIds,
        'dueAt': dueAt.toUtc().toIso8601String(),
        'priority': priority,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to create task');
    }
  }

  static Future<List<dynamic>> allTasks({
    String status = 'ACTIVE',
    DateTime? from,
    DateTime? to,
    String? assigneeId,
  }) async {
    final res = await http.get(
      _listUri('/api/tasks/all', status: status, from: from, to: to, assigneeId: assigneeId),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load tasks');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> stats() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/tasks/stats'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load stats');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> checklists({
    String status = 'ACTIVE',
    DateTime? from,
    DateTime? to,
    String? assigneeId,
  }) async {
    final res = await http.get(
      _listUri('/api/checklists', status: status, from: from, to: to, assigneeId: assigneeId),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load checklists');
    return jsonDecode(res.body);
  }

  static Future<void> createChecklist({
    required String title,
    required String assigneeId,
    required String recurrence,
    required String timeOfDay,
    int? weekday,
    int? dayOfMonth,
    String priority = 'NORMAL',
  }) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/checklists'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'assigneeId': assigneeId,
        'recurrence': recurrence,
        'timeOfDay': timeOfDay,
        if (weekday != null) 'weekday': weekday,
        if (dayOfMonth != null) 'dayOfMonth': dayOfMonth,
        'priority': priority,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to create checklist');
    }
  }

  static Future<void> toggleChecklist(String id) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/checklists/$id/toggle'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to toggle');
  }

  static Future<List<dynamic>> flows() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/fms/flows'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load flows');
    return jsonDecode(res.body);
  }

  static Future<void> createFlow({
    required String name,
    required String prefix,
    required String itemLabel,
    required List<Map<String, dynamic>> stages,
  }) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/fms/flows'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'prefix': prefix,
        'itemLabel': itemLabel,
        'stages': stages,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to create flow');
    }
  }

  static Future<void> createOrder(String flowId) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/fms/flows/$flowId/orders'),
      headers: _headers,
    );
    if (res.statusCode != 201) throw Exception('Failed to create order');
  }

  static Future<List<dynamic>> orders({
    String status = 'ACTIVE',
    DateTime? from,
    DateTime? to,
    String? assigneeId,
  }) async {
    final res = await http.get(
      _listUri('/api/fms/orders', status: status, from: from, to: to, assigneeId: assigneeId),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load orders');
    return jsonDecode(res.body);
  }

  static Future<void> completeStage(
    String orderStageId,
    Map<String, dynamic> data, {
    String? remarks,
  }) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/fms/orderstages/$orderStageId/complete'),
      headers: _headers,
      body: jsonEncode({
        'data': data,
        if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to complete stage');
    }
  }

  static Future<String> uploadImage(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${Config.apiBase}/api/uploads'),
    );
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final decoded = jsonDecode(res.body);
    if (res.statusCode != 201) {
      throw Exception(decoded['error'] ?? 'Failed to upload image');
    }
    return decoded['url'] as String;
  }

  static Future<Map<String, dynamic>> orderHistory(String orderId) async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/fms/orders/$orderId/history'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load order history');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> bottlenecks() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/fms/bottlenecks'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load bottlenecks');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> skus({String? search, String? category, String status = 'ALL'}) async {
    final uri = Uri.parse('${Config.apiBase}/api/inventory/skus').replace(queryParameters: {
      'status': status,
      if (search != null && search.isNotEmpty) 'search': search,
      if (category != null && category.isNotEmpty) 'category': category,
    });
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load inventory');
    return jsonDecode(res.body);
  }

  static Future<void> createSku({
    required String name,
    required String code,
    String? category,
    String unit = 'pcs',
    double? currentStock,
    double? minStock,
    double? maxStock,
    double? unitCost,
  }) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/inventory/skus'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'code': code,
        if (category != null && category.isNotEmpty) 'category': category,
        'unit': unit,
        if (currentStock != null) 'currentStock': currentStock,
        if (minStock != null) 'minStock': minStock,
        if (maxStock != null) 'maxStock': maxStock,
        if (unitCost != null) 'unitCost': unitCost,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to create SKU');
    }
  }

  static Future<void> updateSku(String id, Map<String, dynamic> changes) async {
    final res = await http.patch(
      Uri.parse('${Config.apiBase}/api/inventory/skus/$id'),
      headers: _headers,
      body: jsonEncode(changes),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to update SKU');
    }
  }

  static Future<void> recordMovement({
    required String skuId,
    required String type,
    required double quantity,
    String? reason,
  }) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/inventory/skus/$skuId/movement'),
      headers: _headers,
      body: jsonEncode({
        'type': type,
        'quantity': quantity,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to record movement');
    }
  }

  static Future<Map<String, dynamic>> skuHistory(String skuId) async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/inventory/skus/$skuId/history'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load history');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> inventorySummary() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/inventory/summary'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load inventory summary');
    return jsonDecode(res.body);
  }
}