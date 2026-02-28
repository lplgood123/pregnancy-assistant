# 孕期飞书提醒助手（本地版）

这个工具做的事：
- 你在网页里录入基本信息（称呼、末次月经、预产期）
- 录入每天几点要发什么提醒
- 系统自动调用飞书机器人，每天按时发送

## 1. 安装（只做一次）

在终端执行：

```bash
cd /Users/lpl/Desktop/codex/孕期助手/feishu_reminder
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 2. 启动

最简单（推荐）：

```bash
cd /Users/lpl/Desktop/codex/孕期助手/feishu_reminder
./start.command
```

或者手动启动：

```bash
cd /Users/lpl/Desktop/codex/孕期助手/feishu_reminder
source .venv/bin/activate
python app.py
```

看到 `Running on http://0.0.0.0:5077` 就成功了。

浏览器打开：

[http://127.0.0.1:5077](http://127.0.0.1:5077)

## 3. 页面里怎么填

1. 先填“基本信息”
2. 再填飞书机器人的 `Webhook URL`
3. 新增每日提醒（时间 + 标题 + 内容）
4. 点击“立即测试发送”确认飞书能收到

## 4. 注意事项

- 这个是本地服务：你的 Mac 需要开机并且这个程序在运行，才会按时发送。
- 如果你关掉终端，服务会停止。
- 数据保存在同目录 `data.db`。

## 5. 后续可选升级

- 做成“开机自动启动”后台服务（LaunchAgent）
- 增加“每周几发送”而不是每天都发
- 增加“用药记录回填”和飞书交互命令（例如回复“已完成”）
