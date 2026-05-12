import 'package:shared_preferences/shared_preferences.dart';

/// 首次启动新手引导是否已完成（与通知偏好分键存储）。
class OnboardingStore {
  OnboardingStore._();

  static final OnboardingStore instance = OnboardingStore._();

  static const String _key = 'first_launch_onboarding_done_v1';

  Future<bool> isCompleted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? false;
  }

  Future<void> markCompleted() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, true);
  }

  /// 设置里「再次显示引导」用：清除后下次冷启动会再弹（也可直接调 [present]）。
  Future<void> clearCompleted() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
