/// 顶部筛选标签页。
enum NotificationTab { all, important, messages, codes, system, ignored }

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
  });

  final String id;
  final String app;
  final String title;
  final String content;
  final String time;
  final bool unread;
  final List<String> categories;
  final String? code;

  String get appShort => String.fromCharCodes(app.runes.take(2));

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
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> raw) {
    final categoriesRaw = raw['categories'];
    final categories = categoriesRaw is List
        ? categoriesRaw.map((e) => e.toString()).toList()
        : <String>[];
    return AppNotification(
      id: (raw['id'] ?? '').toString(),
      app: (raw['app'] ?? '未知应用').toString(),
      title: (raw['title'] ?? '新通知').toString(),
      content: (raw['content'] ?? '').toString(),
      time: (raw['time'] ?? '').toString(),
      unread: raw['unread'] != false,
      categories: categories,
      code: raw['code']?.toString(),
    );
  }
}
