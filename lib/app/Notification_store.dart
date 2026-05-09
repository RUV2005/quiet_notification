import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 通知本地持久化仓库。
///
/// 用 [SharedPreferences] 存储 JSON 列表，最多保留 [maxCount] 条。
/// 调用前必须先调用 [init]。
class NotificationStore {
  NotificationStore._();

  static final NotificationStore instance = NotificationStore._();

  static const String _key = 'notifications_v1';
  static const int maxCount = 200;

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 从本地加载所有通知（最新在前）。
  List<AppNotification> load() {
    final prefs = _prefs;
    if (prefs == null) return [];
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 将当前通知列表持久化到磁盘，超出 [maxCount] 的旧通知会被截断。
  Future<void> save(List<AppNotification> notifications) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final trimmed = notifications.length > maxCount
        ? notifications.sublist(0, maxCount)
        : notifications;
    final json = jsonEncode(trimmed.map((n) => n.toJson()).toList());
    await prefs.setString(_key, json);
  }

  /// 清空所有持久化通知。
  Future<void> clear() async {
    await _prefs?.remove(_key);
  }
}