import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'constants.dart';
import 'models.dart';
import 'notification_store.dart';
import 'preview_window_controller.dart';
import 'websocket_manager.dart';
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
  static const double _snapThreshold = 18;

  final List<AppNotification> _notifications = [];
  final TextEditingController _urlController =
      TextEditingController(text: 'ws://127.0.0.1:8765/notifications');

  late final WebSocketManager _wsManager;
  WsStatus _wsStatus = WsStatus.disconnected;

  NotificationTab _activeTab = NotificationTab.all;
  WindowAction _closeAction = WindowAction.hide;
  bool _pinned = false;
  String? _copiedId;
  final Map<String, bool> _appExpanded = <String, bool>{};

  Timer? _snapDebounce;
  PreviewWindowController? _previewWindowController;
  bool _isSnappingWindow = false;

  final NotificationStore _store = NotificationStore.instance;
  bool _storeReady = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _wsManager = WebSocketManager(
      onMessage: _handleMessage,
      onStatusChanged: (s) {
        if (mounted) setState(() => _wsStatus = s);
      },
    );
    _initStore();
    _wsManager.connect(_urlController.text);
    _previewWindowController = PreviewWindowController(
      onOpenMainRequested: _openMainFromPreviewRequest,
    );
    unawaited(_previewWindowController!.initialize());
  }

  Future<void> _initStore() async {
    await _store.init();
    final saved = _store.load();
    if (mounted) {
      setState(() {
        if (saved.isNotEmpty) _notifications.addAll(saved);
        _storeReady = true;
      });
    }
  }

  void _updateNotifications(void Function() mutate) {
    setState(mutate);
    if (_storeReady) unawaited(_store.save(_notifications));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _snapDebounce?.cancel();
    unawaited(_previewWindowController?.dispose());
    _wsManager.dispose();
    _urlController.dispose();
    super.dispose();
  }

  // ── 窗口吸附 ──────────────────────────────────────────
  @override
  void onWindowMoved() {
    if (_isSnappingWindow) return;
    _snapDebounce?.cancel();
    _snapDebounce = Timer(
      const Duration(milliseconds: 100),
      _snapWindowToNearestEdge,
    );
  }

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

  Rect _displayWorkArea(Display display) {
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }

  // ── 消息处理 ──────────────────────────────────────────
  void _handleMessage(String raw) {
    dynamic data;
    try {
      data = jsonDecode(raw);
    } catch (_) {
      return;
    }
    final list = data is List ? data : [data];
    _updateNotifications(() {
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
      if (_notifications.length > NotificationStore.maxCount) {
        _notifications.removeRange(
            NotificationStore.maxCount, _notifications.length);
      }
    });
    if (_notifications.isNotEmpty) {
      unawaited(_showPreviewWindowIfNeeded(_notifications.first));
    }
  }

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

  // ── 通知操作 ──────────────────────────────────────────
  void _ignoreNotification(AppNotification n) {
    _updateNotifications(() {
      final idx = _notifications.indexWhere((x) => x.id == n.id);
      if (idx >= 0) _notifications[idx] = n.markIgnored();
    });
  }

  void _unignoreNotification(AppNotification n) {
    _updateNotifications(() {
      final idx = _notifications.indexWhere((x) => x.id == n.id);
      if (idx >= 0) _notifications[idx] = n.unmarkIgnored();
    });
  }

  void _markGroupRead(String app) {
    _updateNotifications(() {
      for (var i = 0; i < _notifications.length; i++) {
        if (_notifications[i].app == app && _notifications[i].unread) {
          _notifications[i] = _notifications[i].markRead();
        }
      }
    });
  }

  // ── Tab ───────────────────────────────────────────────
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

  /// Tab 角标：已忽略 tab 显示总条数，其余 tab 只统计未读数。
  int _count(NotificationTab tab) {
    if (tab == NotificationTab.ignored) {
      return _notifications.where((n) => _matchTab(n, tab)).length;
    }
    return _notifications.where((n) => _matchTab(n, tab) && n.unread).length;
  }

  Future<void> _onClose() async {
    if (_closeAction == WindowAction.hide) {
      await windowManager.hide();
    } else {
      await windowManager.close();
    }
  }

  // ── UI ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isIgnoredTab = _activeTab == NotificationTab.ignored;
    final filtered =
        _notifications.where((n) => _matchTab(n, _activeTab)).toList();
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
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              HeaderBar(
                pinned: _pinned,
                wsStatus: _wsStatus,
                onPin: () async {
                  _pinned = !_pinned;
                  await windowManager.setAlwaysOnTop(_pinned);
                  setState(() {});
                },
                onSettings: () => _showSettings(context),
                onMinimize: () => windowManager.minimize(),
                onClose: _onClose,
                onReconnect: () => _wsManager.connect(_urlController.text),
              ),
              const SizedBox(height: 8),
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
                          ? _buildEmptyState(isIgnoredTab)
                          : ListView.separated(
                              itemCount: groupedEntries.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final app = groupedEntries[i].key;
                                final appNotifs = groupedEntries[i].value;
                                return AppGroupCard(
                                  app: app,
                                  notifications: appNotifs,
                                  expanded: _appExpanded[app] ?? false,
                                  onToggle: () {
                                    final willExpand =
                                        !(_appExpanded[app] ?? false);
                                    setState(
                                        () => _appExpanded[app] = willExpand);
                                    if (willExpand) _markGroupRead(app);
                                  },
                                  cardBuilder: (n) => NotificationCardView(
                                    n: n,
                                    copied: _copiedId == n.id,
                                    isIgnoredTab: isIgnoredTab,
                                    onCopy: n.code == null
                                        ? null
                                        : () async {
                                            await Clipboard.setData(
                                                ClipboardData(text: n.code!));
                                            setState(() => _copiedId = n.id);
                                            Future<void>.delayed(
                                              const Duration(seconds: 2),
                                              () {
                                                if (mounted &&
                                                    _copiedId == n.id) {
                                                  setState(
                                                      () => _copiedId = null);
                                                }
                                              },
                                            );
                                          },
                                    onIgnore: () => _ignoreNotification(n),
                                    onUnignore: () => _unignoreNotification(n),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    if (!isIgnoredTab)
                      InkWell(
                        borderRadius: BorderRadius.circular(kUnifiedRadius),
                        onTap: () => setState(
                            () => _activeTab = NotificationTab.ignored),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.chevron_right,
                                  size: 18, color: Colors.white38),
                              const SizedBox(width: 8),
                              Text(
                                '查看已忽略通知（$ignoredCount 条）',
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.white38),
                              ),
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

  Widget _buildEmptyState(bool isIgnoredTab) {
    if (!_storeReady) {
      return const Center(
          child: Text('加载中...', style: TextStyle(color: Colors.white54)));
    }
    if (isIgnoredTab) {
      return const Center(
          child: Text('没有已忽略的通知',
              style: TextStyle(color: Colors.white54)));
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _wsStatus == WsStatus.connected
                ? Icons.notifications_none
                : Icons.wifi_off,
            size: 40,
            color: Colors.white24,
          ),
          const SizedBox(height: 12),
          Text(
            switch (_wsStatus) {
              WsStatus.connected => '已连接，等待通知数据...',
              WsStatus.connecting => '正在连接...',
              WsStatus.reconnecting => '连接断开，正在重连...',
              WsStatus.disconnected => '未连接',
            },
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

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
                    value: WindowAction.hide, child: Text('隐藏窗口（推荐）')),
                DropdownMenuItem(
                    value: WindowAction.close, child: Text('退出应用')),
              ],
              onChanged: (v) => localAction = v ?? WindowAction.hide,
              decoration: const InputDecoration(labelText: '关闭按钮行为'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await _store.clear();
                _updateNotifications(() => _notifications.clear());
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('清空所有通知'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _wsManager.connect(local.text.trim()),
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
              _wsManager.connect(_urlController.text);
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}