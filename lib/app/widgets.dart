import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import 'constants.dart';
import 'models.dart';

/// 自定义标题栏（拖拽区 + 固定/设置/最小化/关闭）。
class HeaderBar extends StatelessWidget {
  const HeaderBar({
    super.key,
    required this.pinned,
    required this.onPin,
    required this.onSettings,
    required this.onMinimize,
    required this.onClose,
  });

  final bool pinned;
  final VoidCallback onPin;
  final VoidCallback onSettings;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(kUnifiedRadius),
                    ),
                    child: SvgPicture.asset(
                      'lib/assets/notice.svg',
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      '通知助手',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          TitleBtn(icon: Icons.push_pin, active: pinned, onTap: onPin),
          TitleBtn(icon: Icons.settings, onTap: onSettings),
          TitleBtn(icon: Icons.remove, onTap: onMinimize),
          TitleBtn(icon: Icons.close, onTap: onClose),
        ],
      ),
    );
  }
}

/// 标题栏图标按钮组件。
class TitleBtn extends StatelessWidget {
  const TitleBtn({super.key, required this.icon, required this.onTap, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(kUnifiedRadius),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 28,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 24,
            color: active ? Colors.lightBlueAccent : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// 顶部筛选标签条（支持横向滚动和数量徽标）。
class NotificationTabsBar extends StatelessWidget {
  const NotificationTabsBar({
    super.key,
    required this.activeTab,
    required this.countOf,
    required this.onChanged,
  });

  final NotificationTab activeTab;
  final int Function(NotificationTab) countOf;
  final ValueChanged<NotificationTab> onChanged;

  static const labels = <NotificationTab, String>{
    NotificationTab.all: '全部',
    NotificationTab.important: '重要',
    NotificationTab.messages: '消息',
    NotificationTab.codes: '验证码',
    NotificationTab.system: '系统',
    NotificationTab.ignored: '已忽略',
  };

  Widget _buildTabChip(NotificationTab t) {
    final active = activeTab == t;
    final count = countOf(t);
    return InkWell(
      borderRadius: BorderRadius.circular(kUnifiedRadius),
      onTap: () => onChanged(t),
      child: Container(
        constraints: const BoxConstraints(minHeight: 38),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labels[t]!,
              style: TextStyle(
                color: active ? Colors.lightBlueAccent : Colors.white70,
                fontSize: 17,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(kUnifiedRadius),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(fontSize: 13, height: 1.1, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalTabs = NotificationTab.values
        .where((t) => t != NotificationTab.ignored)
        .toList();
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < normalTabs.length; i++) ...[
                  _buildTabChip(normalTabs[i]),
                  if (i != normalTabs.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 单条通知卡片（用于应用分组展开后的明细列表）。
class NotificationCardView extends StatelessWidget {
  const NotificationCardView({
    super.key,
    required this.n,
    required this.copied,
    this.onCopy,
  });

  final AppNotification n;
  final bool copied;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kUnifiedRadius),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          buildAppAvatar(
            appName: n.app,
            fallbackText: n.appShort,
            size: 44,
            fallbackFontSize: 15,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${n.app} · ${n.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  n.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                n.time,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 6),
              if (onCopy != null)
                OutlinedButton(
                  onPressed: onCopy,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(78, 32),
                  ),
                  child: Text(
                    copied ? '已复制' : '复制',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 按应用聚合后的分组卡片，可展开查看该应用下全部通知。
class AppGroupCard extends StatelessWidget {
  const AppGroupCard({
    super.key,
    required this.app,
    required this.notifications,
    required this.expanded,
    required this.onToggle,
    required this.cardBuilder,
  });

  final String app;
  final List<AppNotification> notifications;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget Function(AppNotification n) cardBuilder;

  @override
  Widget build(BuildContext context) {
    final unreadCount = notifications.where((n) => n.unread).length;
    final latest = notifications.first;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(kUnifiedRadius),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(kUnifiedRadius),
            onTap: onToggle,
            child: Container(
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  buildAppAvatar(
                    appName: app,
                    fallbackText: String.fromCharCodes(app.runes.take(2)),
                    size: 48,
                    fallbackFontSize: 17,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                app,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${notifications.length} 条',
                              style: const TextStyle(color: Colors.white60, fontSize: 15),
                            ),
                            if (unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                '未读 $unreadCount',
                                style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 15),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${latest.title} · ${latest.content}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    latest.time,
                    style: const TextStyle(color: Colors.white54, fontSize: 15),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  for (var i = 0; i < notifications.length; i++) ...[
                    cardBuilder(notifications[i]),
                    if (i != notifications.length - 1) const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

