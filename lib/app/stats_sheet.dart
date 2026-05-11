import 'package:flutter/material.dart';

import 'constants.dart';
import 'models.dart';

/// 底部弹层：通知统计（今日/本周、应用分布、分类占比）。
void showNotificationStatsSheet(
  BuildContext context,
  List<AppNotification> notifications,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF151A23),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final now = DateTime.now();
      final today0 = DateTime(now.year, now.month, now.day);
      final week0 = today0.subtract(Duration(days: today0.weekday - 1));

      int total = notifications.length;
      int today = 0;
      int week = 0;
      int codes = 0;
      int ignored = 0;
      int unread = 0;
      final byApp = <String, int>{};

      for (final n in notifications) {
        final t = parseNotificationTime(n.time);
        if (t != null) {
          if (!t.isBefore(today0)) today++;
          if (!t.isBefore(week0)) week++;
        }
        byApp[n.app] = (byApp[n.app] ?? 0) + 1;
        if (n.categories.contains('codes')) codes++;
        if (n.categories.contains('ignored')) ignored++;
        if (n.unread) unread++;
      }

      final topApps = byApp.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '通知统计',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  _row('总条数', '$total'),
                  _row('今日', '$today'),
                  _row('本周', '$week'),
                  _row('未读', '$unread'),
                  _row('验证码类', '$codes'),
                  _row('已忽略', '$ignored'),
                  const SizedBox(height: 12),
                  const Text('应用 Top 8',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 6),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: topApps.length > 8 ? 8 : topApps.length,
                    itemBuilder: (_, i) {
                      final e = topApps[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text('${e.value}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 13)),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget _row(String k, String v) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(color: Colors.white70)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
