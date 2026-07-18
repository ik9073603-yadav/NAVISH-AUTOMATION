import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../offline/write_queue.dart';

// Tracks online/offline state and flushes the write queue the moment
// connectivity returns. The automation engine itself never runs offline —
// this is only about the app staying usable and queuing the user's own writes.
class ConnectivityService {
  static final ValueNotifier<bool> isOnline = ValueNotifier(true);
  static bool _started = false;

  static Future<void> start(Future<void> Function() onReconnect) async {
    if (_started) return;
    _started = true;

    final initial = await Connectivity().checkConnectivity();
    isOnline.value = !initial.contains(ConnectivityResult.none);

    Connectivity().onConnectivityChanged.listen((results) {
      final nowOnline = !results.contains(ConnectivityResult.none);
      final wasOffline = !isOnline.value;
      isOnline.value = nowOnline;
      if (nowOnline && wasOffline) onReconnect();
    });

    if (isOnline.value && WriteQueue.pendingCount.value > 0) onReconnect();
  }
}
