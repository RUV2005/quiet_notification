import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'preview_popup.dart';

/// 子窗口中的预览应用：仅负责展示和用户动作回传。
class PreviewWindowApp extends StatelessWidget {
  const PreviewWindowApp({
    super.key,
    required this.windowController,
  });

  final WindowController windowController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PreviewWindowPage(windowController: windowController),
    );
  }
}

class PreviewWindowPage extends StatefulWidget {
  const PreviewWindowPage({
    super.key,
    required this.windowController,
  });

  final WindowController windowController;

  @override
  State<PreviewWindowPage> createState() => _PreviewWindowPageState();
}

class _PreviewWindowPageState extends State<PreviewWindowPage> {
  static const WindowMethodChannel _actionChannel = WindowMethodChannel(
    'quick_notification_preview_action',
    mode: ChannelMode.unidirectional,
  );

  static const Size _previewSize = Size(360, 200);
  static const double _previewMargin = 10;

  Timer? _autoHideTimer;
  AppNotification? _notification;

  @override
  void initState() {
    super.initState();
    unawaited(_initPreviewWindow());
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    unawaited(widget.windowController.setWindowMethodHandler(null));
    super.dispose();
  }

  Future<void> _initPreviewWindow() async {
    await windowManager.ensureInitialized();
    await widget.windowController.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'show_preview':
          final args = (call.arguments as Map?)?.cast<dynamic, dynamic>() ?? const {};
          final raw = args['notification'];
          if (raw is Map) {
            final n = AppNotification.fromJson(Map<String, dynamic>.from(raw));
            await _showPreview(n);
          }
          return null;
        case 'hide_preview':
          await _hidePreview();
          return null;
        default:
          return null;
      }
    });
  }

  Future<void> _showPreview(AppNotification n) async {
    _autoHideTimer?.cancel();
    setState(() => _notification = n);
    await _positionAndPrepareWindow();

    _autoHideTimer = Timer(const Duration(seconds: 7), () {
      _hidePreview();
    });
  }

  Future<void> _hidePreview() async {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    setState(() => _notification = null);
    await windowManager.hide();
  }

  Future<void> _positionAndPrepareWindow() async {
    final displays = await screenRetriever.getAllDisplays();
    Rect workArea;
    if (displays.isEmpty) {
      workArea = const Rect.fromLTWH(0, 0, 1920, 1080);
    } else {
      final display = displays.first;
      final position = display.visiblePosition ?? Offset.zero;
      final size = display.visibleSize ?? display.size;
      workArea = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
    }

    final width = math.min(_previewSize.width, workArea.width - _previewMargin * 2);
    final height = math.min(_previewSize.height, workArea.height - _previewMargin * 2);
    final left = workArea.right - width - _previewMargin;
    final top = workArea.bottom - height - _previewMargin;

    await windowManager.setMinimumSize(const Size(300, 160));
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setBounds(
      Rect.fromLTWH(left, top, width, height),
      animate: true,
    );
    await windowManager.show();
  }

  Future<void> _copyText() async {
    final text = _notification?.code ?? _notification?.content ?? '';
    await _actionChannel.invokeMethod('copy_text', <String, dynamic>{'text': text});
    await _hidePreview();
  }

  Future<void> _openMain() async {
    await _actionChannel.invokeMethod('open_main');
    await _hidePreview();
  }

  @override
  Widget build(BuildContext context) {
    if (_notification == null) {
      return const Scaffold(backgroundColor: Color(0xFF161B24));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF161B24),
      body: MinimizedPreviewCard(
        notification: _notification!,
        onCopy: _copyText,
        onOpen: _openMain,
        onIgnore: _hidePreview,
      ),
    );
  }
}
