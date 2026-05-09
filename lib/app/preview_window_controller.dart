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
  }

  Future<void> dispose() async {
    await _actionChannel.setMethodCallHandler(null);
  }

  Future<void> showNotification(AppNotification notification) async {
    final window = _previewWindow ?? await _findOrCreatePreviewWindow();
    _previewWindow = window;

    await _invokePreviewWindowMethodWithRetry(window, 'show_preview', <String, dynamic>{
      'notification': notification.toJson(),
    });
    await window.show();
  }

  Future<void> hidePreview() async {
    final window = _previewWindow;
    if (window == null) return;
    await _invokePreviewWindowMethodWithRetry(window, 'hide_preview');
    await window.hide();
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

  Future<void> _invokePreviewWindowMethodWithRetry(
    WindowController window,
    String method, [
    dynamic arguments,
  ]) async {
    const maxAttempts = 12;
    for (var i = 0; i < maxAttempts; i++) {
      try {
        await window.invokeMethod(method, arguments);
        return;
      } catch (_) {
        if (i == maxAttempts - 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }
}
