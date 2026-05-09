import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket 连接状态。
enum WsStatus { disconnected, connecting, connected, reconnecting }

/// 带指数退避自动重连的 WebSocket 管理器。
///
/// 使用方式：
/// ```dart
/// final manager = WebSocketManager(
///   onMessage: (raw) { ... },
///   onStatusChanged: (status) => setState(() => _wsStatus = status),
/// );
/// manager.connect('ws://127.0.0.1:8765/notifications');
/// ```
class WebSocketManager {
  WebSocketManager({
    required this.onMessage,
    required this.onStatusChanged,
  });

  final void Function(String raw) onMessage;
  final void Function(WsStatus status) onStatusChanged;

  static const Duration _initialDelay = Duration(seconds: 1);
  static const Duration _maxDelay = Duration(seconds: 30);

  String? _url;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Duration _currentDelay = _initialDelay;

  /// 当前连接状态（只读）。
  WsStatus get status => _status;
  WsStatus _status = WsStatus.disconnected;

  bool _disposed = false;
  bool _manualDisconnect = false;

  // ── 公开接口 ──────────────────────────────────────────

  /// 连接到指定 URL，若已有连接则先断开。
  void connect(String url) {
    _manualDisconnect = false;
    _url = url;
    _currentDelay = _initialDelay;
    _doConnect(isReconnect: false);
  }

  /// 主动断开并停止自动重连。
  void disconnect() {
    _manualDisconnect = true;
    _cleanup();
    _setStatus(WsStatus.disconnected);
  }

  /// 释放所有资源（页面 dispose 时调用）。
  void dispose() {
    _disposed = true;
    _cleanup();
  }

  // ── 内部实现 ──────────────────────────────────────────

  void _doConnect({required bool isReconnect}) {
    if (_disposed) return;
    _cleanup(keepUrl: true);
    _setStatus(isReconnect ? WsStatus.reconnecting : WsStatus.connecting);

    final url = _url;
    if (url == null || url.isEmpty) {
      _setStatus(WsStatus.disconnected);
      return;
    }

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;

      channel.ready.then((_) {
        if (_disposed) return;
        _currentDelay = _initialDelay; // 连上了，重置退避
        _setStatus(WsStatus.connected);
      }).catchError((_) {
        _onError();
      });

      _subscription = channel.stream.listen(
        (raw) {
          if (_disposed) return;
          onMessage(raw.toString());
        },
        onError: (_) => _onError(),
        onDone: () => _onError(),
        cancelOnError: false,
      );
    } catch (_) {
      _onError();
    }
  }

  void _onError() {
    if (_disposed || _manualDisconnect) return;
    _cleanup(keepUrl: true);
    _setStatus(WsStatus.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_currentDelay, () {
      if (_disposed || _manualDisconnect) return;
      _currentDelay = _nextDelay(_currentDelay);
      _doConnect(isReconnect: true);
    });
  }

  Duration _nextDelay(Duration current) {
    final next = Duration(seconds: current.inSeconds * 2);
    return next > _maxDelay ? _maxDelay : next;
  }

  void _cleanup({bool keepUrl = false}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    if (!keepUrl) _url = null;
  }

  void _setStatus(WsStatus s) {
    if (_status == s) return;
    _status = s;
    if (!_disposed) onStatusChanged(s);
  }
}