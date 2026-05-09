import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:window_manager/window_manager.dart';

import 'constants.dart';
import 'models.dart';
import 'preview_window_controller.dart';
import 'widgets.dart';

class NotificationApp extends StatelessWidget {
  const NotificationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF10131A),
      ),
      home: const NotificationHomePage(),
    );
  }
}

class NotificationHomePage extends StatefulWidget {
  const NotificationHomePage({super.key});

  @override
  State<NotificationHomePage> createState() => _NotificationHomePageState();
}

class _NotificationHomePageState extends State<NotificationHomePage>
    with WindowListener {
  /// 主窗口拖动吸附边缘阈值（像素）。
  static const double _snapThreshold = 18;

  /// 通知总缓存（最新在前，限制最大条数）。
  final List<AppNotification> _notifications = [];
  final TextEditingController _urlController =
      TextEditingController(text: 'ws://127.0.0.1:8765/notifications');

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  NotificationTab _activeTab = NotificationTab.all;
  WindowAction _closeAction = WindowAction.hide;
  bool _pinned = false;
  String? _copiedId;
  final Map<String, bool> _appExpanded = <String, bool>{};
  Timer? _snapDebounce;
  PreviewWindowController? _previewWindowController;
  bool _isSnappingWindow = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _connect(_urlController.text);
    _previewWindowController = PreviewWindowController(
      onOpenMainRequested: _openMainFromPreviewRequest,
    );
    unawaited(_previewWindowController!.initialize());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _snapDebounce?.cancel();
    unawaited(_previewWindowController?.dispose());
    _subscription?.cancel();
    _channel?.sink.close();
    _urlController.dispose();
    super.dispose();
  }

  @override
  void onWindowMoved() {
    if (_isSnappingWindow) return;
    _snapDebounce?.cancel();
    _snapDebounce = Timer(
      const Duration(milliseconds: 100),
      _snapWindowToNearestEdge,
    );
  }

  /// 将主窗口自动吸附到最近屏幕边缘，提升桌面停靠体验。
  Future<void> _snapWindowToNearestEdge() async {
    if (!mounted || _isSnappingWindow) return;

    final bounds = await windowManager.getBounds();
    final workArea = await _resolveCurrentWorkArea(bounds);
    if (workArea == null) return;

    double nextLeft = bounds.left;
    double nextTop = bounds.top;
    final nextRight = bounds.left + bounds.width;
    final nextBottom = bounds.top + bounds.height;

    if ((bounds.left - workArea.left).abs() <= _snapThreshold) {
      nextLeft = workArea.left;
    } else if ((workArea.right - nextRight).abs() <= _snapThreshold) {
      nextLeft = workArea.right - bounds.width;
    }

    if ((bounds.top - workArea.top).abs() <= _snapThreshold) {
      nextTop = workArea.top;
    } else if ((workArea.bottom - nextBottom).abs() <= _snapThreshold) {
      nextTop = workArea.bottom - bounds.height;
    }

    final moved = (nextLeft - bounds.left).abs() > 0.5 ||
        (nextTop - bounds.top).abs() > 0.5;
    if (!moved) return;

    _isSnappingWindow = true;
    try {
      await windowManager.setPosition(Offset(nextLeft, nextTop));
    } finally {
      _isSnappingWindow = false;
    }
  }

  /// 根据当前窗口所在屏幕，获取对应可用工作区（考虑任务栏占位）。
  Future<Rect?> _resolveCurrentWorkArea(Rect windowBounds) async {
    final displays = await screenRetriever.getAllDisplays();
    if (displays.isEmpty) return null;

    final center = windowBounds.center;
    Rect? selectedArea;
    double nearestDistance = double.infinity;

    for (final display in displays) {
      final area = _displayWorkArea(display);
      if (area.contains(center)) return area;

      final dx = center.dx.clamp(area.left, area.right) - center.dx;
      final dy = center.dy.clamp(area.top, area.bottom) - center.dy;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        selectedArea = area;
      }
    }
    return selectedArea;
  }

  /// 从 display 信息提取可见工作区矩形。
  Rect _displayWorkArea(Display display) {
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }

  /// 建立/重建 WebSocket 连接。
  void _connect(String url) {
    _subscription?.cancel();
    _channel?.sink.close();

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      _subscription = channel.stream.listen(
        (raw) => _handleMessage(raw.toString()),
        onError: (_) {},
        onDone: () {},
      );
      channel.ready.catchError((_) {});
    } catch (_) {}
  }

  /// 处理服务端通知消息：解析、去重更新、截断缓存、触发预览。
  void _handleMessage(String raw) {
    dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return;
    }

    final list = data is List ? data : [data];
    for (final item in list) {
      if (item is! Map) continue;
      final n = _fromJson(Map<String, dynamic>.from(item));
      final idx = _notifications.indexWhere((x) => x.id == n.id);
      if (idx >= 0) {
        _notifications[idx] = n;
      } else {
        _notifications.insert(0, n);
      }
    }
    if (_notifications.length > 200) {
      _notifications.removeRange(200, _notifications.length);
    }
    setState(() {});
    unawaited(_showPreviewWindowIfNeeded(_notifications.first));
  }

  /// 主窗口最小化时，将通知交给独立预览子窗口展示。
  Future<void> _showPreviewWindowIfNeeded(AppNotification n) async {
    if (!mounted) return;
    final minimized = await windowManager.isMinimized();
    if (!minimized) return;
    await _previewWindowController?.showNotification(n);
  }

  Future<void> _openMainFromPreviewRequest() async {
    await _previewWindowController?.hidePreview();
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  /// 将外部 JSON 转成内部通知模型，并做基础分类推断。
  AppNotification _fromJson(Map<String, dynamic> raw) {
    final now = DateTime.now();
    final app = (raw['app'] ?? '未知应用').toString();
    final title = (raw['title'] ?? '新通知').toString();
    final content = (raw['content'] ?? '').toString();
    final id = (raw['id'] ?? now.millisecondsSinceEpoch).toString();
    final time =
        (raw['time'] ?? '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}')
            .toString();
    final code = (raw['code'] ?? '').toString();

    final categories = <String>{};
    final rawCats = raw['categories'];
    if (rawCats is List) {
      for (final c in rawCats) {
        categories.add(c.toString().toLowerCase());
      }
    } else {
      final joined = '$app $title $content'.toLowerCase();
      if (joined.contains('验证码') || joined.contains('otp') || code.isNotEmpty) {
        categories.add('codes');
      }
      if (joined.contains('微信') || joined.contains('message') || joined.contains('钉钉')) {
        categories.add('messages');
      }
      if (joined.contains('系统') || joined.contains('提醒') || joined.contains('calendar')) {
        categories.add('system');
      }
      if (raw['important'] == true) categories.add('important');
      if (raw['ignored'] == true) categories.add('ignored');
      if (categories.isEmpty) categories.add('system');
    }

    return AppNotification(
      id: id,
      app: app,
      title: title,
      content: content,
      time: time,
      unread: raw['unread'] != false,
      categories: categories.toList(),
      code: code.isEmpty ? null : code,
    );
  }

  /// 判断一条通知是否应该在当前标签页显示。
  bool _matchTab(AppNotification n, NotificationTab tab) {
    switch (tab) {
      case NotificationTab.all:
        return !n.categories.contains('ignored');
      case NotificationTab.important:
        return n.categories.contains('important');
      case NotificationTab.messages:
        return n.categories.contains('messages');
      case NotificationTab.codes:
        return n.categories.contains('codes');
      case NotificationTab.system:
        return n.categories.contains('system');
      case NotificationTab.ignored:
        return n.categories.contains('ignored');
    }
  }

  /// 统计标签页数量。
  int _count(NotificationTab tab) => _notifications.where((n) => _matchTab(n, tab)).length;

  /// 响应标题栏关闭按钮：隐藏或退出。
  Future<void> _onClose() async {
    if (_closeAction == WindowAction.hide) {
      await windowManager.hide();
    } else {
      await windowManager.close();
    }
  }

  /// 主界面构建。
  @override
  Widget build(BuildContext context) {
    final filtered = _notifications.where((n) => _matchTab(n, _activeTab)).toList();
    final ignoredCount = _count(NotificationTab.ignored);
    final groupedByApp = <String, List<AppNotification>>{};
    for (final n in filtered) {
      groupedByApp.putIfAbsent(n.app, () => <AppNotification>[]).add(n);
    }
    _appExpanded.removeWhere((app, _) => !groupedByApp.containsKey(app));
    for (final app in groupedByApp.keys) {
      _appExpanded.putIfAbsent(app, () => false);
    }
    final groupedEntries = groupedByApp.entries.toList();

    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF10131A),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              HeaderBar(
                pinned: _pinned,
                onPin: () async {
                  _pinned = !_pinned;
                  await windowManager.setAlwaysOnTop(_pinned);
                  setState(() {});
                },
                onSettings: () => _showSettings(context),
                onMinimize: () => windowManager.minimize(),
                onClose: _onClose,
              ),
              const SizedBox(height: 4),
              const SizedBox(height: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NotificationTabsBar(
                      activeTab: _activeTab,
                      countOf: _count,
                      onChanged: (t) => setState(() => _activeTab = t),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('等待 WebSocket 通知数据...'))
                          : ListView.separated(
                              itemCount: groupedEntries.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final app = groupedEntries[i].key;
                                final appNotifications = groupedEntries[i].value;
                                return AppGroupCard(
                                  app: app,
                                  notifications: appNotifications,
                                  expanded: _appExpanded[app] ?? true,
                                  onToggle: () {
                                    setState(() {
                                      _appExpanded[app] = !(_appExpanded[app] ?? true);
                                    });
                                  },
                                  cardBuilder: (n) => NotificationCardView(
                                    n: n,
                                    copied: _copiedId == n.id,
                                    onCopy: n.code == null
                                        ? null
                                        : () async {
                                            await Clipboard.setData(ClipboardData(text: n.code!));
                                            setState(() => _copiedId = n.id);
                                            Future<void>.delayed(const Duration(seconds: 2), () {
                                              if (mounted && _copiedId == n.id) {
                                                setState(() => _copiedId = null);
                                              }
                                            });
                                          },
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      borderRadius: BorderRadius.circular(kUnifiedRadius),
                      onTap: () => setState(() => _activeTab = NotificationTab.ignored),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: _activeTab == NotificationTab.ignored
                                  ? Colors.lightBlueAccent
                                  : Colors.white60,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '查看已忽略通知（$ignoredCount 条）',
                              style: TextStyle(
                                fontSize: 14,
                                color: _activeTab == NotificationTab.ignored
                                    ? Colors.lightBlueAccent
                                    : Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 设置弹窗：配置 WebSocket 地址与关闭行为。
  Future<void> _showSettings(BuildContext context) async {
    final local = TextEditingController(text: _urlController.text);
    var localAction = _closeAction;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF151A23),
        title: const Text('设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: local,
              decoration: const InputDecoration(labelText: 'WebSocket 地址'),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<WindowAction>(
              initialValue: localAction,
              items: const [
                DropdownMenuItem(
                  value: WindowAction.hide,
                  child: Text('隐藏窗口（推荐）'),
                ),
                DropdownMenuItem(
                  value: WindowAction.close,
                  child: Text('退出应用'),
                ),
              ],
              onChanged: (v) => localAction = v ?? WindowAction.hide,
              decoration: const InputDecoration(labelText: '关闭按钮行为'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _connect(local.text.trim()),
            child: const Text('测试连接'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              _urlController.text = local.text.trim();
              _closeAction = localAction;
              _connect(_urlController.text);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
