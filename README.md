# Quick Notification (Flutter)

一个运行在桌面的 Flutter 通知助手，支持：
- WebSocket 实时读取通知数据
- 按分类过滤（全部 / 重要 / 消息 / 验证码 / 系统 / 已忽略）
- 验证码一键复制
- 置顶、最小化、关闭行为设置
- 拖动贴近屏幕边缘自动贴边

## 运行项目（Windows）

在项目根目录执行：

```bash
flutter pub get
flutter run -d windows
```

## WebSocket 接入

默认地址：

`ws://127.0.0.1:8765/notifications`

可以在应用右上角「设置」中修改并测试连接。

### 消息格式（JSON）

支持单条对象或对象数组。

```json
{
  "id": "msg-1001",
  "app": "微信",
  "title": "张经理",
  "content": "今晚 8 点开会",
  "time": "21:03",
  "important": true,
  "ignored": false,
  "code": "",
  "unread": true,
  "categories": ["messages", "important"]
}
```

字段说明：
- `id`: 通知唯一 ID（重复 ID 会覆盖更新）
- `app/title/content/time`: 展示文本
- `important/ignored/unread`: 状态位
- `code`: 验证码（存在时显示复制按钮）
- `categories`: 可选，留空时由应用自动推断分类

## 项目结构（Flutter 主实现）

- 主入口：`lib/main.dart`
- 应用图标资源：`lib/assets/*.png`
- 依赖配置：`pubspec.yaml`

## Python 推送脚本

- 脚本路径：`python_push/push_notifications.py`
- 用于向本地 WebSocket 服务发送测试通知数据。
