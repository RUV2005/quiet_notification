import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import 'models.dart';

typedef PreviewActionOpenMain = Future<void> Function();

/// 主窗口侧的预览子窗口控制器（创建、更新、接收动作）。
class PreviewWindowController {
  PreviewWindowController({
    required this.onOpenMainRequested,
  });

  static const WindowMethodChannel _actionChannel = WindowMethodChannel(
    'quick_notification_preview_action',
    mode: ChannelMode.unidirectional,
  );

  final PreviewActionOpenMain onOpenMainRequested;

  WindowController? _previewWindow;

  Future<void> initialize() async {
    await _actionChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'copy_text':
          final args = (call.arguments as Map?)?.cast<dynamic, dynamic>() ?? const {};
          final text = (args['text'] ?? '').toString();
          if (text.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: text));
          }
          break;
        case 'open_main':
          await onOpenMainRequested();
          break;
        default:
          break;
      }
      return null;
    });

    _previewWindow = await _findOrCreatePreviewWindow();
    await _waitUntilPreviewInvokerReady(_previewWindow!);
  }

  /// 子窗口 Dart 启动后需先 `setWindowMethodHandler`，否则主窗口 `invokeMethod` 会 CHANNEL_UNREGISTERED。
  Future<void> _waitUntilPreviewInvokerReady(WindowController window) async {
    const step = Duration(milliseconds: 40);
    const maxWait = Duration(seconds: 12);
    final deadline = DateTime.now().add(maxWait);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final ok = await window.invokeMethod<dynamic>('__ready_ack__');
        if (ok == true) return;
      } catch (_) {}
      await Future<void>.delayed(step);
    }
  }

  Future<void> dispose() async {
    await _actionChannel.setMethodCallHandler(null);
  }

  /// 是否成功让子窗口展示预览（失败时调用方可回退到恢复主窗口等）。
  Future<bool> showNotification(AppNotification notification) async {
    try {
      var window = _previewWindow ?? await _findOrCreatePreviewWindow();
      _previewWindow = window;

      var ok = await _invokePreviewWindowMethodWithRetry(
        window,
        'show_preview',
        <String, dynamic>{'notification': notification.toJson()},
      );
      if (!ok) {
        _previewWindow = null;
        window = await _findOrCreatePreviewWindow();
        _previewWindow = window;
        ok = await _invokePreviewWindowMethodWithRetry(
          window,
          'show_preview',
          <String, dynamic>{'notification': notification.toJson()},
        );
      }
      if (!ok) return false;
      await window.show();
      return true;
    } catch (_) {
      _previewWindow = null;
      return false;
    }
  }

  Future<void> hidePreview() async {
    final window = _previewWindow;
    if (window == null) return;
    final ok = await _invokePreviewWindowMethodWithRetry(window, 'hide_preview');
    if (ok) await window.hide();
  }

  Future<WindowController> _findOrCreatePreviewWindow() async {
    final allWindows = await WindowController.getAll();
    for (final controller in allWindows) {
      final type = _windowType(controller.arguments);
      if (type == 'preview') {
        return controller;
      }
    }

    return WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode(<String, dynamic>{'type': 'preview'}),
      ),
    );
  }

  String? _windowType(String raw) {
    if (raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['type'] is String) {
        return data['type'] as String;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _invokePreviewWindowMethodWithRetry(
    WindowController window,
    String method, [
    dynamic arguments,
  ]) async {
    const maxAttempts = 25;
    for (var i = 0; i < maxAttempts; i++) {
      try {
        await window.invokeMethod(method, arguments);
        return true;
      } catch (_) {
        if (i == maxAttempts - 1) return false;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    return false;
  }
}
