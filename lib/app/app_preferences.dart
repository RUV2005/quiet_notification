import 'dart:convert';

import 'models.dart';
import 'notification_rules.dart';

/// 应用级偏好（规则、置顶、隐私、去重窗口等），可导出备份。
class AppPreferences {
  AppPreferences({
    this.rules = const [],
    this.pinnedApps = const {},
    this.privacyHideContent = false,
    this.sensitiveAppHints = const [],
    this.dedupeWindowSeconds = 120,
    this.closeAction = WindowAction.hide,
    this.sortModeName = 'receivedDesc',
  });

  final List<NotificationRule> rules;
  final Set<String> pinnedApps;
  final bool privacyHideContent;
  final List<String> sensitiveAppHints;
  final int dedupeWindowSeconds;
  final WindowAction closeAction;
  final String sortModeName;

  AppPreferences copyWith({
    List<NotificationRule>? rules,
    Set<String>? pinnedApps,
    bool? privacyHideContent,
    List<String>? sensitiveAppHints,
    int? dedupeWindowSeconds,
    WindowAction? closeAction,
    String? sortModeName,
  }) {
    return AppPreferences(
      rules: rules ?? this.rules,
      pinnedApps: pinnedApps ?? this.pinnedApps,
      privacyHideContent: privacyHideContent ?? this.privacyHideContent,
      sensitiveAppHints: sensitiveAppHints ?? this.sensitiveAppHints,
      dedupeWindowSeconds: dedupeWindowSeconds ?? this.dedupeWindowSeconds,
      closeAction: closeAction ?? this.closeAction,
      sortModeName: sortModeName ?? this.sortModeName,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'rules': rules.map((e) => e.toJson()).toList(),
        'pinnedApps': pinnedApps.toList(),
        'privacyHideContent': privacyHideContent,
        'sensitiveAppHints': sensitiveAppHints,
        'dedupeWindowSeconds': dedupeWindowSeconds,
        'closeAction': closeAction.name,
        'sortModeName': sortModeName,
      };

  factory AppPreferences.fromJson(Map<String, dynamic> raw) {
    final rulesRaw = raw['rules'];
    final rules = rulesRaw is List
        ? rulesRaw
            .map((e) => NotificationRule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <NotificationRule>[];
    final pinned = raw['pinnedApps'];
    final pinnedSet = pinned is List
        ? pinned.map((e) => e.toString()).toSet()
        : <String>{};
    final hintsRaw = raw['sensitiveAppHints'];
    final hints = hintsRaw is List
        ? hintsRaw.map((e) => e.toString()).toList()
        : <String>[];
    return AppPreferences(
      rules: rules,
      pinnedApps: pinnedSet,
      privacyHideContent: raw['privacyHideContent'] == true,
      sensitiveAppHints: hints,
      dedupeWindowSeconds: (raw['dedupeWindowSeconds'] is num)
          ? (raw['dedupeWindowSeconds'] as num).toInt()
          : 120,
      closeAction: WindowAction.values.firstWhere(
        (e) => e.name == raw['closeAction'],
        orElse: () => WindowAction.hide,
      ),
      sortModeName: (raw['sortModeName'] ?? 'receivedDesc').toString(),
    );
  }

  static AppPreferences fromExportString(String s) {
    final map = jsonDecode(s) as Map<String, dynamic>;
    return AppPreferences.fromJson(map);
  }

  String toExportString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
