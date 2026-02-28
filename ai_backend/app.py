from __future__ import annotations

import os
import re
from datetime import datetime
from zoneinfo import ZoneInfo

import requests
from flask import Flask, jsonify, request

app = Flask(__name__)


def env_trim(key: str, default: str = "") -> str:
    return os.getenv(key, default).strip()


def current_cn_datetime_text() -> str:
    tz_name = env_trim("APP_TIMEZONE", "Asia/Shanghai")
    try:
        tz = ZoneInfo(tz_name)
    except Exception:
        tz = ZoneInfo("Asia/Shanghai")
    return datetime.now(tz).strftime("%Y-%m-%d %H:%M")


def first_non_empty(values: list[str | None]) -> str:
    for value in values:
        if value is None:
            continue
        trimmed = value.strip()
        if trimmed:
            return trimmed
    return ""


def normalize_plain_text(raw: str) -> str:
    text = raw.strip()
    if text.startswith("```"):
        text = text.replace("```text", "").replace("```", "").strip()

    text = re.sub(r"(?is)<think\b[^>]*>.*?</think>", "", text).strip()
    if "<think" in text.lower():
        text = re.split(r"(?i)<think", text)[0].strip()

    if text.startswith('"') and text.endswith('"') and len(text) >= 2:
        text = text[1:-1]

    text = re.sub(r"\s+", " ", text.replace("\n", " ")).strip()
    if len(text) <= 120:
        return text

    parts = [part.strip() for part in re.split(r"[。！？!?]", text) if part.strip()]
    if not parts:
        return text
    tail = "。".join(parts[-2:])
    return tail if tail.endswith("。") else f"{tail}。"


class BackendError(Exception):
    def __init__(self, message: str, status_code: int = 500):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def extract_text_from_provider(payload: dict) -> str:
    choices = payload.get("choices")
    if isinstance(choices, list) and choices:
        first = choices[0] if isinstance(choices[0], dict) else {}
        message = first.get("message", {}) if isinstance(first, dict) else {}
        content = message.get("content", "") if isinstance(message, dict) else ""
        if isinstance(content, str):
            return content.strip()
        if isinstance(content, list):
            chunks: list[str] = []
            for item in content:
                if isinstance(item, dict):
                    text = item.get("text")
                    if isinstance(text, str):
                        chunks.append(text)
                elif isinstance(item, str):
                    chunks.append(item)
            return "".join(chunks).strip()

    # Some providers place text in data/output style fields.
    direct_text = first_non_empty(
        [
            payload.get("content") if isinstance(payload.get("content"), str) else None,
            payload.get("reply") if isinstance(payload.get("reply"), str) else None,
            payload.get("text") if isinstance(payload.get("text"), str) else None,
            payload.get("result") if isinstance(payload.get("result"), str) else None,
            payload.get("output") if isinstance(payload.get("output"), str) else None,
        ]
    )
    return direct_text


def require_backend_token() -> tuple[bool, tuple]:
    expected = env_trim("AI_BACKEND_TOKEN")
    if not expected:
        return True, ()

    auth = request.headers.get("Authorization", "").strip()
    if auth != f"Bearer {expected}":
        return False, (jsonify({"error": "Unauthorized"}), 401)
    return True, ()


def call_minimax_chat(messages: list[dict], model: str | None, temperature: float) -> str:
    api_key = env_trim("MINIMAX_API_KEY")
    if not api_key:
        raise BackendError("MINIMAX_API_KEY is missing on backend.", 500)

    base_url = env_trim("MINIMAX_BASE_URL", "https://api.minimax.io/v1")
    endpoint = f"{base_url.rstrip('/')}/chat/completions"
    effective_model = model or env_trim("MINIMAX_MODEL", "MiniMax-M2.5")
    timeout_seconds = float(env_trim("MINIMAX_TIMEOUT_SECONDS", "60") or "60")

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    body = {
        "model": effective_model,
        "messages": messages,
        "temperature": temperature,
    }

    try:
        response = requests.post(endpoint, headers=headers, json=body, timeout=timeout_seconds)
    except requests.RequestException as exc:
        raise BackendError(f"Failed to reach Minimax: {exc}", 502) from exc

    if not (200 <= response.status_code < 300):
        raise BackendError(
            f"Minimax API error ({response.status_code}): {response.text[:800]}",
            502,
        )

    try:
        payload = response.json()
    except ValueError as exc:
        raise BackendError("Minimax returned non-JSON response.", 502) from exc

    text = extract_text_from_provider(payload)
    if not text:
        raise BackendError("Minimax returned empty content.", 502)
    return text


def build_chat_system_prompt(context: str) -> str:
    now_text = current_cn_datetime_text()
    safe_context = context.strip() or "无"
    return f"""
你是孕期健康助手。你必须以 JSON 输出，不要输出额外文字。
你的任务：从用户输入中提取结构化意图与槽位，用于记录用药/检查/提醒。
如果用户只是闲聊（如讲笑话、问候、聊天），也要返回 JSON，intent=unknown，并给出 assistant_reply。
语气风格：直爽、温和、接地气，允许轻微幽默；不冒犯、不粗俗。
当前日期/时间：{now_text}（Asia/Shanghai）。如涉及今天/明天，必须基于该时间。

输出 JSON 结构：
{{
  "intent": "create_medication|create_check_record|create_reminder|query_schedule|update_reminder_time|unknown",
  "slots": {{
    "item_name": "",
    "dosage": "",
    "frequency": "",
    "time_semantic": "",
    "time_exact": "",
    "date_semantic": "",
    "minutes_before": null,
    "duration_days": null,
    "check_type": "",
    "check_date": "",
    "hcg": null,
    "progesterone": null,
    "estradiol": null,
    "note": ""
  }},
  "need_clarify": false,
  "clarify_question": "",
  "assistant_reply": ""
}}

规则：
1) 只输出 JSON，禁止解释、禁止附加文字。
2) 如果关键信息不全，need_clarify=true，并提供简短追问。
3) 不做医学诊断与建议。
4) 若用户询问“今天/明天吃什么药、用药安排”，intent=query_schedule，date_semantic=今天/明天/后天。
5) 若用户修改作息或提醒时间（如“晚饭后改到19:30”、“提醒提前10分钟”），intent=update_reminder_time。
6) 若用户询问医疗判断/治疗建议，assistant_reply 需提示“我是健康助手，不是医生，请咨询医生”。
7) 不支持的操作（如修改既有用药、确认已服用）统一返回 intent=unknown，并在 assistant_reply 给出可执行替代建议。
8) 参考用户资料与用药计划：
{safe_context}
""".strip()


HOME_SUMMARY_SYSTEM_PROMPT = """
你是孕期健康伙伴，请把“今日情况 + 下一步提醒 + 近期复查”总结成 1-2 句中文自然句。
要求：
1) 语气亲切、直白，不用医学术语，不做诊断。
2) 必须提到今天的状态和接下来要做什么。
3) 若有近期复查要点明时间；若没有，明确说“近期暂无复查安排”。
4) 控制在 40-80 字，输出纯文本，不要 JSON/Markdown/项目符号。
5) 严禁输出任何思考过程标签或内容（例如 <think>、分析过程、步骤列表）。
""".strip()


@app.get("/healthz")
def healthz():
    return jsonify({"ok": True, "service": "pregnancy-ai-backend"})


@app.post("/api/ai/chat")
def ai_chat():
    allowed, reject = require_backend_token()
    if not allowed:
        return reject

    payload = request.get_json(silent=True) or {}
    context = str(payload.get("context", "")).strip()
    user_input = str(payload.get("userInput", "")).strip()
    model = str(payload.get("model", "")).strip() or None
    history = payload.get("history", [])

    if not user_input:
        return jsonify({"error": "userInput is required"}), 400

    safe_history: list[dict] = []
    if isinstance(history, list):
        for item in history[-40:]:
            if not isinstance(item, dict):
                continue
            role = item.get("role")
            content = item.get("content")
            if role not in ("user", "assistant"):
                continue
            if not isinstance(content, str):
                continue
            safe_history.append({"role": role, "content": content})

    messages = (
        [{"role": "system", "content": build_chat_system_prompt(context)}]
        + safe_history
        + [{"role": "user", "content": user_input}]
    )

    try:
        text = call_minimax_chat(messages=messages, model=model, temperature=0.3)
    except BackendError as err:
        return jsonify({"error": err.message}), err.status_code

    return jsonify({"content": text})


@app.post("/api/ai/home-summary")
def ai_home_summary():
    allowed, reject = require_backend_token()
    if not allowed:
        return reject

    payload = request.get_json(silent=True) or {}
    snapshot = str(payload.get("snapshot", "")).strip()
    model = str(payload.get("model", "")).strip() or None

    if not snapshot:
        return jsonify({"error": "snapshot is required"}), 400

    messages = [
        {"role": "system", "content": HOME_SUMMARY_SYSTEM_PROMPT},
        {"role": "user", "content": f"请根据以下快照生成总结：\n{snapshot}"},
    ]

    try:
        raw_text = call_minimax_chat(messages=messages, model=model, temperature=0.5)
    except BackendError as err:
        return jsonify({"error": err.message}), err.status_code

    return jsonify({"content": normalize_plain_text(raw_text)})


if __name__ == "__main__":
    port = int(env_trim("PORT", env_trim("APP_PORT", "8787")) or "8787")
    app.run(host="0.0.0.0", port=port, debug=False)
