import 'package:flutter/material.dart';

/// 全局圆角：主界面、分组卡片、按钮尽量统一视觉风格。
const double kUnifiedRadius = 10;

/// 应用名关键字到图标资源的映射，用于通知卡片头像自动识别。
const Map<String, String> kAppIconMap = <String, String>{
  '微信': 'lib/assets/wechat.png',
  'qq': 'lib/assets/qq.png',
  '钉钉': 'lib/assets/dingding.png',
  '淘宝': 'lib/assets/taobao.png',
  '京东': 'lib/assets/jd.png',
  '菜鸟': 'lib/assets/taobao.png',
  '日历': 'lib/assets/calendar.png',
  '短信': 'lib/assets/text_message.png',
  '支付宝': 'lib/assets/alipay.png',
  '银行通知': 'lib/assets/bank.png',
  '系统': 'lib/assets/notice.png',
};

/// 根据应用名匹配对应图标资源，未匹配到时返回 null 使用文字头像。
String? resolveAppIconAsset(String appName) {
  final lower = appName.toLowerCase();
  for (final entry in kAppIconMap.entries) {
    if (lower.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

const List<Color> _kAvatarPalette = <Color>[
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFF06B6D4),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF6366F1),
];

Color avatarColorForApp(String appName) {
  final key = appName.trim().toLowerCase();
  final hash = key.runes.fold<int>(0, (acc, r) => (acc * 131 + r) & 0x7fffffff);
  return _kAvatarPalette[hash % _kAvatarPalette.length];
}

DateTime? parseNotificationTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  var dt = DateTime.tryParse(text);
  if (dt != null) return dt;
  dt = DateTime.tryParse(text.replaceFirst(' ', 'T'));
  if (dt != null) return dt;

  final hm = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
  if (hm != null) {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(hm.group(1)!),
      int.parse(hm.group(2)!),
      int.tryParse(hm.group(3) ?? '0') ?? 0,
    );
  }
  return null;
}

String _two(int v) => v.toString().padLeft(2, '0');

String formatFriendlyTime(String raw) {
  final dt = parseNotificationTime(raw);
  if (dt == null) return raw;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final days = today.difference(day).inDays;
  final hm = '${_two(dt.hour)}:${_two(dt.minute)}';
  if (days == 0) return hm;
  if (days == 1) return '昨天 $hm';
  return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} $hm';
}

/// 隐私模式 / 敏感应用：列表与预览中展示的正文（不含标题行）。
String notificationBodyForDisplay(
  String app,
  String content, {
  required bool privacyHideContent,
  List<String> sensitiveAppHints = const [],
}) {
  if (privacyHideContent) return '（内容已隐藏）';
  final appL = app.toLowerCase();
  for (final h in sensitiveAppHints) {
    final t = h.trim();
    if (t.isEmpty) continue;
    if (appL.contains(t.toLowerCase())) {
      return '（敏感应用：内容已隐藏）';
    }
  }
  return content;
}

/// 构建通知中的应用头像：优先图标，失败时回退到应用简称文字。
Widget buildAppAvatar({
  required String appName,
  required String fallbackText,
  required double size,
  required double fallbackFontSize,
}) {
  final iconAsset = resolveAppIconAsset(appName);
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: avatarColorForApp(appName),
      borderRadius: BorderRadius.circular(kUnifiedRadius),
    ),
    child: iconAsset == null
        ? Text(
            fallbackText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: fallbackFontSize,
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset(
              iconAsset,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Text(
                fallbackText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: fallbackFontSize,
                ),
              ),
            ),
          ),
  );
}
