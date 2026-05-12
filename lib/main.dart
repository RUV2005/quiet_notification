import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app/home_page.dart';
import 'app/preview_window.dart';

/// 程序入口：初始化窗口管理，并以桌面窗口方式启动 Flutter 应用。
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 本应用几乎无大图资源；收紧全局图片缓存以降低常驻内存（默认上限很大）。
  PaintingBinding.instance.imageCache
    ..maximumSize = 24
    ..maximumSizeBytes = 12 << 20;
  final currentWindow = await WindowController.fromCurrentEngine();
  final type = _windowType(currentWindow.arguments);
  if (type == 'preview') {
    await windowManager.ensureInitialized();
    await currentWindow.setWindowMethodHandler(PreviewCommandBridge.handle);
    runApp(PreviewWindowApp(windowController: currentWindow));
    return;
  }

  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(710, 800),
    minimumSize: Size(560, 620),
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Color(0xFF10131A),
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const NotificationApp());
}

String? _windowType(String raw) {
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['type'] is String) {
      return decoded['type'] as String;
    }
  } catch (_) {}
  return null;
}
