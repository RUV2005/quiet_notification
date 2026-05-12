/// 应用名单条上限（避免异常数据撑爆内存）。
const int kNotificationAppMaxChars = 128;

/// 标题单条上限。
const int kNotificationTitleMaxChars = 512;

/// 正文单条上限（本地 JSON 与堆内列表共用，避免超长推送占满内存）。
const int kNotificationContentMaxChars = 8192;

/// 验证码等短字段上限。
const int kNotificationCodeMaxChars = 256;

String clampNotificationField(String value, int maxChars) {
  if (value.length <= maxChars) return value;
  return value.substring(0, maxChars);
}

/// 顶部筛选标签页。
enum NotificationTab { all, important, messages, codes, system, read, ignored }

/// 标题栏关闭按钮行为。
enum WindowAction { hide, close }

/// 统一的通知数据模型，承载列表与预览弹窗展示字段。
class AppNotification {
  AppNotification({
    required this.id,
    required this.app,
    required this.title,
    required this.content,
    required this.time,
    required this.unread,
    required this.categories,
    this.code,
    this.repeatCount = 1,
  });

  final String id;
  final String app;
  final String title;
  final String content;
  final String time;
  final bool unread;
  final List<String> categories;
  final String? code;
  /// 去重合并后的重复次数（同应用同标题短时间内的条数）。
  final int repeatCount;

  String get appShort => String.fromCharCodes(app.runes.take(2));

  /// 返回一个修改了指定字段的副本。
  AppNotification copyWith({
    String? id,
    String? app,
    String? title,
    String? content,
    String? time,
    bool? unread,
    List<String>? categories,
    String? code,
    int? repeatCount,
  }) {
    return AppNotification(
      id: id ?? this.id,
      app: app ?? this.app,
      title: title ?? this.title,
      content: content ?? this.content,
      time: time ?? this.time,
      unread: unread ?? this.unread,
      categories: categories ?? List<String>.from(this.categories),
      code: code ?? this.code,
      repeatCount: repeatCount ?? this.repeatCount,
    );
  }

  /// 将通知标记为已忽略（加入 ignored 分类，从其他分类移除）。
  AppNotification markIgnored() {
    final cats = List<String>.from(categories);
    if (!cats.contains('ignored')) cats.add('ignored');
    return copyWith(categories: cats, unread: false);
  }

  /// 取消忽略：移除 ignored，若没有其他分类则补 system。
  AppNotification unmarkIgnored() {
    final cats = List<String>.from(categories)..remove('ignored');
    if (cats.isEmpty) cats.add('system');
    return copyWith(categories: cats);
  }

  /// 标记已读。
  AppNotification markRead() => copyWith(unread: false);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'app': app,
      'title': title,
      'content': content,
      'time': time,
      'unread': unread,
      'categories': categories,
      'code': code,
      'repeatCount': repeatCount,
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> raw) {
    final categoriesRaw = raw['categories'];
    final categories = categoriesRaw is List
        ? categoriesRaw.map((e) => e.toString()).toList()
        : <String>[];
    final rc = raw['repeatCount'];
    final codeRaw = raw['code']?.toString();
    return AppNotification(
      id: (raw['id'] ?? '').toString(),
      app: clampNotificationField(
        (raw['app'] ?? '未知应用').toString(),
        kNotificationAppMaxChars,
      ),
      title: clampNotificationField(
        (raw['title'] ?? '新通知').toString(),
        kNotificationTitleMaxChars,
      ),
      content: clampNotificationField(
        (raw['content'] ?? '').toString(),
        kNotificationContentMaxChars,
      ),
      time: (raw['time'] ?? '').toString(),
      unread: raw['unread'] != false,
      categories: categories,
      code: codeRaw == null || codeRaw.isEmpty
          ? null
          : clampNotificationField(codeRaw, kNotificationCodeMaxChars),
      repeatCount: rc is num ? rc.toInt() : 1,
    );
  }
}