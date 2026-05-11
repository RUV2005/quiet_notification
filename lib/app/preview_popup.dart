import 'package:flutter/material.dart';

import 'constants.dart';
import 'models.dart';

/// 最小化状态右下角预览卡片（独立模块）。
class MinimizedPreviewCard extends StatelessWidget {
  const MinimizedPreviewCard({
    super.key,
    required this.notification,
    required this.onCopy,
    required this.onOpen,
    required this.onIgnore,
  });

  final AppNotification notification;
  final Future<void> Function() onCopy;
  final Future<void> Function() onOpen;
  final Future<void> Function() onIgnore;

  @override
  Widget build(BuildContext context) {
    final copyLabel = notification.code == null ? '复制内容' : '复制';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B24).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              buildAppAvatar(
                appName: notification.app,
                fallbackText: notification.appShort,
                size: 22,
                fallbackFontSize: 10,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${notification.title} · ${notification.app}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatFriendlyTime(notification.time),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              IconButton(
                onPressed: onIgnore,
                splashRadius: 12,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                icon: const Icon(Icons.close, color: Colors.white70, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            notification.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            notification.code ?? notification.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF3EA4FF),
              fontSize: 24,
              height: 1.05,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '来自：${notification.app}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCopy,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    side: const BorderSide(color: Colors.white30),
                  ),
                  child: Text(copyLabel, style: const TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton(
                  onPressed: onOpen,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    backgroundColor: const Color(0xFF2A3342),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('打开应用', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton(
                  onPressed: onIgnore,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    backgroundColor: const Color(0xFF2A3342),
                    foregroundColor: Colors.white70,
                  ),
                  child: const Text('忽略', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
