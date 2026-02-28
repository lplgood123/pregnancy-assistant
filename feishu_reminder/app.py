import os
import sqlite3
import threading
import time
from datetime import date, datetime
from zoneinfo import ZoneInfo
from urllib import request

from flask import Flask, redirect, render_template, request as flask_request, url_for

APP_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(APP_DIR, "data.db")

app = Flask(__name__)


def db_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = db_conn()
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS profile (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            mother_name TEXT,
            last_period_date TEXT,
            due_date TEXT,
            timezone TEXT DEFAULT 'Asia/Shanghai'
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS app_config (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            webhook_url TEXT
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS reminders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            send_time TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1
        )
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS send_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            reminder_id INTEGER NOT NULL,
            sent_date TEXT NOT NULL,
            UNIQUE(reminder_id, sent_date)
        )
        """
    )
    cur.execute("INSERT OR IGNORE INTO profile (id, timezone) VALUES (1, 'Asia/Shanghai')")
    cur.execute("INSERT OR IGNORE INTO app_config (id, webhook_url) VALUES (1, '')")
    conn.commit()
    conn.close()


def parse_date(text):
    if not text:
        return None
    try:
        return datetime.strptime(text, "%Y-%m-%d").date()
    except ValueError:
        return None


def pregnancy_info(profile_row):
    today = date.today()
    due = parse_date(profile_row["due_date"]) if profile_row else None
    lmp = parse_date(profile_row["last_period_date"]) if profile_row else None

    if not lmp and due:
        lmp = due.fromordinal(due.toordinal() - 280)

    if not lmp:
        return "未录入孕期日期信息"

    days = max((today - lmp).days, 0)
    week = min(days // 7 + 1, 42)
    day = days % 7

    if due:
        remain = (due - today).days
        if remain >= 0:
            due_text = f"距离预产期 {remain} 天（预产期 {due.isoformat()}）"
        else:
            due_text = f"已过预产期 {-remain} 天（预产期 {due.isoformat()}）"
    else:
        due_text = "未录入预产期"

    return f"当前孕周：{week}周+{day}天；{due_text}"


def get_profile_and_config():
    conn = db_conn()
    profile = conn.execute("SELECT * FROM profile WHERE id = 1").fetchone()
    config = conn.execute("SELECT * FROM app_config WHERE id = 1").fetchone()
    reminders = conn.execute("SELECT * FROM reminders ORDER BY send_time, id").fetchall()
    conn.close()
    return profile, config, reminders


def send_feishu_text(webhook_url, text):
    payload = ('{"msg_type":"text","content":{"text":' + '"' + text.replace('"', '\\"') + '"}}').encode(
        "utf-8"
    )
    req = request.Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with request.urlopen(req, timeout=10) as resp:
        return resp.read().decode("utf-8")


def build_message(profile, reminder):
    name = profile["mother_name"] or "家人"
    info = pregnancy_info(profile)
    lines = [
        f"【孕期提醒】{name}",
        f"事项：{reminder['title']}",
        reminder["content"],
        info,
        f"发送时间：{datetime.now().strftime('%Y-%m-%d %H:%M')}",
    ]
    return "\n".join(lines)


@app.route("/")
def home():
    profile, config, reminders = get_profile_and_config()
    msg = flask_request.args.get("msg", "")
    return render_template(
        "index.html",
        profile=profile,
        config=config,
        reminders=reminders,
        info_text=pregnancy_info(profile),
        msg=msg,
    )


@app.post("/save-profile")
def save_profile():
    mother_name = flask_request.form.get("mother_name", "").strip()
    last_period_date = flask_request.form.get("last_period_date", "").strip()
    due_date = flask_request.form.get("due_date", "").strip()
    timezone_name = flask_request.form.get("timezone", "Asia/Shanghai").strip() or "Asia/Shanghai"

    conn = db_conn()
    conn.execute(
        """
        UPDATE profile
        SET mother_name = ?, last_period_date = ?, due_date = ?, timezone = ?
        WHERE id = 1
        """,
        (mother_name, last_period_date, due_date, timezone_name),
    )
    conn.commit()
    conn.close()
    return redirect(url_for("home", msg="基本信息已保存"))


@app.post("/save-config")
def save_config():
    webhook_url = flask_request.form.get("webhook_url", "").strip()
    conn = db_conn()
    conn.execute("UPDATE app_config SET webhook_url = ? WHERE id = 1", (webhook_url,))
    conn.commit()
    conn.close()
    return redirect(url_for("home", msg="机器人配置已保存"))


@app.post("/add-reminder")
def add_reminder():
    title = flask_request.form.get("title", "").strip()
    content = flask_request.form.get("content", "").strip()
    send_time = flask_request.form.get("send_time", "09:00").strip()

    if not title or not content or len(send_time) != 5:
        return redirect(url_for("home", msg="请填写完整提醒信息"))

    conn = db_conn()
    conn.execute(
        "INSERT INTO reminders(title, content, send_time, enabled) VALUES (?, ?, ?, 1)",
        (title, content, send_time),
    )
    conn.commit()
    conn.close()
    return redirect(url_for("home", msg="提醒已添加"))


@app.post("/toggle-reminder/<int:reminder_id>")
def toggle_reminder(reminder_id):
    conn = db_conn()
    row = conn.execute("SELECT enabled FROM reminders WHERE id = ?", (reminder_id,)).fetchone()
    if row:
        conn.execute(
            "UPDATE reminders SET enabled = ? WHERE id = ?",
            (0 if row["enabled"] else 1, reminder_id),
        )
        conn.commit()
    conn.close()
    return redirect(url_for("home", msg="提醒状态已更新"))


@app.post("/delete-reminder/<int:reminder_id>")
def delete_reminder(reminder_id):
    conn = db_conn()
    conn.execute("DELETE FROM reminders WHERE id = ?", (reminder_id,))
    conn.commit()
    conn.close()
    return redirect(url_for("home", msg="提醒已删除"))


@app.post("/send-now/<int:reminder_id>")
def send_now(reminder_id):
    profile, config, _ = get_profile_and_config()
    webhook_url = (config["webhook_url"] or "").strip()
    if not webhook_url:
        return redirect(url_for("home", msg="请先配置飞书机器人 Webhook"))

    conn = db_conn()
    reminder = conn.execute("SELECT * FROM reminders WHERE id = ?", (reminder_id,)).fetchone()
    conn.close()
    if not reminder:
        return redirect(url_for("home", msg="提醒不存在"))

    text = build_message(profile, reminder)
    try:
        send_feishu_text(webhook_url, text)
        return redirect(url_for("home", msg="已发送测试消息"))
    except Exception as exc:
        return redirect(url_for("home", msg=f"发送失败: {exc}"))


def scheduler_loop():
    last_key = ""
    while True:
        try:
            profile, config, reminders = get_profile_and_config()
            webhook_url = (config["webhook_url"] or "").strip()
            timezone_name = (profile["timezone"] or "Asia/Shanghai") if profile else "Asia/Shanghai"
            now = datetime.now(ZoneInfo(timezone_name))
            minute_key = now.strftime("%Y-%m-%d %H:%M")
            if minute_key != last_key:
                last_key = minute_key
                today = now.strftime("%Y-%m-%d")
                hm = now.strftime("%H:%M")
                if webhook_url:
                    conn = db_conn()
                    for reminder in reminders:
                        if reminder["enabled"] and reminder["send_time"] == hm:
                            exists = conn.execute(
                                "SELECT 1 FROM send_logs WHERE reminder_id = ? AND sent_date = ?",
                                (reminder["id"], today),
                            ).fetchone()
                            if exists:
                                continue
                            text = build_message(profile, reminder)
                            send_feishu_text(webhook_url, text)
                            conn.execute(
                                "INSERT INTO send_logs(reminder_id, sent_date) VALUES (?, ?)",
                                (reminder["id"], today),
                            )
                            conn.commit()
                    conn.close()
        except Exception:
            pass
        time.sleep(15)


if __name__ == "__main__":
    init_db()
    t = threading.Thread(target=scheduler_loop, daemon=True)
    t.start()
    app.run(host="0.0.0.0", port=5077, debug=False)
