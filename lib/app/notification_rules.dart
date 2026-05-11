import 'dart:convert';

/// 规则命中后的动作。
enum RuleAction {
  ignore,
  markRead,
  silence,
  remindOnly,
  autoCopyCode,
}

/// 单条通知匹配规则（按列表顺序，先命中先生效）。
class NotificationRule {
  NotificationRule({
    required this.id,
    this.appContains,
    this.keywordContains,
    this.regexPattern,
    required this.action,
  });

  final String id;
  final String? appContains;
  final String? keywordContains;
  final String? regexPattern;
  final RuleAction action;

  bool matches(String app, String title, String content) {
    final hasApp = appContains != null && appContains!.trim().isNotEmpty;
    final hasKw = keywordContains != null && keywordContains!.trim().isNotEmpty;
    final hasRe = regexPattern != null && regexPattern!.trim().isNotEmpty;
    if (!hasApp && !hasKw && !hasRe) return false;

    final hay = '$title $content'.toLowerCase();
    final appL = app.toLowerCase();
    if (hasApp) {
      if (!appL.contains(appContains!.trim().toLowerCase())) return false;
    }
    if (hasKw) {
      if (!hay.contains(keywordContains!.trim().toLowerCase())) return false;
    }
    if (hasRe) {
      try {
        if (!RegExp(regexPattern!.trim()).hasMatch('$app $title $content')) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'appContains': appContains,
        'keywordContains': keywordContains,
        'regexPattern': regexPattern,
        'action': action.name,
      };

  factory NotificationRule.fromJson(Map<String, dynamic> raw) {
    return NotificationRule(
      id: (raw['id'] ?? '').toString(),
      appContains: raw['appContains']?.toString(),
      keywordContains: raw['keywordContains']?.toString(),
      regexPattern: raw['regexPattern']?.toString(),
      action: RuleAction.values.firstWhere(
        (e) => e.name == raw['action'],
        orElse: () => RuleAction.ignore,
      ),
    );
  }

  static List<NotificationRule> listFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => NotificationRule.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<NotificationRule> rules) =>
      jsonEncode(rules.map((e) => e.toJson()).toList());
}
