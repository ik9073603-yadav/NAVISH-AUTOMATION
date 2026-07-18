import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'offline/offline_store.dart';
import 'offline/write_queue.dart';

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

  static const _readTimeout = Duration(seconds: 8);

  // Fetches and caches a GET result under [cacheKey]. On a connectivity
  // failure, falls back to the last-cached value instead of surfacing an
  // error or hanging — this is what keeps shop-floor screens usable offline.
  // Any other (non-connectivity) failure still throws normally.
  static Future<T> _cachedGet<T>(String cacheKey, Future<T> Function() fetch) async {
    try {
      final result = await fetch().timeout(_readTimeout);
      await OfflineStore.put(cacheKey, result);
      return result;
    } catch (e) {
      if (isConnectivityError(e)) {
        final cached = await OfflineStore.get(cacheKey);
        if (cached != null) return cached as T;
      }
      rethrow;
    }
  }

  // Runs a write call; if it fails due to connectivity, queues it for later
  // sync and signals the caller via OfflineQueuedException instead of the
  // real error, so the UI can proceed optimistically.
  static Future<void> _writeOrQueue(String actionType, Map<String, dynamic> payload, Future<void> Function() call) async {
    try {
      await call().timeout(_readTimeout);
    } catch (e) {
      if (isConnectivityError(e)) {
        await WriteQueue.enqueue(actionType, payload);
        throw OfflineQueuedException();
      }
      rethrow;
    }
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
    return _cachedGet('myTasks:$status', () async {
      final res = await http.get(
        _listUri('/api/tasks/my', status: status, from: from, to: to),
        headers: _headers,
      );
      if (res.statusCode != 200) throw Exception('Failed to load tasks');
      return jsonDecode(res.body) as List<dynamic>;
    });
  }

  static Future<void> _rawMarkDone(String taskId) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/tasks/$taskId/done'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to mark done');
  }

  static Future<void> markDone(String taskId) async {
    await _writeOrQueue('MARK_DONE', {'taskId': taskId}, () => _rawMarkDone(taskId));
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
    String? phone,
  }) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/users'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to add user');
    }
  }

  static Future<void> updateInventoryPermissions(
    String userId, {
    required bool canStockIn,
    required bool canStockOut,
  }) async {
    final res = await http.patch(
      Uri.parse('${Config.apiBase}/api/users/$userId/inventory-permissions'),
      headers: _headers,
      body: jsonEncode({'canStockIn': canStockIn, 'canStockOut': canStockOut}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to update permissions');
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
    return _cachedGet('checklists:$status', () async {
      final res = await http.get(
        _listUri('/api/checklists', status: status, from: from, to: to, assigneeId: assigneeId),
        headers: _headers,
      );
      if (res.statusCode != 200) throw Exception('Failed to load checklists');
      return jsonDecode(res.body) as List<dynamic>;
    });
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
    return _cachedGet('orders:$status', () async {
      final res = await http.get(
        _listUri('/api/fms/orders', status: status, from: from, to: to, assigneeId: assigneeId),
        headers: _headers,
      );
      if (res.statusCode != 200) throw Exception('Failed to load orders');
      return jsonDecode(res.body) as List<dynamic>;
    });
  }

  static Future<void> _rawCompleteStage(
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

  static Future<void> completeStage(
    String orderStageId,
    Map<String, dynamic> data, {
    String? remarks,
  }) async {
    await _writeOrQueue(
      'COMPLETE_STAGE',
      {'orderStageId': orderStageId, 'data': data, if (remarks != null) 'remarks': remarks},
      () => _rawCompleteStage(orderStageId, data, remarks: remarks),
    );
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

  // Flow analytics: KPI counts + drill-down lists (see fms.dart's Analytics segment).
  static Future<Map<String, dynamic>> fmsAnalyticsSummary() async {
    return _cachedGet('fmsAnalyticsSummary', () async {
      final res = await http.get(
        Uri.parse('${Config.apiBase}/api/fms/analytics/summary'),
        headers: _headers,
      );
      if (res.statusCode != 200) throw Exception('Failed to load flow analytics summary');
      return jsonDecode(res.body) as Map<String, dynamic>;
    });
  }

  // category: PENDING | COMPLETED | DELAYED | ONTIME
  static Future<List<dynamic>> fmsAnalyticsOrders(
    String category, {
    String? search,
    DateTime? from,
    DateTime? to,
  }) async {
    final uri = Uri.parse('${Config.apiBase}/api/fms/analytics/orders').replace(queryParameters: {
      'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    });
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load orders');
    return jsonDecode(res.body) as List<dynamic>;
  }

  static Future<List<dynamic>> skus({String? search, String? category, String status = 'ALL'}) async {
    return _cachedGet('skus:$status:${search ?? ''}:${category ?? ''}', () async {
      final uri = Uri.parse('${Config.apiBase}/api/inventory/skus').replace(queryParameters: {
        'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (category != null && category.isNotEmpty) 'category': category,
      });
      final res = await http.get(uri, headers: _headers);
      if (res.statusCode != 200) throw Exception('Failed to load inventory');
      return jsonDecode(res.body) as List<dynamic>;
    });
  }

  static Future<void> createSku({
    required String name,
    String? code,
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
        if (code != null && code.isNotEmpty) 'code': code,
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

  static Future<void> _rawRecordMovement({
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

  static Future<void> recordMovement({
    required String skuId,
    required String type,
    required double quantity,
    String? reason,
  }) async {
    await _writeOrQueue(
      'STOCK_MOVEMENT',
      {'skuId': skuId, 'type': type, 'quantity': quantity, if (reason != null) 'reason': reason},
      () => _rawRecordMovement(skuId: skuId, type: type, quantity: quantity, reason: reason),
    );
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

  static Future<void> registerDevice(String token, {required String platform}) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/devices'),
      headers: _headers,
      body: jsonEncode({'token': token, 'platform': platform}),
    );
    if (res.statusCode != 201) throw Exception('Failed to register device');
  }

  static Future<void> unregisterDevice(String token) async {
    final res = await http.delete(
      Uri.parse('${Config.apiBase}/api/devices'),
      headers: _headers,
      body: jsonEncode({'token': token}),
    );
    if (res.statusCode != 200) throw Exception('Failed to unregister device');
  }

  static Future<void> updateMyPhone(String? phone) async {
    await updateMe(phone: phone);
  }

  // Self-service profile edits — any field left null (not passed) is left
  // untouched server-side. Pass an empty string to clear a nullable field.
  static Future<Map<String, dynamic>> updateMe({
    String? phone,
    String? name,
    String? nickname,
    String? designation,
    String? language,
    String? photoUrl,
  }) async {
    final body = <String, dynamic>{};
    if (phone != null) body['phone'] = phone.isEmpty ? null : phone;
    if (name != null && name.isNotEmpty) body['name'] = name;
    if (nickname != null) body['nickname'] = nickname.isEmpty ? null : nickname;
    if (designation != null) body['designation'] = designation.isEmpty ? null : designation;
    if (language != null) body['language'] = language;
    if (photoUrl != null) body['photoUrl'] = photoUrl.isEmpty ? null : photoUrl;

    final res = await http.patch(
      Uri.parse('${Config.apiBase}/api/auth/me'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to update profile');
    }
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> stuckList() async {
    return _cachedGet('stuckList', () async {
      final res = await http.get(
        Uri.parse('${Config.apiBase}/api/stuck'),
        headers: _headers,
      );
      if (res.statusCode != 200) throw Exception('Failed to load stuck items');
      return jsonDecode(res.body) as List<dynamic>;
    });
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/settings'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to load settings');
    }
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> updateSettings({
    String? name,
    String? industry,
    String? logoUrl,
    String? timezone,
    List<int>? workingDays,
    String? shiftStart,
    String? shiftEnd,
    List<String>? holidays,
  }) async {
    final res = await http.patch(
      Uri.parse('${Config.apiBase}/api/settings'),
      headers: _headers,
      body: jsonEncode({
        if (name != null) 'name': name,
        if (industry != null) 'industry': industry.isEmpty ? null : industry,
        if (logoUrl != null) 'logoUrl': logoUrl.isEmpty ? null : logoUrl,
        if (timezone != null) 'timezone': timezone,
        if (workingDays != null) 'workingDays': workingDays,
        if (shiftStart != null) 'shiftStart': shiftStart,
        if (shiftEnd != null) 'shiftEnd': shiftEnd,
        if (holidays != null) 'holidays': holidays,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to update settings');
    }
    return jsonDecode(res.body);
  }

  static Future<void> changePassword(String currentPassword, String newPassword) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/auth/change-password'),
      headers: _headers,
      body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to change password');
    }
  }

  // Public — no auth token needed, called from the login screen.
  static Future<String> requestPasswordReset(String email) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/auth/request-reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Failed to request reset');
    return data['message'] as String;
  }

  static Future<List<dynamic>> resetRequests() async {
    final res = await http.get(
      Uri.parse('${Config.apiBase}/api/auth/reset-requests'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load reset requests');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> approveReset(String requestId) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/auth/reset-requests/$requestId/approve'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to approve reset');
    }
    return jsonDecode(res.body);
  }

  static Future<void> denyReset(String requestId) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/auth/reset-requests/$requestId/deny'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to deny reset');
    }
  }

  static Uri _rangeUri(String path, DateTime from, DateTime to) {
    return Uri.parse('${Config.apiBase}$path').replace(queryParameters: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    });
  }

  static Future<List<dynamic>> analyticsEmployees(DateTime from, DateTime to) async {
    final res = await http.get(_rangeUri('/api/analytics/employees', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load employee analytics');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> analyticsDelegation(DateTime from, DateTime to) async {
    final res = await http.get(_rangeUri('/api/analytics/delegation', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load delegation analytics');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> analyticsChecklists(DateTime from, DateTime to) async {
    final res = await http.get(_rangeUri('/api/analytics/checklists', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load checklist analytics');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> analyticsFms(DateTime from, DateTime to) async {
    final res = await http.get(_rangeUri('/api/analytics/fms', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load flow analytics');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> analyticsInventory(DateTime from, DateTime to) async {
    final res = await http.get(_rangeUri('/api/analytics/inventory', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load inventory analytics');
    return jsonDecode(res.body);
  }

  // ---------------- Superadmin ----------------

  static Future<Map<String, dynamic>> adminOverview() async {
    final res = await http.get(Uri.parse('${Config.apiBase}/api/admin/overview'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load admin overview');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> adminOrgs() async {
    final res = await http.get(Uri.parse('${Config.apiBase}/api/admin/orgs'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load orgs');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> adminOrgDetail(String orgId) async {
    final res = await http.get(Uri.parse('${Config.apiBase}/api/admin/orgs/$orgId'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load org detail');
    return jsonDecode(res.body);
  }

  static Future<bool> adminToggleOrg(String orgId) async {
    final res = await http.post(Uri.parse('${Config.apiBase}/api/admin/orgs/$orgId/toggle'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to toggle org');
    return jsonDecode(res.body)['enabled'] as bool;
  }

  // ---------------- Exports ----------------
  // Returns raw file bytes + a suggested filename; caller shares/saves them.

  static Future<(Uint8List, String)> exportFms(String flowId, String format, {DateTime? from, DateTime? to}) async {
    final uri = Uri.parse('${Config.apiBase}/api/export/fms/$flowId').replace(queryParameters: {
      'format': format,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    });
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to export flow report');
    return (res.bodyBytes, 'flow-report.$format');
  }

  static Future<(Uint8List, String)> exportInventoryMovements(String format, {DateTime? from, DateTime? to}) async {
    final uri = Uri.parse('${Config.apiBase}/api/export/inventory/movements').replace(queryParameters: {
      'format': format,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    });
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to export inventory movements');
    return (res.bodyBytes, 'inventory-movements.$format');
  }

  static Future<(Uint8List, String)> exportTasks(String format, {DateTime? from, DateTime? to}) async {
    final uri = Uri.parse('${Config.apiBase}/api/export/tasks').replace(queryParameters: {
      'format': format,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    });
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to export tasks report');
    return (res.bodyBytes, 'tasks-report.$format');
  }

  static Future<(Uint8List, String)> exportBackup() async {
    final res = await http.get(Uri.parse('${Config.apiBase}/api/export/backup'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to export backup');
    return (res.bodyBytes, 'navish-backup.zip');
  }

  // ---------------- Signup ----------------

  static Future<Map<String, dynamic>> signup({
    required String companyName,
    required String ownerName,
    required String email,
    required String password,
    String? phone,
    required bool acceptedTerms,
  }) async {
    final res = await http.post(
      Uri.parse('${Config.apiBase}/api/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'companyName': companyName,
        'ownerName': ownerName,
        'email': email,
        'password': password,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'acceptedTerms': acceptedTerms,
      }),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(data['error'] ?? 'Signup failed');
    await _saveToken(data['token']);
    return data;
  }

  // ---------------- Templates ----------------

  static Future<List<dynamic>> templates() async {
    final res = await http.get(Uri.parse('${Config.apiBase}/api/templates'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load templates');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> applyTemplate(String id) async {
    final res = await http.post(Uri.parse('${Config.apiBase}/api/templates/$id/apply'), headers: _headers);
    final data = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(data['error'] ?? 'Failed to apply template');
    return data;
  }

  static Future<void> assignStage(String stageId, {String? responsibleId}) async {
    final res = await http.patch(
      Uri.parse('${Config.apiBase}/api/fms/stages/$stageId'),
      headers: _headers,
      body: jsonEncode({'responsibleId': responsibleId}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to assign stage');
    }
  }

  static Future<void> updateChecklistRule(String ruleId, {String? assigneeId, bool? active}) async {
    final res = await http.patch(
      Uri.parse('${Config.apiBase}/api/checklists/$ruleId'),
      headers: _headers,
      body: jsonEncode({
        if (assigneeId != null) 'assigneeId': assigneeId,
        if (active != null) 'active': active,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to update checklist');
    }
  }

  // ---------------- Account deletion (Feature 176) ----------------

  static Future<void> requestAccountDeletion() async {
    final res = await http.post(Uri.parse('${Config.apiBase}/api/auth/request-deletion'), headers: _headers);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to request deletion');
    }
  }

  static Future<List<dynamic>> deletionRequests() async {
    final res = await http.get(Uri.parse('${Config.apiBase}/api/auth/deletion-requests'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load deletion requests');
    return jsonDecode(res.body);
  }

  static Future<void> completeDeletionRequest(String id) async {
    final res = await http.post(Uri.parse('${Config.apiBase}/api/auth/deletion-requests/$id/complete'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to complete deletion request');
  }

  static Future<void> denyDeletionRequest(String id) async {
    final res = await http.post(Uri.parse('${Config.apiBase}/api/auth/deletion-requests/$id/deny'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to deny deletion request');
  }

  // ---------------- Offline write-queue sync ----------------
  // Replays queued actions via the RAW (non-queueing) calls — the engine
  // itself never runs offline, this just replays the user's own writes.
  static Future<void> flushQueue() async {
    await WriteQueue.flush((action) async {
      switch (action.type) {
        case 'MARK_DONE':
          await _rawMarkDone(action.payload['taskId'] as String);
          break;
        case 'STOCK_MOVEMENT':
          await _rawRecordMovement(
            skuId: action.payload['skuId'] as String,
            type: action.payload['type'] as String,
            quantity: (action.payload['quantity'] as num).toDouble(),
            reason: action.payload['reason'] as String?,
          );
          break;
        case 'COMPLETE_STAGE':
          await _rawCompleteStage(
            action.payload['orderStageId'] as String,
            Map<String, dynamic>.from(action.payload['data'] as Map),
            remarks: action.payload['remarks'] as String?,
          );
          break;
      }
    });
  }
}