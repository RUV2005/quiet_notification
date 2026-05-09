#!/usr/bin/env python3
"""
WebSocket 通知推送服务（用于本地演示）。

启动后监听:
  ws://127.0.0.1:8765/notifications

你的应用连接后，将每一定间隔收到通知。
每个客户端独立维护状态，互不干扰。
"""

import asyncio
import json
import logging
import random
import signal
import uuid
from datetime import datetime

import websockets

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("push")

HOST = "127.0.0.1"
PORT = 8765
PATH = "/notifications"
INTERVAL_MIN_SECONDS = 0.6
INTERVAL_MAX_SECONDS = 2.8

CHAT_CONTACTS = [
    ("微信", "张经理", ["今晚过下方案", "预算表我放群里了", "你确认下排期", "先按 v2 走"]),
    ("微信", "产品群", ["明早 10 点评审", "PRD 已更新到 1.8", "交互稿刚改完"]),
    ("QQ", "项目组", ["测试环境刚重启", "线上日志我发你了", "这个 bug 能复现"]),
    ("钉钉", "运营组", ["活动文案已提审", "素材还差封面图", "今晚 9 点前上线"]),
]

LOGISTICS_TRACK = [
    "商家已发货",
    "快件已揽收",
    "快件离开【上海转运中心】",
    "快件到达【杭州转运中心】",
    "快件正在派送",
    "包裹已签收",
]


def random_code():
    return f"{random.randint(100000, 999999)}"


def hour_weights() -> tuple[float, float, float]:
    h = datetime.now().hour
    if 9 <= h <= 18:
        return 0.60, 0.33, 0.07
    if 19 <= h <= 23:
        return 0.52, 0.30, 0.18
    return 0.30, 0.40, 0.30


def maybe_start_conversation(state: dict):
    if state["conversation_left"] > 0:
        return
    if random.random() < 0.18:
        app, contact, _ = random.choice(CHAT_CONTACTS)
        state["conversation_contact"] = (app, contact)
        state["conversation_left"] = random.randint(2, 5)


def generate_message_notification(state: dict) -> dict:
    maybe_start_conversation(state)
    if state["conversation_left"] > 0 and state["conversation_contact"]:
        app, contact = state["conversation_contact"]
        pool = next(c[2] for c in CHAT_CONTACTS if c[0] == app and c[1] == contact)
        state["conversation_left"] -= 1
    else:
        app, contact, pool = random.choice(CHAT_CONTACTS)

    content = random.choice(pool)
    important = random.random() < 0.28
    categories = ["messages"]
    if important:
        categories.append("important")
    return {
        "app": app,
        "title": contact,
        "content": content,
        "important": important,
        "ignored": False,
        "categories": categories,
    }


def generate_system_notification(state: dict) -> dict:
    mode = random.random()
    if mode < 0.45:
        title = "物流消息"
        content = LOGISTICS_TRACK[state["logistics_index"]]
        state["logistics_index"] = (state["logistics_index"] + 1) % len(LOGISTICS_TRACK)
        app = random.choice(["淘宝", "京东", "菜鸟"])
        important = "派送" in content or "签收" in content
    elif mode < 0.7:
        app = "日历"
        title = random.choice(["会议提醒", "日程提醒"])
        mins = random.choice([5, 10, 15, 30])
        content = f"你有一个会议将在 {mins} 分钟后开始"
        important = mins <= 10
    else:
        app = "系统"
        title = random.choice(["电量提示", "安全提醒", "更新提示"])
        if title == "电量提示":
            state["battery_level"] = max(8, state["battery_level"] - random.randint(1, 5))
            content = f"当前电量 {state["battery_level"]}% ，建议连接电源"
        elif title == "安全提醒":
            content = random.choice(["发现新设备登录，请确认是否本人", "账号异地登录已被拦截"])
        else:
            content = random.choice(["今晚 02:00 安装系统补丁", "后台组件已更新，重启后生效"])
        important = title != "更新提示"

    ignored = random.random() < 0.1 and not important
    categories = ["system"]
    if important:
        categories.append("important")
    if ignored:
        categories.append("ignored")
    return {
        "app": app,
        "title": title,
        "content": content,
        "important": important,
        "ignored": ignored,
        "categories": categories,
    }


def generate_code_notification() -> dict:
    code = random_code()
    return {
        "app": random.choice(["短信", "支付宝", "银行通知"]),
        "title": random.choice(["登录验证", "支付验证", "设备验证"]),
        "content": f"验证码 {code}，5 分钟内有效。若非本人操作请忽略。",
        "code": code,
        "important": True,
        "ignored": False,
        "categories": ["codes", "important"],
    }


def generate_notification(state: dict) -> dict:
    w_msg, w_sys, _ = hour_weights()
    t = random.random()
    if t < w_msg:
        base = generate_message_notification(state)
    elif t < (w_msg + w_sys):
        base = generate_system_notification(state)
    else:
        base = generate_code_notification()

    now = datetime.now().strftime("%H:%M")
    payload = dict(base)
    payload["id"] = str(uuid.uuid4())
    payload["time"] = now
    payload["unread"] = random.random() < 0.9
    return payload


async def push_loop(websocket, state: dict):
    while True:
        burst = 1
        if random.random() < 0.16:
            burst = random.randint(2, 4)

        for _ in range(burst):
            payload = generate_notification(state)
            try:
                await websocket.send(json.dumps(payload, ensure_ascii=False))
                logger.debug(
                    "推送 %s · %s | %s (%s)",
                    payload["app"], payload["title"], payload["content"], payload["time"],
                )
            except websockets.ConnectionClosed:
                return
            await asyncio.sleep(random.uniform(0.08, 0.35))

        await asyncio.sleep(random.uniform(INTERVAL_MIN_SECONDS, INTERVAL_MAX_SECONDS))


async def handler(websocket):
    # 每个客户端独立的会话状态
    state = {
        "conversation_left": 0,
        "conversation_contact": None,
        "logistics_index": 0,
        "battery_level": 66,
    }
    logger.info("客户端已连接，开始推送通知")
    try:
        await push_loop(websocket, state)
    except websockets.ConnectionClosed:
        logger.info("客户端断开连接")


async def main():
    stop = asyncio.Event()

    def _shutdown():
        logger.info("收到终止信号，准备关闭服务...")
        stop.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _shutdown)
        except NotImplementedError:
            # Windows 不支持 add_signal_handler，使用 signal.signal 回退
            signal.signal(sig, lambda s, f: _shutdown())

    logger.info("WebSocket 服务启动: ws://%s:%d%s", HOST, PORT, PATH)
    async with websockets.serve(
        handler, HOST, PORT, ping_interval=20, ping_timeout=10,
    ):
        await stop.wait()

    logger.info("服务已关闭")


if __name__ == "__main__":
    asyncio.run(main())
