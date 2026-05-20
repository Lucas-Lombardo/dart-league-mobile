import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/presence_service.dart';

class PresenceProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const Duration _pingInterval = Duration(seconds: 30);

  Timer? _timer;
  int? _onlineCount;
  bool _started = false;

  int? get onlineCount => _onlineCount;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _pingNow();
    _timer = Timer.periodic(_pingInterval, (_) => _pingNow());
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    if (_onlineCount != null) {
      _onlineCount = null;
      notifyListeners();
    }
  }

  Future<void> _pingNow() async {
    final count = await PresenceService.ping();
    if (count != null && count != _onlineCount) {
      _onlineCount = count;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    if (state == AppLifecycleState.resumed) {
      // Refresh immediately on resume; the periodic timer keeps running but
      // a manual ping avoids a 30s-stale UI.
      _pingNow();
      _timer ??= Timer.periodic(_pingInterval, (_) => _pingNow());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Stop pings while in background to avoid pointless network traffic.
      // The user's entry will expire from Redis after STALE_MS and they'll
      // be counted as offline — which is what we want.
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
