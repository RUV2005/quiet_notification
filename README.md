# Quick Notification (Flutter)

一个运行在桌面的 Flutter 通知助手，支持：
- WebSocket 作为**接收端**实时读取通知数据（可与安卓 `quietNotification` 发送端或本机脚本对接）
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

## WebSocket 接入（Flutter 为接收端）

Flutter 应用使用 **WebSocket 客户端**连接数据源。

### 方式 A：安卓手机作为发送端（嵌入式服务）

安卓工程 `quietNotification` 在本机启动 WebSocket **服务端**，路径固定为：

`ws://<手机局域网IPv4>:8765/notifications`

1. 手机与电脑同一 Wi‑Fi。
2. 打开安卓应用，界面会显示完整连接地址（含当前检测到的 IPv4）。
3. 在 Flutter 桌面端右上角「设置」里把 WebSocket 地址填成该地址并保存。
4. 安卓端点击「发送测试通知」即可在桌面端列表中看到数据。

> 若连接失败：确认手机未限制「局域网内被访问」、电脑防火墙放行到该端口的出站访问；仍使用明文 `ws://` 时双方需允许明文（安卓端已配置 `network_security_config`）。

### 方式 B：本机 Python 演示脚本

默认地址：

`ws://127.0.0.1:8765/notifications`

先运行 `python_push/push_notifications.py` 再启动 Flutter，或在应用「设置」中修改并测试连接。

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
