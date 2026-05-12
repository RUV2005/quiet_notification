import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'android_notification_bridge.dart';
import 'app_preferences.dart';
import 'constants.dart';
import 'models.dart';
import 'native_float_preview_windows.dart';
import 'onboarding_flow.dart';
import 'onboarding_store.dart';
import 'notification_rules.dart';
import 'notification_store.dart';
import 'preferences_store.dart';
import 'preview_window_controller.dart';
import 'stats_sheet.dart';
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

enum NotificationSortMode { receivedDesc, appThenNewest, appThenOldest }

enum _TimeFilterMode { any, last24h, last7d }

class _NotificationHomePageState extends State<NotificationHomePage>
    with WindowListener, WidgetsBindingObserver, TrayListener {
  static const double _snapThreshold = 18;

  final List<AppNotification> _notifications = [];
  /// 接收端：连接推送来源。安卓作发送端时请填 `ws://手机局域网IP:8765/notifications`；
  /// 本机 Python 演示脚本仍可用 `ws://127.0.0.1:8765/notifications`。
  final TextEditingController _urlController =
      TextEditingController(text: 'ws://10.0.2.132:8765/notifications');

  late final WebSocketManager _wsManager;
  WsStatus _wsStatus = WsStatus.disconnected;

  NotificationTab _activeTab = NotificationTab.all;
  WindowAction _closeAction = WindowAction.hide;
  NotificationSortMode _sortMode = NotificationSortMode.receivedDesc;
  bool _pinned = false;
  String? _copiedId;
  final Map<String, bool> _appExpanded = <String, bool>{};

  Timer? _snapDebounce;
  PreviewWindowController? _previewWindowController;
  bool _isSnappingWindow = false;
  StreamSubscription<Map<String, dynamic>>? _androidNotificationSub;
  bool _androidListenerEnabled = false;

  final NotificationStore _store = NotificationStore.instance;
  bool _storeReady = false;

  /// 主窗口最小化或生命周期非 resumed 时，Flutter 会几乎不泵帧，WebSocket/子窗口通道会卡住。
  /// 在需要后台工作时周期性强制一帧，避免「最小化后有通知就像停住」。
  Timer? _desktopBackgroundFrameTimer;
  bool _desktopWindowMinimized = false;
  bool _desktopLifecycleBackground = false;

  /// 避免多条通知连续到达时，未 await 的预览调用乱序完成导致弹窗与列表不一致。
  int _desktopPreviewShowSeq = 0;

  final PreferencesStore _prefsStore = PreferencesStore.instance;
  AppPreferences _prefs = AppPreferences();
  late final TextEditingController _searchCtrl;
  bool _filterCodesOnly = false;
  String? _filterApp;
  _TimeFilterMode _timeFilter = _TimeFilterMode.any;

  static const Map<NotificationSortMode, String> _sortLabels = {
    NotificationSortMode.receivedDesc: '按接收顺序（最新优先）',
    NotificationSortMode.appThenNewest: '先按应用分组（应用名），组内最新优先',
    NotificationSortMode.appThenOldest: '先按应用分组（应用名），组内最早优先',
  };

  int _compareByParsedTime(AppNotification a, AppNotification b) {
    final ta = parseNotificationTime(a.time);
    final tb = parseNotificationTime(b.time);
    if (ta != null && tb != null) return tb.compareTo(ta);
    if (ta != null) return -1;
    if (tb != null) return 1;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    if (_isDesktopWindow) {
      windowManager.addListener(this);
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_syncDesktopMinimizedFromOs());
      });
    }
    _wsManager = WebSocketManager(
      onMessage: _handleMessage,
      onStatusChanged: (s) {
        if (mounted) setState(() => _wsStatus = s);
      },
    );
    _initStore();
    unawaited(_initAndroidBridge());
    unawaited(_initTray());
    if (_isDesktopWindow) {
      if (_useDesktopPreviewSubwindow) {
        _previewWindowController = PreviewWindowController(
          onOpenMainRequested: _openMainFromPreviewRequest,
        );
        unawaited(_bootstrapDesktopNetworking());
      } else {
        _wsManager.connect(_urlController.text);
      }
    } else {
      _wsManager.connect(_urlController.text);
    }
  }

  Future<void> _initTray() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      await trayManager.setIcon('windows/runner/resources/app_icon.ico');
      trayManager.addListener(this);
      await _refreshTray();
    } catch (_) {}
  }

  Future<void> _showMainWindowFromTray() async {
    if (!_isDesktopWindow) return;
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showMainWindowFromTray());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == 'show') {
      unawaited(_showMainWindowFromTray());
      return;
    }
    if (key == 'mark_all') {
      _updateNotifications(() {
        for (var i = 0; i < _notifications.length; i++) {
          if (!_notifications[i].categories.contains('ignored')) {
            _notifications[i] = _notifications[i].markRead();
          }
        }
      });
      return;
    }
    if (key == 'clear_read') {
      _updateNotifications(() {
        _notifications.removeWhere(
          (n) => !n.unread && !n.categories.contains('ignored'),
        );
      });
      return;
    }
    if (key == 'exit') {
      unawaited(windowManager.close());
      return;
    }
    if (key != null && key.startsWith('recent_')) {
      unawaited(_showMainWindowFromTray());
    }
  }

  Future<void> _refreshTray() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    if (!mounted) return;
    try {
      final unread = _notifications
          .where((n) => n.unread && !n.categories.contains('ignored'))
          .length;
      await trayManager.setToolTip('通知助手 · 未读 $unread');
      final recent = _notifications
          .where((n) => !n.categories.contains('ignored'))
          .take(8)
          .toList();
      final items = <MenuItem>[
        MenuItem(key: 'show', label: '显示主窗口'),
        MenuItem(key: 'mark_all', label: '全部标为已读'),
        MenuItem(key: 'clear_read', label: '清空已读记录'),
        if (recent.isNotEmpty) MenuItem.separator(),
        ...recent.map((n) {
          final label = '${n.app}: ${n.title}';
          final short =
              label.length > 42 ? '${label.substring(0, 41)}…' : label;
          return MenuItem(key: 'recent_${n.id}', label: short);
        }),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出'),
      ];
      await trayManager.setContextMenu(Menu(items: items));
    } catch (_) {}
  }

  /// 非 Windows：先等预览子窗口跨窗通道就绪再连 WebSocket。
  Future<void> _bootstrapDesktopNetworking() async {
    try {
      await _previewWindowController?.initialize();
    } catch (_) {}
    if (!mounted) return;
    _wsManager.connect(_urlController.text);
  }

  Future<void> _initStore() async {
    await _store.init();
    await _prefsStore.init();
    final saved = _store.load();
    final loadedPrefs = _prefsStore.load();
    if (mounted) {
      setState(() {
        if (saved.isNotEmpty) _notifications.addAll(saved);
        _storeReady = true;
        _prefs = loadedPrefs;
        _closeAction = loadedPrefs.closeAction;
        _sortMode = NotificationSortMode.values.firstWhere(
          (e) => e.name == loadedPrefs.sortModeName,
          orElse: () => NotificationSortMode.receivedDesc,
        );
      });
    }
    unawaited(_refreshTray());
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeShowFirstLaunchOnboarding());
      });
    }
  }

  Future<void> _maybeShowFirstLaunchOnboarding() async {
    if (!mounted) return;
    final done = await OnboardingStore.instance.isCompleted();
    if (!mounted || done) return;
    await presentOnboardingFlow(context, markCompletedWhenDone: true);
  }

  Future<void> _savePrefs() async {
    final p = _prefs.copyWith(
      closeAction: _closeAction,
      sortModeName: _sortMode.name,
    );
    if (mounted) setState(() => _prefs = p);
    await _prefsStore.save(p);
  }

  void _updateNotifications(void Function() mutate) {
    setState(mutate);
    if (_storeReady) unawaited(_store.save(_notifications));
    unawaited(_refreshTray());
  }

  @override
  void dispose() {
    if (_isDesktopWindow) {
      windowManager.removeListener(this);
      WidgetsBinding.instance.removeObserver(this);
    }
    _desktopBackgroundFrameTimer?.cancel();
    _desktopBackgroundFrameTimer = null;
    _snapDebounce?.cancel();
    _androidNotificationSub?.cancel();
    trayManager.removeListener(this);
    unawaited(_previewWindowController?.dispose());
    if (_isDesktopWindow && !_useDesktopPreviewSubwindow) {
      unawaited(NativeFloatPreviewWindows.hide());
    }
    _wsManager.dispose();
    _urlController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isDesktopWindow =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Windows 上 `desktop_multi_window` 跨引擎 `invokeMethod` 易触发 CHANNEL_UNREGISTERED（与插件/嵌入器组合有关）；
  /// 最小化通知改为仅恢复主窗口提示。Linux/macOS 仍使用独立预览子窗口。
  bool get _useDesktopPreviewSubwindow =>
      _isDesktopWindow && defaultTargetPlatform != TargetPlatform.windows;

  void _updateDesktopBackgroundFramePump() {
    if (!_isDesktopWindow) return;
    final needPump = _desktopWindowMinimized || _desktopLifecycleBackground;
    if (needPump && _desktopBackgroundFrameTimer == null) {
      _desktopBackgroundFrameTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          if (!mounted) return;
          SchedulerBinding.instance.scheduleForcedFrame();
        },
      );
    } else if (!needPump && _desktopBackgroundFrameTimer != null) {
      _desktopBackgroundFrameTimer!.cancel();
      _desktopBackgroundFrameTimer = null;
    }
  }

  Future<void> _syncDesktopMinimizedFromOs() async {
    if (!_isDesktopWindow || !mounted) return;
    try {
      final minimized = await windowManager.isMinimized();
      if (!mounted) return;
      if (_desktopWindowMinimized != minimized) {
        _desktopWindowMinimized = minimized;
        _updateDesktopBackgroundFramePump();
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isDesktopWindow) return;
    _desktopLifecycleBackground = state != AppLifecycleState.resumed;
    _updateDesktopBackgroundFramePump();
  }

  @override
  void onWindowMinimize() {
    if (!_isDesktopWindow) return;
    _desktopWindowMinimized = true;
    _updateDesktopBackgroundFramePump();
  }

  @override
  void onWindowRestore() {
    if (!_isDesktopWindow) return;
    _desktopWindowMinimized = false;
    _updateDesktopBackgroundFramePump();
  }

  Future<void> _initAndroidBridge() async {
    if (!_isAndroid) return;
    final enabled = await AndroidNotificationBridge.isListenerEnabled();
    if (!mounted) return;
    setState(() => _androidListenerEnabled = enabled);
    if (!enabled) return;
    _androidNotificationSub = AndroidNotificationBridge.notifications().listen(
      _handleAndroidNotification,
      onError: (_) {},
    );
  }

  void _handleAndroidNotification(Map<String, dynamic> raw) {
    ({AppNotification? notification, bool silentPreview})? lastIncoming;
    _updateNotifications(() {
      lastIncoming = _upsertIncomingNotification(raw);
      if (_notifications.length > NotificationStore.maxCount) {
        _notifications.removeRange(
            NotificationStore.maxCount, _notifications.length);
      }
    });
    final li = lastIncoming;
    if (li != null && li.notification != null && !li.silentPreview) {
      unawaited(_showPreviewWindowIfNeeded(li.notification!));
    }
  }

  bool _isPersistentNotification(Map<String, dynamic> raw) {
    bool asBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v?.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }

    if (asBool(raw['ongoing']) ||
        asBool(raw['is_ongoing']) ||
        asBool(raw['isOngoing']) ||
        asBool(raw['foreground_service']) ||
        asBool(raw['is_foreground_service']) ||
        asBool(raw['persistent'])) {
      return true;
    }

    final title = (raw['title'] ?? '').toString();
    final content = (raw['content'] ?? '').toString();
    final combined = '$title $content';
    const keywords = <String>[
      '正在运行',
      '正在通过usb为此设备充电',
      'foreground service',
      'is running',
      'running in background',
    ];
    for (final kw in keywords) {
      if (combined.toLowerCase().contains(kw.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  // ── 窗口吸附 ──────────────────────────────────────────
  @override
  void onWindowMoved() {
    if (!_isDesktopWindow) return;
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

  List<AppNotification> _applySearchFilters(List<AppNotification> list) {
    var out = list;
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((n) {
        final blob = '${n.app} ${n.title} ${n.content}'.toLowerCase();
        return blob.contains(q);
      }).toList();
    }
    if (_filterApp != null && _filterApp!.isNotEmpty) {
      out = out.where((n) => n.app == _filterApp).toList();
    }
    if (_filterCodesOnly) {
      out = out.where((n) => n.categories.contains('codes')).toList();
    }
    if (_timeFilter == _TimeFilterMode.last24h) {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      out = out
          .where((n) {
            final t = parseNotificationTime(n.time);
            if (t == null) return true;
            return !t.isBefore(cutoff);
          })
          .toList();
    } else if (_timeFilter == _TimeFilterMode.last7d) {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      out = out
          .where((n) {
            final t = parseNotificationTime(n.time);
            if (t == null) return true;
            return !t.isBefore(cutoff);
          })
          .toList();
    }
    return out;
  }

  ({AppNotification? notification, bool silentPreview}) _applyRulesTo(
      AppNotification n) {
    var cur = n;
    var skipPreview = false;
    for (final r in _prefs.rules) {
      if (!r.matches(cur.app, cur.title, cur.content)) continue;
      switch (r.action) {
        case RuleAction.ignore:
          return (notification: null, silentPreview: true);
        case RuleAction.markRead:
          cur = cur.markRead();
          break;
        case RuleAction.silence:
          skipPreview = true;
          break;
        case RuleAction.remindOnly:
          final cats = List<String>.from(cur.categories);
          if (!cats.contains('important')) cats.add('important');
          cur = cur.copyWith(categories: cats);
          break;
        case RuleAction.autoCopyCode:
          if (cur.code != null && cur.code!.trim().isNotEmpty) {
            unawaited(
                Clipboard.setData(ClipboardData(text: cur.code!.trim())));
          }
          break;
      }
    }
    return (notification: cur, silentPreview: skipPreview);
  }

  AppNotification? _tryDedupeMerge(AppNotification n) {
    final wsec = _prefs.dedupeWindowSeconds.clamp(5, 3600);
    final window = Duration(seconds: wsec);
    final nt = parseNotificationTime(n.time) ?? DateTime.now();
    for (var i = 0; i < _notifications.length; i++) {
      final o = _notifications[i];
      if (o.id == n.id) continue;
      if (o.app != n.app || o.title != n.title) continue;
      final ot = parseNotificationTime(o.time) ?? nt;
      if (nt.difference(ot).abs() <= window) {
        _notifications[i] = o.copyWith(
          content: n.content,
          time: n.time,
          unread: n.unread || o.unread,
          code: n.code ?? o.code,
          categories:
              n.categories.isNotEmpty ? n.categories : o.categories,
          repeatCount: o.repeatCount + 1,
        );
        return _notifications[i];
      }
    }
    return null;
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
    ({AppNotification? notification, bool silentPreview})? lastIncoming;
    _updateNotifications(() {
      for (final item in list) {
        if (item is! Map) continue;
        lastIncoming =
            _upsertIncomingNotification(Map<String, dynamic>.from(item));
      }
      if (_notifications.length > NotificationStore.maxCount) {
        _notifications.removeRange(
            NotificationStore.maxCount, _notifications.length);
      }
    });
    final li = lastIncoming;
    if (li != null && li.notification != null && !li.silentPreview) {
      unawaited(_showPreviewWindowIfNeeded(li.notification!));
    }
  }

  ({AppNotification? notification, bool silentPreview})
      _upsertIncomingNotification(Map<String, dynamic> raw) {
    if (_isPersistentNotification(raw)) {
      return (notification: null, silentPreview: true);
    }
    var n = _fromJson(raw);
    final applied = _applyRulesTo(n);
    if (applied.notification == null) {
      return (notification: null, silentPreview: true);
    }
    n = applied.notification!;
    final silentPreview = applied.silentPreview;
    final idx = _notifications.indexWhere((x) => x.id == n.id);
    if (idx >= 0) {
      _notifications[idx] = n;
      return (notification: n, silentPreview: silentPreview);
    }
    final merged = _tryDedupeMerge(n);
    if (merged != null) {
      return (notification: merged, silentPreview: silentPreview);
    }
    _notifications.insert(0, n);
    return (notification: n, silentPreview: silentPreview);
  }

  Future<void> _showPreviewWindowIfNeeded(AppNotification n) async {
    if (!_isDesktopWindow) return;
    if (!mounted) return;
    if (n.categories.contains('ignored')) return;
    final seq = ++_desktopPreviewShowSeq;
    try {
      final minimized = await windowManager.isMinimized();
      if (!mounted) return;
      if (seq != _desktopPreviewShowSeq) return;
      if (!minimized) return;
      if (!_useDesktopPreviewSubwindow) {
        if (seq != _desktopPreviewShowSeq) return;
        await NativeFloatPreviewWindows.show(
          n,
          privacyHideContent: _prefs.privacyHideContent,
          sensitiveAppHints: _prefs.sensitiveAppHints,
        );
        return;
      }
      if (seq != _desktopPreviewShowSeq) return;
      final ok = await (_previewWindowController?.showNotification(n) ??
          Future<bool>.value(false));
      if (seq != _desktopPreviewShowSeq) return;
      if (!ok && mounted) await _fallbackMainWindowForMinimizedNotification(n);
    } catch (_) {}
  }

  /// 子窗通道失效时（例如热重载注销了 handler），恢复主窗口并提示，避免用户以为进程死掉。
  Future<void> _fallbackMainWindowForMinimizedNotification(AppNotification n) async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          n.content.isNotEmpty ? '${n.app} · ${n.title}\n${n.content}' : '${n.app} · ${n.title}',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _openMainFromPreviewRequest() async {
    if (!_isDesktopWindow) return;
    await _previewWindowController?.hidePreview();
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  AppNotification _fromJson(Map<String, dynamic> raw) {
    final now = DateTime.now();
    final app = clampNotificationField(
      (raw['app'] ?? '未知应用').toString(),
      kNotificationAppMaxChars,
    );
    final title = clampNotificationField(
      (raw['title'] ?? '新通知').toString(),
      kNotificationTitleMaxChars,
    );
    final content = clampNotificationField(
      (raw['content'] ?? '').toString(),
      kNotificationContentMaxChars,
    );
    final id = (raw['id'] ?? now.millisecondsSinceEpoch).toString();
    final time =
        (raw['time'] ?? '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}')
            .toString();
    final code = clampNotificationField(
      (raw['code'] ?? '').toString(),
      kNotificationCodeMaxChars,
    );

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

    final rc = raw['repeatCount'];
    return AppNotification(
      id: id,
      app: app,
      title: title,
      content: content,
      time: time,
      unread: raw['unread'] != false,
      categories: categories.toList(),
      code: code.isEmpty ? null : code,
      repeatCount: rc is num ? rc.toInt() : 1,
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

  Future<void> _addRuleAndSave(NotificationRule rule) async {
    final next = List<NotificationRule>.from(_prefs.rules)..add(rule);
    setState(() => _prefs = _prefs.copyWith(rules: next));
    await _savePrefs();
  }

  Future<void> _togglePinApp(String app) async {
    final pins = Set<String>.from(_prefs.pinnedApps);
    if (pins.contains(app)) {
      pins.remove(app);
    } else {
      pins.add(app);
    }
    setState(() => _prefs = _prefs.copyWith(pinnedApps: pins));
    await _savePrefs();
  }

  void _markOneRead(AppNotification n) {
    _updateNotifications(() {
      final i = _notifications.indexWhere((x) => x.id == n.id);
      if (i >= 0) _notifications[i] = n.markRead();
    });
  }

  void _copyAllFields(AppNotification n) {
    final t =
        '${n.app}\n${n.title}\n${n.content}${n.code != null ? '\n${n.code}' : ''}';
    unawaited(Clipboard.setData(ClipboardData(text: t)));
  }

  // ── Tab ───────────────────────────────────────────────
  bool _matchTab(AppNotification n, NotificationTab tab) {
    switch (tab) {
      case NotificationTab.all:
        return !n.categories.contains('ignored') && n.unread;
      case NotificationTab.important:
        return n.categories.contains('important') &&
            !n.categories.contains('ignored') &&
            n.unread;
      case NotificationTab.messages:
        return n.categories.contains('messages') &&
            !n.categories.contains('ignored') &&
            n.unread;
      case NotificationTab.codes:
        return n.categories.contains('codes') &&
            !n.categories.contains('ignored') &&
            n.unread;
      case NotificationTab.system:
        return n.categories.contains('system') &&
            !n.categories.contains('ignored') &&
            n.unread;
      case NotificationTab.read:
        return !n.categories.contains('ignored') && !n.unread;
      case NotificationTab.ignored:
        return n.categories.contains('ignored');
    }
  }

  /// Tab 角标：已忽略 tab 显示总条数，其余 tab 只统计未读数。
  int _count(NotificationTab tab) {
    if (tab == NotificationTab.ignored || tab == NotificationTab.read) {
      return _notifications.where((n) => _matchTab(n, tab)).length;
    }
    return _notifications.where((n) => _matchTab(n, tab) && n.unread).length;
  }

  Future<void> _onClose() async {
    if (!_isDesktopWindow) {
      await SystemNavigator.pop();
      return;
    }
    if (_closeAction == WindowAction.hide) {
      await windowManager.hide();
    } else {
      await windowManager.close();
    }
  }

  Widget? _buildHealthBanner() {
    final wsBad = _wsStatus != WsStatus.connected;
    final androidBad = _isAndroid && !_androidListenerEnabled;
    if (!wsBad && !androidBad) return null;
    return Material(
      color: const Color(0xFF3A2A1A),
      borderRadius: BorderRadius.circular(kUnifiedRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                [
                  if (wsBad) 'WebSocket 未连接，通知可能无法到达。',
                  if (androidBad) '未开启系统通知读取权限。',
                ].join('\n'),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () => _wsManager.connect(_urlController.text),
              child: const Text('重连'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final apps = _notifications.map((e) => e.app).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            hintText: '搜索 应用 / 标题 / 正文…',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () =>
                    showNotificationStatsSheet(context, _notifications),
                icon: const Icon(Icons.bar_chart, size: 18),
                label: const Text('统计'),
              ),
              FilterChip(
                label: const Text('仅验证码'),
                selected: _filterCodesOnly,
                onSelected: (v) => setState(() => _filterCodesOnly = v),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('全部时间'),
                selected: _timeFilter == _TimeFilterMode.any,
                onSelected: (_) =>
                    setState(() => _timeFilter = _TimeFilterMode.any),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('24h'),
                selected: _timeFilter == _TimeFilterMode.last24h,
                onSelected: (_) =>
                    setState(() => _timeFilter = _TimeFilterMode.last24h),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('7天'),
                selected: _timeFilter == _TimeFilterMode.last7d,
                onSelected: (_) =>
                    setState(() => _timeFilter = _TimeFilterMode.last7d),
              ),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: _filterApp,
                hint: const Text('应用'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('全部应用')),
                  ...apps.map(
                    (a) => DropdownMenuItem<String?>(value: a, child: Text(a)),
                  ),
                ],
                onChanged: (v) => setState(() => _filterApp = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── UI ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isIgnoredTab = _activeTab == NotificationTab.ignored;
    var filtered =
        _notifications.where((n) => _matchTab(n, _activeTab)).toList();
    filtered = _applySearchFilters(filtered);
    final ignoredCount = _count(NotificationTab.ignored);
    final groupedByApp = <String, List<AppNotification>>{};
    for (final n in filtered) {
      groupedByApp.putIfAbsent(n.app, () => <AppNotification>[]).add(n);
    }
    for (final list in groupedByApp.values) {
      if (_sortMode == NotificationSortMode.appThenOldest) {
        list.sort((a, b) => -_compareByParsedTime(a, b));
      } else {
        list.sort(_compareByParsedTime);
      }
    }
    _appExpanded.removeWhere((app, _) => !groupedByApp.containsKey(app));
    for (final app in groupedByApp.keys) {
      _appExpanded.putIfAbsent(app, () => false);
    }
    final groupedEntries = groupedByApp.entries.toList();
    groupedEntries.sort((a, b) {
      final pinA = _prefs.pinnedApps.contains(a.key);
      final pinB = _prefs.pinnedApps.contains(b.key);
      if (pinA != pinB) return pinA ? -1 : 1;
      if (_sortMode == NotificationSortMode.receivedDesc) {
        final pa = a.value.isEmpty ? null : parseNotificationTime(a.value.first.time);
        final pb = b.value.isEmpty ? null : parseNotificationTime(b.value.first.time);
        if (pa != null && pb != null) return pb.compareTo(pa);
        if (pa != null) return -1;
        if (pb != null) return 1;
        return 0;
      }
      final byApp = a.key.compareTo(b.key);
      if (byApp != 0) return byApp;
      final pa2 = a.value.isEmpty ? null : parseNotificationTime(a.value.first.time);
      final pb2 = b.value.isEmpty ? null : parseNotificationTime(b.value.first.time);
      if (pa2 != null && pb2 != null) return pb2.compareTo(pa2);
      return 0;
    });

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
                  if (!_isDesktopWindow) return;
                  _pinned = !_pinned;
                  await windowManager.setAlwaysOnTop(_pinned);
                  setState(() {});
                },
                onSettings: () => _showSettings(context),
                onMinimize: () {
                  if (_isDesktopWindow) {
                    windowManager.minimize();
                  }
                },
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
                    if (_buildHealthBanner() != null) ...[
                      _buildHealthBanner()!,
                      const SizedBox(height: 8),
                    ],
                    _buildFilterBar(context),
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
                                  privacyHideContent:
                                      _prefs.privacyHideContent,
                                  sensitiveAppHints:
                                      _prefs.sensitiveAppHints,
                                  showPinButton: !isIgnoredTab &&
                                      _activeTab != NotificationTab.read,
                                  isPinned: _prefs.pinnedApps.contains(app),
                                  onTogglePin: () => _togglePinApp(app),
                                  onToggle: () {
                                    final wasExpanded =
                                        _appExpanded[app] ?? false;
                                    final willExpand = !wasExpanded;
                                    setState(
                                        () => _appExpanded[app] = willExpand);
                                    // 仅「先展开再折叠」后整组标已读，避免一点击就全部已读
                                    if (!willExpand && wasExpanded) {
                                      _markGroupRead(app);
                                    }
                                  },
                                  cardBuilder: (n) => NotificationCardView(
                                    n: n,
                                    copied: _copiedId == n.id,
                                    isIgnoredTab: isIgnoredTab,
                                    privacyHideContent:
                                        _prefs.privacyHideContent,
                                    sensitiveAppHints:
                                        _prefs.sensitiveAppHints,
                                    onMarkRead: isIgnoredTab
                                        ? null
                                        : () => _markOneRead(n),
                                    onCopyAll: isIgnoredTab
                                        ? null
                                        : () => _copyAllFields(n),
                                    onAddIgnoreAppRule: isIgnoredTab
                                        ? null
                                        : () async {
                                            await _addRuleAndSave(
                                              NotificationRule(
                                                id:
                                                    'r_${DateTime.now().millisecondsSinceEpoch}',
                                                appContains: n.app,
                                                action: RuleAction.ignore,
                                              ),
                                            );
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        '已添加忽略应用规则')),
                                              );
                                            }
                                          },
                                    onAddIgnoreTitleKeywordRule:
                                        isIgnoredTab
                                            ? null
                                            : () async {
                                                final kw = n.title.length > 40
                                                    ? n.title
                                                        .substring(0, 40)
                                                    : n.title;
                                                await _addRuleAndSave(
                                                  NotificationRule(
                                                    id:
                                                        'r_${DateTime.now().millisecondsSinceEpoch}',
                                                    keywordContains: kw,
                                                    action: RuleAction.ignore,
                                                  ),
                                                );
                                                if (mounted) {
                                                  ScaffoldMessenger.of(
                                                          context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                        content: Text(
                                                            '已添加标题关键字规则')),
                                                  );
                                                }
                                              },
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
                                    onOpenAppHint: isIgnoredTab
                                        ? null
                                        : () {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    '请在设备上手动打开「${n.app}」'),
                                              ),
                                            );
                                          },
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
    var localSortMode = _sortMode;
    final hintsCtrl =
        TextEditingController(text: _prefs.sensitiveAppHints.join(', '));
    final dedupeCtrl =
        TextEditingController(text: '${_prefs.dedupeWindowSeconds}');
    final localPriv = <bool>[_prefs.privacyHideContent];

    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF151A23),
          title: const Text('设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: local,
                  decoration: const InputDecoration(
                    labelText: 'WebSocket 地址（接收端）',
                    helperText:
                        '安卓发送端：ws://手机IP:8765/notifications；本机脚本：ws://127.0.0.1:8765/notifications',
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<WindowAction>(
                  initialValue: localAction,
                  items: const [
                    DropdownMenuItem(
                        value: WindowAction.hide,
                        child: Text('隐藏窗口（推荐）')),
                    DropdownMenuItem(
                        value: WindowAction.close, child: Text('退出应用')),
                  ],
                  onChanged: (v) => localAction = v ?? WindowAction.hide,
                  decoration: const InputDecoration(labelText: '关闭按钮行为'),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<NotificationSortMode>(
                  initialValue: localSortMode,
                  items: NotificationSortMode.values
                      .map(
                        (m) => DropdownMenuItem<NotificationSortMode>(
                          value: m,
                          child: Text(_sortLabels[m]!),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => localSortMode = v ?? _sortMode,
                  decoration: const InputDecoration(labelText: '通知排序方式'),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('隐私模式（列表与浮窗隐藏正文）'),
                  value: localPriv[0],
                  onChanged: (v) => setDlg(() => localPriv[0] = v),
                ),
                TextField(
                  controller: hintsCtrl,
                  decoration: const InputDecoration(
                    labelText: '敏感应用关键词（逗号分隔）',
                    helperText: '应用名包含任一则隐藏正文',
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: dedupeCtrl,
                  decoration: const InputDecoration(
                    labelText: '去重合并时间窗口（秒）',
                    helperText: '同应用同标题在此时间内合并为一条并计数',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(dlgCtx);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        unawaited(presentOnboardingFlow(
                          context,
                          markCompletedWhenDone: true,
                        ));
                      }
                    });
                  },
                  child: const Text('重新查看新手引导'),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(dlgCtx);
                    unawaited(_showRulesManagerDialog(context));
                  },
                  child: const Text('管理通知规则'),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () async {
                    final bundle = <String, dynamic>{
                      'exportVersion': 1,
                      'preferences': _prefs
                          .copyWith(
                            closeAction: localAction,
                            sortModeName: localSortMode.name,
                          )
                          .toJson(),
                    };
                    await Clipboard.setData(
                        ClipboardData(text: jsonEncode(bundle)));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已导出到剪贴板')),
                      );
                    }
                  },
                  child: const Text('导出配置到剪贴板'),
                ),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(dlgCtx);
                    unawaited(_showImportDialog(context));
                  },
                  child: const Text('从剪贴板导入配置'),
                ),
                const SizedBox(height: 12),
                if (_isAndroid) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      await AndroidNotificationBridge.openListenerSettings();
                      final enabled =
                          await AndroidNotificationBridge.isListenerEnabled();
                      if (mounted) {
                        setState(() => _androidListenerEnabled = enabled);
                      }
                      setDlg(() {});
                    },
                    icon: Icon(
                      _androidListenerEnabled
                          ? Icons.check_circle
                          : Icons.settings,
                      size: 16,
                    ),
                    label: Text(_androidListenerEnabled
                        ? '通知读取权限：已开启'
                        : '开启系统通知读取权限'),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: () async {
                    await _store.clear();
                    _updateNotifications(() => _notifications.clear());
                    if (dlgCtx.mounted) Navigator.pop(dlgCtx);
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
          ),
          actions: [
            TextButton(
              onPressed: () => _wsManager.connect(local.text.trim()),
              child: const Text('测试连接'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final ded = int.tryParse(dedupeCtrl.text.trim());
                setState(() {
                  _urlController.text = local.text.trim();
                  _closeAction = localAction;
                  _sortMode = localSortMode;
                  _prefs = _prefs.copyWith(
                    privacyHideContent: localPriv[0],
                    sensitiveAppHints: hintsCtrl.text
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                    dedupeWindowSeconds:
                        (ded != null && ded > 0) ? ded : _prefs.dedupeWindowSeconds,
                    closeAction: localAction,
                    sortModeName: localSortMode.name,
                  );
                });
                unawaited(_prefsStore.save(_prefs));
                _wsManager.connect(_urlController.text);
                Navigator.pop(dlgCtx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  String _ruleLabel(NotificationRule r) {
    final hint = r.appContains?.isNotEmpty == true
        ? '应用:${r.appContains}'
        : (r.keywordContains?.isNotEmpty == true
            ? '关键词:${r.keywordContains}'
            : (r.regexPattern?.isNotEmpty == true
                ? '正则:${r.regexPattern}'
                : '(空)'));
    return '${r.action.name} · $hint';
  }

  Future<void> _showRulesManagerDialog(BuildContext context) async {
    var localRules = List<NotificationRule>.from(_prefs.rules);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF151A23),
          title: const Text('通知规则'),
          content: SizedBox(
            width: 460,
            height: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final created = await _showAddRuleDialog(context);
                      if (created != null) {
                        setD(() => localRules.add(created));
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加规则'),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: localRules
                        .map(
                          (r) => ListTile(
                            title: Text(
                              _ruleLabel(r),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.white38),
                              onPressed: () =>
                                  setD(() => localRules.remove(r)),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() => _prefs = _prefs.copyWith(rules: localRules));
                unawaited(_prefsStore.save(_prefs));
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<NotificationRule?> _showAddRuleDialog(BuildContext context) async {
    return showDialog<NotificationRule>(
      context: context,
      builder: (ctx) {
        final act = <RuleAction>[RuleAction.ignore];
        final appCtrl = TextEditingController();
        final kwCtrl = TextEditingController();
        final reCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            backgroundColor: const Color(0xFF151A23),
            title: const Text('添加规则'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('动作',
                        style: TextStyle(fontSize: 12, color: Colors.white54)),
                  ),
                  const SizedBox(height: 4),
                  DropdownButton<RuleAction>(
                    isExpanded: true,
                    value: act[0],
                    items: const [
                      DropdownMenuItem(
                          value: RuleAction.ignore, child: Text('忽略')),
                      DropdownMenuItem(
                          value: RuleAction.markRead, child: Text('标为已读')),
                      DropdownMenuItem(
                          value: RuleAction.silence, child: Text('静音预览')),
                      DropdownMenuItem(
                          value: RuleAction.remindOnly, child: Text('仅强化提醒')),
                      DropdownMenuItem(
                          value: RuleAction.autoCopyCode,
                          child: Text('自动复制验证码')),
                    ],
                    onChanged: (v) =>
                        setSt(() => act[0] = v ?? RuleAction.ignore),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: appCtrl,
                    decoration: const InputDecoration(
                      labelText: '应用名包含（可选）',
                    ),
                  ),
                  TextField(
                    controller: kwCtrl,
                    decoration: const InputDecoration(
                      labelText: '标题/正文关键词（可选）',
                    ),
                  ),
                  TextField(
                    controller: reCtrl,
                    decoration: const InputDecoration(
                      labelText: '正则（可选，慎用）',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final rule = NotificationRule(
                    id: 'r_${DateTime.now().millisecondsSinceEpoch}',
                    appContains: appCtrl.text.trim().isEmpty
                        ? null
                        : appCtrl.text.trim(),
                    keywordContains: kwCtrl.text.trim().isEmpty
                        ? null
                        : kwCtrl.text.trim(),
                    regexPattern: reCtrl.text.trim().isEmpty
                        ? null
                        : reCtrl.text.trim(),
                    action: act[0],
                  );
                  final has = rule.appContains?.isNotEmpty == true ||
                      rule.keywordContains?.isNotEmpty == true ||
                      rule.regexPattern?.isNotEmpty == true;
                  if (!has) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请至少填写一项匹配条件')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, rule);
                },
                child: const Text('添加'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151A23),
        title: const Text('导入配置'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctrl,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '粘贴导出 JSON',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final map =
                    jsonDecode(ctrl.text.trim()) as Map<String, dynamic>;
                final inner = map['preferences'] as Map<String, dynamic>? ??
                    map;
                final p = AppPreferences.fromJson(
                    Map<String, dynamic>.from(inner));
                setState(() {
                  _prefs = p;
                  _closeAction = p.closeAction;
                  _sortMode = NotificationSortMode.values.firstWhere(
                    (e) => e.name == p.sortModeName,
                    orElse: () => NotificationSortMode.receivedDesc,
                  );
                });
                unawaited(_prefsStore.save(p));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('导入成功')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('导入失败: $e')),
                );
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }
}