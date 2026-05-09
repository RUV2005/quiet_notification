import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// 主进程 Win32 原生置顶浮窗（由 `windows/runner` 内 MethodChannel + GDI+ 绘制）。
abstract final class NativeFloatPreviewWindows {
  static const MethodChannel _channel =
      MethodChannel('quick_notification/native_float');

  /// 浮窗右上角只显示时刻（`HH:mm`），去掉日期、秒等。
  static String _timeOnlyForPopup(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (s.contains('T')) {
      s = s.split('T').last;
      s = s.split('.').first.split('Z').first.trim();
    } else if (RegExp(r'\d{4}[-/]\d{1,2}[-/]\d').hasMatch(s) && s.contains(' ')) {
      final parts = s.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        s = parts.last;
      }
    }
    final m = RegExp(r'^(\d{1,2}:\d{2})(?::\d{2})?').firstMatch(s.trim());
    if (m != null) {
      return m.group(1)!;
    }
    return s;
  }

  static Future<void> show(AppNotification n) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      final payload = Map<String, dynamic>.from(n.toJson());
      payload['time'] = _timeOnlyForPopup(n.time);
      // 与主列表 [NotificationCardView] 首行一致：应用 · 标题
      payload['header_title'] = '${n.app} · ${n.title}';

      final hasCode = n.code != null && n.code!.trim().isNotEmpty;
      final mainText = hasCode
          ? n.code!.trim()
          : (n.content.trim().isNotEmpty
              ? n.content.trim()
              : n.title.trim());
      payload['code'] = mainText;
      payload['code_label'] = hasCode ? '验证码' : '';

      if (hasCode) {
        final c = n.content.trim();
        if (c.isNotEmpty && c != mainText && !c.contains(mainText)) {
          payload['subtitle'] = n.content;
        } else {
          payload['subtitle'] = '5 分钟内有效，请勿泄露';
        }
      } else {
        payload['subtitle'] = '';
      }

      payload['from_label'] = '来自：${n.app}';
      payload['copy_payload'] = (n.code != null && n.code!.isNotEmpty)
          ? n.code
          : (n.content.isNotEmpty ? n.content : n.title);
      await _channel.invokeMethod<void>('show', payload);
    } catch (_) {}
  }

  static Future<void> hide() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }
}
