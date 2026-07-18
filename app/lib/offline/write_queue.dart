import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class QueuedAction {
  final String id;
  final String type; // MARK_DONE | STOCK_MOVEMENT | COMPLETE_STAGE
  final Map<String, dynamic> payload;
  final String createdAt;

  QueuedAction({required this.id, required this.type, required this.payload, required this.createdAt});

  Map<String, dynamic> toJson() => {'id': id, 'type': type, 'payload': payload, 'createdAt': createdAt};
  factory QueuedAction.fromJson(Map<String, dynamic> j) => QueuedAction(
        id: j['id'] as String,
        type: j['type'] as String,
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        createdAt: j['createdAt'] as String,
      );
}

// Thrown by Api write methods when a call is queued for later instead of
// failing outright — callers treat this as a (deferred) success and update
// their UI optimistically.
class OfflineQueuedException implements Exception {
  final String message;
  OfflineQueuedException([this.message = 'Saved offline — will sync when back online']);
  @override
  String toString() => message;
}

bool isConnectivityError(Object e) {
  return e is SocketException || e is TimeoutException || e is http.ClientException;
}

// Pending write actions taken while offline — flushed in FIFO order once
// connectivity returns. Deliberately simple: last-write-wins, no retry
// backoff tuning. The one hard rule: never lose or duplicate a queued action.
class WriteQueue {
  static const _key = 'write_queue';
  static final ValueNotifier<int> pendingCount = ValueNotifier(0);
  static final ValueNotifier<bool> syncing = ValueNotifier(false);
  static const _uuid = Uuid();

  static Future<List<QueuedAction>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(QueuedAction.fromJson).toList();
  }

  static Future<void> _save(List<QueuedAction> actions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(actions.map((a) => a.toJson()).toList()));
    pendingCount.value = actions.length;
  }

  static Future<void> init() async {
    pendingCount.value = (await _load()).length;
  }

  static Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    final actions = await _load();
    actions.add(QueuedAction(
      id: _uuid.v4(), type: type, payload: payload, createdAt: DateTime.now().toIso8601String(),
    ));
    await _save(actions);
  }

  // Replays queued actions via [executor] (which must call the RAW api call,
  // not the queue-on-failure wrapper). Stops — preserving remaining order —
  // on the first connectivity failure; drops an action only if the server
  // rejects it outright (a logical error that retrying won't fix).
  static Future<void> flush(Future<void> Function(QueuedAction) executor) async {
    if (syncing.value) return;
    var actions = await _load();
    if (actions.isEmpty) return;

    syncing.value = true;
    try {
      while (actions.isNotEmpty) {
        final next = actions.first;
        try {
          await executor(next);
          actions = actions.sublist(1);
          await _save(actions);
        } catch (e) {
          if (isConnectivityError(e)) break; // still offline — retry later
          actions = actions.sublist(1); // server rejected it — drop, keep going
          await _save(actions);
        }
      }
    } finally {
      syncing.value = false;
    }
  }
}
