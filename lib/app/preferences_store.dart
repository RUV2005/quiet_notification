import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_preferences.dart';

/// 持久化 [AppPreferences]（与 [NotificationStore] 共用 SharedPreferences）。
class PreferencesStore {
  PreferencesStore._();

  static final PreferencesStore instance = PreferencesStore._();

  static const String _key = 'app_preferences_v1';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  AppPreferences load() {
    final prefs = _prefs;
    if (prefs == null) return AppPreferences();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AppPreferences();
    try {
      return AppPreferences.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return AppPreferences();
    }
  }

  Future<void> save(AppPreferences p) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(_key, jsonEncode(p.toJson()));
  }
}
