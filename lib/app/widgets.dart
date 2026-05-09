import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';

import 'constants.dart';
import 'models.dart';
import 'websocket_manager.dart';

// ── 标题栏 ────────────────────────────────────────────────────────────────────

/// 自定义标题栏（拖拽区 + 连接状态 + 固定/设置/最小化/关闭）。
class HeaderBar extends StatelessWidget {
  const HeaderBar({
    super.key,
    required this.pinned,
    required this.wsStatus,
    required this.onPin,
    required this.onSettings,
    required this.onMinimize,
    required this.onClose,
    required this.onReconnect,
  });

  final bool pinned;
  final WsStatus wsStatus;
  final VoidCallback onPin;
  final VoidCallback onSettings;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Row(
        children: [
          Expanded(
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
                    colorFilter:
                        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    '通知助手',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                // 连接状态指示器
                WsStatusDot(
                  status: wsStatus,
                  onReconnect: onReconnect,
                ),
              ],
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

/// WebSocket 连接状态指示点，点击可手动重连。
class WsStatusDot extends StatelessWidget {
  const WsStatusDot({
    super.key,
    required this.status,
    required this.onReconnect,
  });

  final WsStatus status;
  final VoidCallback onReconnect;

  static const _labels = <WsStatus, String>{
    WsStatus.connected: '已连接',
    WsStatus.connecting: '连接中',
    WsStatus.reconnecting: '重连中',
    WsStatus.disconnected: '未连接',
  };

  static const _colors = <WsStatus, Color>{
    WsStatus.connected: Color(0xFF4CAF50),
    WsStatus.connecting: Color(0xFFFFC107),
    WsStatus.reconnecting: Color(0xFFFF9800),
    WsStatus.disconnected: Color(0xFF757575),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[status]!;
    final label = _labels[status]!;
    final canReconnect = status == WsStatus.disconnected ||
        status == WsStatus.reconnecting;

    return Tooltip(
      message: canReconnect ? '$label（点击立即重连）' : label,
      child: InkWell(
        onTap: canReconnect ? onReconnect : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 状态圆点，connecting/reconnecting 时加呼吸动画
              status == WsStatus.connecting ||
                      status == WsStatus.reconnecting
                  ? _PulsingDot(color: color)
                  : Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color),
              ),
              if (canReconnect) ...[
                const SizedBox(width: 3),
                Icon(Icons.refresh, size: 13, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 脉冲闪烁圆点（用于 connecting / reconnecting 状态）。
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// 标题栏图标按钮。
class TitleBtn extends StatelessWidget {
  const TitleBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

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

// ── 标签栏 ────────────────────────────────────────────────────────────────────

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
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: active ? Colors.blue : Colors.white12,
                  borderRadius: BorderRadius.circular(kUnifiedRadius),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: FontWeight.w700),
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final t in NotificationTab.values) ...[
            _buildTabChip(t),
            if (t != NotificationTab.values.last)
              const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

// ── 通知卡片 ──────────────────────────────────────────────────────────────────

/// 单条通知卡片。
///
/// - [isIgnoredTab]：true 时显示"恢复"按钮；false 时显示"忽略"按钮。
/// - 未读条目左侧有蓝色竖线标识。
class NotificationCardView extends StatelessWidget {
  const NotificationCardView({
    super.key,
    required this.n,
    required this.copied,
    required this.isIgnoredTab,
    this.onCopy,
    this.onIgnore,
    this.onUnignore,
  });

  final AppNotification n;
  final bool copied;
  final bool isIgnoredTab;
  final VoidCallback? onCopy;
  final VoidCallback? onIgnore;
  final VoidCallback? onUnignore;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kUnifiedRadius),
        border: Border.all(
          color: n.unread ? Colors.blue.withValues(alpha: 0.5) : Colors.white12,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 未读蓝色竖线
            if (n.unread)
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: Colors.lightBlueAccent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(kUnifiedRadius),
                    bottomLeft: Radius.circular(kUnifiedRadius),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
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
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: n.unread
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            n.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: n.unread
                                  ? Colors.white70
                                  : Colors.white38,
                              fontSize: 14,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          n.time,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        // 操作按钮行
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 忽略 / 恢复
                            if (isIgnoredTab)
                              _SmallButton(
                                label: '恢复',
                                icon: Icons.undo,
                                onTap: onUnignore,
                              )
                            else
                              _SmallButton(
                                label: '忽略',
                                icon: Icons.visibility_off_outlined,
                                onTap: onIgnore,
                                danger: true,
                              ),
                            // 复制验证码
                            if (onCopy != null) ...[
                              const SizedBox(width: 6),
                              _SmallButton(
                                label: copied ? '已复制' : '复制',
                                icon: copied
                                    ? Icons.check
                                    : Icons.copy_outlined,
                                onTap: onCopy,
                                highlight: copied,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片内小操作按钮（图标 + 文字）。
class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.danger = false,
    this.highlight = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    Color fgColor;
    if (highlight) {
      fgColor = Colors.lightBlueAccent;
    } else if (danger) {
      fgColor = Colors.white38;
    } else {
      fgColor = Colors.white60;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: highlight
                ? Colors.lightBlueAccent.withValues(alpha: 0.4)
                : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fgColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: fgColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 应用分组卡片 ──────────────────────────────────────────────────────────────

/// 按应用聚合的分组卡片，展开查看明细通知。
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
        border: Border.all(
          color: unreadCount > 0
              ? Colors.blue.withValues(alpha: 0.3)
              : Colors.white12,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(kUnifiedRadius),
            onTap: onToggle,
            child: Container(
              constraints: const BoxConstraints(minHeight: 80),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 未读角标
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      buildAppAvatar(
                        appName: app,
                        fallbackText:
                            String.fromCharCodes(app.runes.take(2)),
                        size: 48,
                        fallbackFontSize: 17,
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                                minWidth: 18, minHeight: 18),
                            child: Text(
                              '$unreadCount',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
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
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${notifications.length} 条',
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${latest.title} · ${latest.content}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unreadCount > 0
                                ? Colors.white70
                                : Colors.white38,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        latest.time,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Icon(
                        expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: Colors.white54,
                      ),
                    ],
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
                  for (var i = 0; i < notifications.length; i++) ...[
                    cardBuilder(notifications[i]),
                    if (i != notifications.length - 1)
                      const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}