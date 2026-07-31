import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'offline/offline_store.dart';
import 'offline/write_queue.dart';

// http.MultipartFile.fromBytes defaults to application/octet-stream when no
// contentType is given — the backend's multer fileFilter rejects anything
// whose Content-Type doesn't start with "image/", so every upload failed
// with 400 regardless of platform. Falls back to guessing from the
// extension for the rare case a picker doesn't supply a mimeType.
String _guessImageMimeType(String filename) {
  final ext = filename.toLowerCase().split('.').last;
  switch (ext) {
    case 'png': return 'image/png';
    case 'webp': return 'image/webp';
    case 'gif': return 'image/gif';
    case 'heic': return 'image/heic';
    case 'heif': return 'image/heif';
    default: return 'image/jpeg';
  }
}

// Thrown by Api.login when the account exists and the password is correct,
// but the email hasn't been OTP-verified yet (mid-signup, or an owner-added
// employee's first login). Callers should route to the OTP-entry screen
// instead of showing this as a plain error.
class EmailNotVerifiedException implements Exception {
  final String email;
  final String message;
  EmailNotVerifiedException(this.email, this.message);
  @override
  String toString() => message;
}

// Thrown by Api.login when the account already has an active session
// elsewhere. The caller should confirm with the user, then retry the same
// login with confirm:true to proceed (this rotates the session and signs
// the other device out).
class SessionActiveException implements Exception {
  final String message;
  SessionActiveException(this.message);
  @override
  String toString() => message;
}

// Every request routes through this client so a "session ended" 401 (another
// device logged in and rotated this account's session) can be caught in ONE
// place instead of every individual call site — see requireAuth on the
// backend for where this response comes from.
class _SessionAwareClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    if (res.statusCode == 401) {
      final bytes = await res.stream.toBytes();
      if (utf8.decode(bytes).contains('session ended')) {
        Api._handleSessionEnded();
      }
      return http.StreamedResponse(
        Stream.value(bytes),
        res.statusCode,
        contentLength: bytes.length,
        request: res.request,
        headers: res.headers,
      );
    }
    return res;
  }
}

// Every screen's `_load()` catch block routes through this instead of
// calling ScaffoldMessenger directly — a screen whose own API call failed
// ONLY because the session already ended has nothing useful to add on top
// of the forced-logout redirect (see Api._handleSessionEnded) that's
// already taking the user to LoginScreen with its own message.
void showApiError(BuildContext context, Object error) {
  if (Api.sessionEnded.value) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
}

class Api {
  static final http.Client _client = _SessionAwareClient();

  // Set once at app startup (main.dart) so Api can force navigation back to
  // the login screen without importing it (main.dart imports api.dart).
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static Widget Function(String message) loginScreenBuilder =
      (_) => throw StateError('Api.loginScreenBuilder not set');
  static bool _handlingSessionEnd = false;

  // Flips true the instant a "session ended" 401 is seen — screens that hold
  // now-stale data (HomeScreen) watch this to blank themselves immediately,
  // rather than falling through to render normal chrome around empty/null
  // data while the actual navigation to LoginScreen is still in flight.
  static final ValueNotifier<bool> sessionEnded = ValueNotifier(false);

  static void _handleSessionEnded() {
    if (_handlingSessionEnd) return;
    _handlingSessionEnd = true;
    sessionEnded.value = true;
    // This device got kicked out — the OTHER session (the one that
    // superseded it) is still active, so don't clear sessionActive.
    logout(notifyServer: false);
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => loginScreenBuilder(
          'Logged out: this account signed in on another device',
        ),
      ),
      (route) => false,
    );
  }

  static String? _token;

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
  }

  static Future<void> _saveToken(String token) async {
    _token = token;
    _handlingSessionEnd = false;
    sessionEnded.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  // notifyServer is false only for a forced kick-out (this device's session
  // got superseded by a newer login elsewhere) — that other session is still
  // active, so it must NOT be cleared just because this device is logging
  // out locally. A real user-initiated logout (the default) clears it so the
  // next login on this account doesn't wrongly warn "already active".
  static Future<void> logout({bool notifyServer = true}) async {
    if (notifyServer && _token != null) {
      try {
        await _client.post(Uri.parse('${Config.apiBase}/api/auth/logout'), headers: _headers);
      } catch (_) {
        // Best-effort — still clear local state below even if this fails.
      }
    }
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

  static Future<Map<String, dynamic>> login(String email, String password, {bool confirm = false}) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password, if (confirm) 'confirm': true}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode == 403 && data['error'] == 'EMAIL_NOT_VERIFIED') {
      throw EmailNotVerifiedException(
        (data['email'] as String?) ?? email,
        (data['message'] as String?) ?? 'Verify your email to continue',
      );
    }
    if (res.statusCode == 409 && data['error'] == 'SESSION_ACTIVE') {
      throw SessionActiveException(
        (data['message'] as String?) ??
            'Already active on another device. Log in here and sign out there?',
      );
    }
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Login failed');
    await _saveToken(data['token']);
    return data;
  }

  // ---------------- Email OTP verification (signup + first-login) ----------------

  static Future<Map<String, dynamic>> verifyOtp(String email, String code) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Invalid or expired code');
    await _saveToken(data['token']);
    return data;
  }

  static Future<String> resendOtp(String email) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/auth/resend-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Failed to resend code');
    return (data['message'] as String?) ?? 'A new code has been sent.';
  }

  // ---------------- Self-service forgot/reset password (email OTP) ----------------

  static Future<String> forgotPasswordOtp(String email) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Failed to send code');
    return (data['message'] as String?) ?? 'If an account exists for that email, a code has been sent.';
  }

  static Future<void> resetPasswordOtp(String email, String code, String newPassword) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code, 'newPassword': newPassword}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Failed to reset password');
  }

  static Future<Map<String, dynamic>> me() async {
    final res = await _client.get(
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
      final res = await _client.get(
        _listUri('/api/tasks/my', status: status, from: from, to: to),
        headers: _headers,
      );
      if (res.statusCode != 200) throw Exception('Failed to load tasks');
      return jsonDecode(res.body) as List<dynamic>;
    });
  }

  static Future<void> _rawMarkDone(String taskId) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/tasks/$taskId/done'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to mark done');
  }

  static Future<void> markDone(String taskId) async {
    await _writeOrQueue('MARK_DONE', {'taskId': taskId}, () => _rawMarkDone(taskId));
  }

  static Future<void> markStuck(String taskId, String reason) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/tasks/$taskId/stuck'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    if (res.statusCode != 200) throw Exception('Failed to mark stuck');
  }

  static Future<List<dynamic>> notifications() async {
    final res = await _client.get(
      Uri.parse('${Config.apiBase}/api/tasks/notifications'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load notifications');
    return jsonDecode(res.body);
  }

  static Future<void> markNotificationsRead() async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/tasks/notifications/read'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to mark notifications read');
  }
  static Future<List<dynamic>> users() async {
    final res = await _client.get(
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
    final res = await _client.post(
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
    final res = await _client.patch(
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
    final res = await _client.post(
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
    final res = await _client.get(
      _listUri('/api/tasks/all', status: status, from: from, to: to, assigneeId: assigneeId),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load tasks');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> stats() async {
    final res = await _client.get(
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
      final res = await _client.get(
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
    final res = await _client.post(
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
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/checklists/$id/toggle'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to toggle');
  }

  static Future<List<dynamic>> flows() async {
    final res = await _client.get(
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
    final res = await _client.post(
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

  static Future<void> createOrder(String flowId, {double? orderValue}) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/fms/flows/$flowId/orders'),
      headers: _headers,
      body: jsonEncode({if (orderValue != null) 'orderValue': orderValue}),
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
      final res = await _client.get(
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
    final res = await _client.post(
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

  static Future<String> uploadImage(Uint8List bytes, String filename, {String? mimeType}) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${Config.apiBase}/api/uploads'),
    );
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: MediaType.parse(mimeType ?? _guessImageMimeType(filename)),
    ));

    final streamed = await _client.send(req);
    final res = await http.Response.fromStream(streamed);
    final decoded = jsonDecode(res.body);
    if (res.statusCode != 201) {
      throw Exception(decoded['error'] ?? 'Failed to upload image');
    }
    return decoded['url'] as String;
  }

  static Future<Map<String, dynamic>> orderHistory(String orderId) async {
    final res = await _client.get(
      Uri.parse('${Config.apiBase}/api/fms/orders/$orderId/history'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load order history');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> bottlenecks() async {
    final res = await _client.get(
      Uri.parse('${Config.apiBase}/api/fms/bottlenecks'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load bottlenecks');
    return jsonDecode(res.body);
  }

  // Flow analytics: KPI counts + drill-down lists (see fms.dart's Analytics segment).
  static Future<Map<String, dynamic>> fmsAnalyticsSummary() async {
    return _cachedGet('fmsAnalyticsSummary', () async {
      final res = await _client.get(
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
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load orders');
    return jsonDecode(res.body) as List<dynamic>;
  }

  // Cost of Delay: total ₹ lost, most expensive delayed orders, costliest
  // stage/person. Date-filtered by order start date.
  static Future<Map<String, dynamic>> fmsAnalyticsCostOfDelay({DateTime? from, DateTime? to}) async {
    final uri = Uri.parse('${Config.apiBase}/api/fms/analytics/cost-of-delay').replace(queryParameters: {
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    });
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load cost of delay');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> skus({String? search, String? category, String status = 'ALL'}) async {
    return _cachedGet('skus:$status:${search ?? ''}:${category ?? ''}', () async {
      final uri = Uri.parse('${Config.apiBase}/api/inventory/skus').replace(queryParameters: {
        'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (category != null && category.isNotEmpty) 'category': category,
      });
      final res = await _client.get(uri, headers: _headers);
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
    final res = await _client.post(
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
    final res = await _client.patch(
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
    final res = await _client.post(
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
    final res = await _client.get(
      Uri.parse('${Config.apiBase}/api/inventory/skus/$skuId/history'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load history');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> inventorySummary() async {
    final res = await _client.get(
      Uri.parse('${Config.apiBase}/api/inventory/summary'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load inventory summary');
    return jsonDecode(res.body);
  }

  static Future<void> registerDevice(String token, {required String platform}) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/devices'),
      headers: _headers,
      body: jsonEncode({'token': token, 'platform': platform}),
    );
    if (res.statusCode != 201) throw Exception('Failed to register device');
  }

  static Future<void> unregisterDevice(String token) async {
    final res = await _client.delete(
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

    final res = await _client.patch(
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
      final res = await _client.get(
        Uri.parse('${Config.apiBase}/api/stuck'),
        headers: _headers,
      );
      if (res.statusCode != 200) throw Exception('Failed to load stuck items');
      return jsonDecode(res.body) as List<dynamic>;
    });
  }

  // Company Health Score — one 0-100 number + transparent component
  // breakdown (see health-score.service.ts on the backend for the formula).
  static Future<Map<String, dynamic>> healthScore({int days = 7}) async {
    return _cachedGet('healthScore:$days', () async {
      final res = await _client.get(
        Uri.parse('${Config.apiBase}/api/health-score').replace(queryParameters: {'days': '$days'}),
        headers: _headers,
      );
      if (res.statusCode != 200) throw Exception('Failed to load health score');
      return jsonDecode(res.body) as Map<String, dynamic>;
    });
  }

  static Future<Map<String, dynamic>> getSettings() async {
    final res = await _client.get(
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
    double? delayCostPerHour,
    bool clearDelayCostPerHour = false,
  }) async {
    final res = await _client.patch(
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
        if (clearDelayCostPerHour) 'delayCostPerHour': null
        else if (delayCostPerHour != null) 'delayCostPerHour': delayCostPerHour,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to update settings');
    }
    return jsonDecode(res.body);
  }

  static Future<void> changePassword(String currentPassword, String newPassword) async {
    final res = await _client.post(
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
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/auth/request-reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Failed to request reset');
    return data['message'] as String;
  }

  static Future<List<dynamic>> resetRequests() async {
    final res = await _client.get(
      Uri.parse('${Config.apiBase}/api/auth/reset-requests'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to load reset requests');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> approveReset(String requestId) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/auth/reset-requests/$requestId/approve'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to approve reset');
    }
    return jsonDecode(res.body);
  }

  static Future<void> denyReset(String requestId) async {
    final res = await _client.post(
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
    final res = await _client.get(_rangeUri('/api/analytics/employees', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load employee analytics');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> analyticsDelegation(DateTime from, DateTime to) async {
    final res = await _client.get(_rangeUri('/api/analytics/delegation', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load delegation analytics');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> analyticsChecklists(DateTime from, DateTime to) async {
    final res = await _client.get(_rangeUri('/api/analytics/checklists', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load checklist analytics');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> analyticsDepartments(DateTime from, DateTime to) async {
    final res = await _client.get(_rangeUri('/api/analytics/departments', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load department analytics');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> analyticsFms(DateTime from, DateTime to) async {
    final res = await _client.get(_rangeUri('/api/analytics/fms', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load flow analytics');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> analyticsInventory(DateTime from, DateTime to) async {
    final res = await _client.get(_rangeUri('/api/analytics/inventory', from, to), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load inventory analytics');
    return jsonDecode(res.body);
  }

  // ---------------- AI Assistant ----------------
  // Every call is backend-side: the app never holds or sends a raw provider
  // key, only OUR endpoints, which look up and decrypt the caller's own
  // stored key server-side.

  static Future<Map<String, dynamic>> aiConfigStatus() async {
    final res = await _client.get(Uri.parse('${Config.apiBase}/api/ai/config'), headers: _headers);
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Failed to load AI settings');
    return data;
  }

  static Future<Map<String, dynamic>> aiSaveConfig({
    required String provider,
    required String apiKey,
    String? model,
  }) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/ai/config'),
      headers: _headers,
      body: jsonEncode({'provider': provider, 'apiKey': apiKey, if (model != null && model.isNotEmpty) 'model': model}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Failed to save AI settings');
    return data;
  }

  static Future<void> aiDeleteConfig() async {
    final res = await _client.delete(Uri.parse('${Config.apiBase}/api/ai/config'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to remove AI settings');
  }

  static Future<void> aiTestConnection({
    required String provider,
    required String apiKey,
    String? model,
  }) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/ai/config/test'),
      headers: _headers,
      body: jsonEncode({'provider': provider, 'apiKey': apiKey, if (model != null && model.isNotEmpty) 'model': model}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Connection test failed');
  }

  static Future<String> aiChat({
    required String message,
    List<Map<String, String>> history = const [],
    String feature = 'ASSIST',
  }) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/ai/chat'),
      headers: _headers,
      body: jsonEncode({'message': message, 'history': history, 'feature': feature}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'AI request failed');
    return data['reply'] as String;
  }

  static Future<String> aiInsights({required String screen, required Map<String, dynamic> data}) async {
    final res = await _client.post(
      Uri.parse('${Config.apiBase}/api/ai/insights'),
      headers: _headers,
      body: jsonEncode({'screen': screen, 'data': data}),
    );
    final body = jsonDecode(res.body);
    if (res.statusCode != 200) throw Exception(body['error'] ?? 'Failed to generate insights');
    return body['insight'] as String;
  }

  static Future<Map<String, dynamic>> aiUsage() async {
    final res = await _client.get(Uri.parse('${Config.apiBase}/api/ai/usage'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load AI usage');
    return jsonDecode(res.body);
  }

  // ---------------- Superadmin ----------------

  static Future<Map<String, dynamic>> adminOverview() async {
    final res = await _client.get(Uri.parse('${Config.apiBase}/api/admin/overview'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load admin overview');
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> adminOrgs() async {
    final res = await _client.get(Uri.parse('${Config.apiBase}/api/admin/orgs'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load orgs');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> adminOrgDetail(String orgId) async {
    final res = await _client.get(Uri.parse('${Config.apiBase}/api/admin/orgs/$orgId'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load org detail');
    return jsonDecode(res.body);
  }

  static Future<bool> adminToggleOrg(String orgId) async {
    final res = await _client.post(Uri.parse('${Config.apiBase}/api/admin/orgs/$orgId/toggle'), headers: _headers);
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
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to export flow report');
    return (res.bodyBytes, 'flow-report.$format');
  }

  static Future<(Uint8List, String)> exportInventoryMovements(String format, {DateTime? from, DateTime? to}) async {
    final uri = Uri.parse('${Config.apiBase}/api/export/inventory/movements').replace(queryParameters: {
      'format': format,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    });
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to export inventory movements');
    return (res.bodyBytes, 'inventory-movements.$format');
  }

  static Future<(Uint8List, String)> exportTasks(String format, {DateTime? from, DateTime? to}) async {
    final uri = Uri.parse('${Config.apiBase}/api/export/tasks').replace(queryParameters: {
      'format': format,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
    });
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to export tasks report');
    return (res.bodyBytes, 'tasks-report.$format');
  }

  static Future<(Uint8List, String)> exportBackup() async {
    final res = await _client.get(Uri.parse('${Config.apiBase}/api/export/backup'), headers: _headers);
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
    final res = await _client.post(
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
    // No token yet — the account is unverified until verifyOtp() succeeds.
    return data;
  }

  // ---------------- Templates ----------------

  static Future<List<dynamic>> templates() async {
    final res = await _client.get(Uri.parse('${Config.apiBase}/api/templates'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load templates');
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> applyTemplate(String id) async {
    final res = await _client.post(Uri.parse('${Config.apiBase}/api/templates/$id/apply'), headers: _headers);
    final data = jsonDecode(res.body);
    if (res.statusCode != 201) throw Exception(data['error'] ?? 'Failed to apply template');
    return data;
  }

  static Future<void> assignStage(String stageId, {String? responsibleId}) async {
    final res = await _client.patch(
      Uri.parse('${Config.apiBase}/api/fms/stages/$stageId'),
      headers: _headers,
      body: jsonEncode({'responsibleId': responsibleId}),
    );
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to assign stage');
    }
  }

  static Future<void> updateChecklistRule(String ruleId, {String? assigneeId, bool? active}) async {
    final res = await _client.patch(
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
    final res = await _client.post(Uri.parse('${Config.apiBase}/api/auth/request-deletion'), headers: _headers);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(jsonDecode(res.body)['error'] ?? 'Failed to request deletion');
    }
  }

  static Future<List<dynamic>> deletionRequests() async {
    final res = await _client.get(Uri.parse('${Config.apiBase}/api/auth/deletion-requests'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to load deletion requests');
    return jsonDecode(res.body);
  }

  static Future<void> completeDeletionRequest(String id) async {
    final res = await _client.post(Uri.parse('${Config.apiBase}/api/auth/deletion-requests/$id/complete'), headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to complete deletion request');
  }

  static Future<void> denyDeletionRequest(String id) async {
    final res = await _client.post(Uri.parse('${Config.apiBase}/api/auth/deletion-requests/$id/deny'), headers: _headers);
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