import 'package:flutter/material.dart';

/// 全局圆角：主界面、分组卡片、按钮尽量统一视觉风格。
const double kUnifiedRadius = 10;

/// 应用名关键字到图标资源的映射，用于通知卡片头像自动识别。
const Map<String, String> kAppIconMap = <String, String>{
  '微信': 'lib/assets/wechat.png',
  'qq': 'lib/assets/qq.png',
  '钉钉': 'lib/assets/dingding.png',
  '淘宝': 'lib/assets/taobao.png',
  '京东': 'lib/assets/jd.png',
  '菜鸟': 'lib/assets/taobao.png',
  '日历': 'lib/assets/calendar.png',
  '短信': 'lib/assets/text_message.png',
  '支付宝': 'lib/assets/alipay.png',
  '银行通知': 'lib/assets/bank.png',
  '系统': 'lib/assets/notice.png',
};

/// 根据应用名匹配对应图标资源，未匹配到时返回 null 使用文字头像。
String? resolveAppIconAsset(String appName) {
  final lower = appName.toLowerCase();
  for (final entry in kAppIconMap.entries) {
    if (lower.contains(entry.key)) {
      return entry.value;
    }
  }
  return null;
}

/// 构建通知中的应用头像：优先图标，失败时回退到应用简称文字。
Widget buildAppAvatar({
  required String appName,
  required String fallbackText,
  required double size,
  required double fallbackFontSize,
}) {
  final iconAsset = resolveAppIconAsset(appName);
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.blue,
      borderRadius: BorderRadius.circular(kUnifiedRadius),
    ),
    child: iconAsset == null
        ? Text(
            fallbackText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: fallbackFontSize,
            ),
          )
        : Padding(
            padding: const EdgeInsets.all(4),
            child: Image.asset(
              iconAsset,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Text(
                fallbackText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: fallbackFontSize,
                ),
              ),
            ),
          ),
  );
}
