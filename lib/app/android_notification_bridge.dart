import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 与 Android 端 [NotificationListenerBridge] 中的通道名保持一致。
///
/// 在非 Android 平台（如 Windows 桌面）上所有方法均为安全空实现，避免
/// `MissingPluginException` 与无效导入。
class AndroidNotificationBridge {
  AndroidNotificationBridge._();

  static const MethodChannel _method = MethodChannel(
    'com.example.quick_notification/notification_listener',
  );
  static const EventChannel _event = EventChannel(
    'com.example.quick_notification/notification_listener_events',
  );

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isListenerEnabled() async {
    if (!_supported) return false;
    try {
      final result = await _method.invokeMethod<bool>('isListenerEnabled');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openListenerSettings() async {
    if (!_supported) return;
    try {
      await _method.invokeMethod<void>('openListenerSettings');
    } on MissingPluginException {
      // 桌面或未嵌入插件时忽略
    } catch (_) {
      // ignore
    }
  }

  /// 仅在已开启通知监听权限且运行在 Android 时才会有事件。
  static Stream<Map<String, dynamic>> notifications() {
    if (!_supported) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    return _event.receiveBroadcastStream().map((dynamic event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{};
    }).where((m) => m.isNotEmpty);
  }
}
