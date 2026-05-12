import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'onboarding_store.dart';

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;
}

/// 首次使用全屏引导；完成后写入 [OnboardingStore]。
Future<void> presentOnboardingFlow(
  BuildContext context, {
  bool markCompletedWhenDone = true,
}) async {
  final isWin = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  final pages = <_OnboardingPageData>[
    const _OnboardingPageData(
      title: '欢迎使用通知助手',
      body:
          '本应用作为「接收端」汇总来自手机脚本、自建服务或局域网推送的通知，'
          '并按应用分组展示。下面几步帮你快速上手。',
      icon: Icons.waving_hand_rounded,
    ),
    const _OnboardingPageData(
      title: '保持连接',
      body:
          '标题栏右侧圆点表示 WebSocket 状态：绿色为已连接。'
          '若断开，可点「重连」或打开设置检查地址。\n\n'
          '默认地址可在「设置」里改成你的推送端，例如本机脚本：\n'
          'ws://127.0.0.1:8765/notifications',
      icon: Icons.wifi_tethering_rounded,
    ),
    const _OnboardingPageData(
      title: '标签与列表',
      body:
          '顶部标签可筛选：全部、重要、消息、验证码、系统、已读、已忽略。\n\n'
          '点击分组行可展开查看该应用下的多条通知；'
          '「先展开再折叠」后，该组未读会标为已读。',
      icon: Icons.filter_list_rounded,
    ),
    const _OnboardingPageData(
      title: '搜索与统计',
      body:
          '列表上方可搜索正文、按应用与时间范围筛选，并可打开「统计」'
          '查看数量与应用分布。',
      icon: Icons.search_rounded,
    ),
    const _OnboardingPageData(
      title: '规则与隐私',
      body:
          '在「设置」中可配置：通知排序、隐私模式、去重时间窗口、'
          '导入导出配置，以及「管理通知规则」（按应用/关键词忽略等）。\n\n'
          '单条卡片右上角「⋯」也可快速添加忽略规则。',
      icon: Icons.shield_outlined,
    ),
    if (isWin)
      const _OnboardingPageData(
        title: 'Windows 托盘',
        body:
            '窗口最小化或隐藏后，可从任务栏旁的系统托盘图标唤回主窗口；'
            '托盘菜单还支持「全部标已读」「清空已读」与最近通知快捷入口。',
        icon: Icons.desktop_windows_rounded,
      ),
    const _OnboardingPageData(
      title: '开始使用',
      body:
          '随时可以打开右上角「设置」修改连接与偏好；'
          '若使用安卓端转发通知，请在手机上授予通知监听权限。\n\n'
          '祝你使用愉快！',
      icon: Icons.rocket_launch_rounded,
    ),
  ];

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      return _OnboardingDialogContent(
        pages: pages,
        markCompletedWhenDone: markCompletedWhenDone,
      );
    },
  );
}

class _OnboardingDialogContent extends StatefulWidget {
  const _OnboardingDialogContent({
    required this.pages,
    required this.markCompletedWhenDone,
  });

  final List<_OnboardingPageData> pages;
  final bool markCompletedWhenDone;

  @override
  State<_OnboardingDialogContent> createState() => _OnboardingDialogContentState();
}

class _OnboardingDialogContentState extends State<_OnboardingDialogContent> {
  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (widget.markCompletedWhenDone) {
      await OnboardingStore.instance.markCompleted();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final last = _index >= widget.pages.length - 1;

    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: const Color(0xFF0D1117),
      child: SizedBox(
        width: size.width.clamp(320, 560),
        height: (size.height * 0.88).clamp(480.0, 720.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  const Text(
                    '新手引导',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: const Text('跳过'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (ctx, i) {
                  final p = widget.pages[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        Icon(p.icon, size: 56, color: Colors.lightBlueAccent),
                        const SizedBox(height: 20),
                        Text(
                          p.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              p.body,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.pages.length,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Icon(
                          Icons.circle,
                          size: i == _index ? 8 : 6,
                          color: i == _index
                              ? Colors.lightBlueAccent
                              : Colors.white24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_index > 0)
                        OutlinedButton(
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          child: const Text('上一步'),
                        )
                      else
                        const SizedBox(width: 88),
                      const Spacer(),
                      FilledButton(
                        onPressed: last
                            ? _finish
                            : () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                );
                              },
                        child: Text(last ? '开始使用' : '下一步'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
