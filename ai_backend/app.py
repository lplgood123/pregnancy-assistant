from __future__ import annotations

import json
import os
import re
import time
from datetime import datetime, timedelta
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


def strip_reasoning_artifacts(raw: str) -> str:
    text = raw.strip()

    # Prefer content after </think> if present.
    close_match = re.search(r"(?i)</think>", text)
    if close_match:
        tail = text[close_match.end() :].strip()
        if tail:
            text = tail

    # Remove complete think blocks and truncated starts.
    text = re.sub(r"(?is)<think\b[^>]*>.*?</think>", "", text).strip()
    if re.search(r"(?i)<think", text):
        text = re.split(r"(?i)<think", text)[0].strip()

    # Unwrap fenced code block if model returns ```json ... ```
    fenced = re.search(r"(?is)```(?:json|text)?\s*(.*?)\s*```", text)
    if fenced:
        candidate = fenced.group(1).strip()
        if candidate:
            text = candidate

    return text.strip()


def normalize_chat_json(raw: str) -> str:
    cleaned = strip_reasoning_artifacts(raw)
    candidate = cleaned

    if not (candidate.startswith("{") and candidate.endswith("}")):
        start = candidate.find("{")
        end = candidate.rfind("}")
        if start != -1 and end != -1 and end > start:
            candidate = candidate[start : end + 1].strip()

    try:
        obj = json.loads(candidate)
        if isinstance(obj, dict):
            normalized = {
                "intent": str(obj.get("intent", "unknown")),
                "slots": obj.get("slots") if isinstance(obj.get("slots"), dict) else {},
                "need_clarify": bool(obj.get("need_clarify", False)),
                "clarify_question": str(obj.get("clarify_question", "")),
                "assistant_reply": str(obj.get("assistant_reply", "")),
            }
            return json.dumps(normalized, ensure_ascii=False)
    except Exception:
        pass

    fallback = {
        "intent": "unknown",
        "slots": {},
        "need_clarify": False,
        "clarify_question": "",
        "assistant_reply": cleaned or "我在呢，你可以告诉我要记录什么。",
    }
    return json.dumps(fallback, ensure_ascii=False)


MEDICAL_DISCLAIMER = "以上为孕期健康参考，若症状加重或持续，请及时联系医生/专业人士。"


def extract_json_dict(raw: str) -> dict | None:
    cleaned = strip_reasoning_artifacts(raw)
    candidate = cleaned
    if not (candidate.startswith("{") and candidate.endswith("}")):
        start = candidate.find("{")
        end = candidate.rfind("}")
        if start != -1 and end != -1 and end > start:
            candidate = candidate[start : end + 1].strip()
    try:
        obj = json.loads(candidate)
        if isinstance(obj, dict):
            return obj
    except Exception:
        return None
    return None


def parse_loose_float(raw: object) -> float | None:
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        value = float(raw)
        return value if value == value else None
    text = str(raw).strip()
    if not text:
        return None
    text = text.replace(",", "")
    try:
        return float(text)
    except Exception:
        pass
    match = re.search(r"([-+]?\d+(?:\.\d+)?)", text)
    if not match:
        return None
    try:
        return float(match.group(1))
    except Exception:
        return None


def parse_flexible_date_text(raw: object, now: datetime | None = None) -> str:
    text = str(raw or "").strip()
    if not text:
        return ""

    if now is None:
        now = datetime.now(ZoneInfo(env_trim("APP_TIMEZONE", "Asia/Shanghai") or "Asia/Shanghai"))

    if "后天" in text:
        return (now + timedelta(days=2)).strftime("%Y-%m-%d")
    if "明天" in text or "明日" in text:
        return (now + timedelta(days=1)).strftime("%Y-%m-%d")
    if "今天" in text or "今日" in text:
        return now.strftime("%Y-%m-%d")

    date_match = re.search(r"(?:(20\d{2})\s*[年/\-.])?\s*(\d{1,2})\s*[月/\-.]\s*(\d{1,2})\s*日?", text)
    if date_match:
        year_text, month_text, day_text = date_match.groups()
        year = int(year_text) if year_text else now.year
        month = int(month_text)
        day = int(day_text)
        try:
            return datetime(year, month, day).strftime("%Y-%m-%d")
        except Exception:
            return ""

    iso_match = re.search(r"(20\d{2})-(\d{1,2})-(\d{1,2})", text)
    if iso_match:
        y, m, d = iso_match.groups()
        try:
            return datetime(int(y), int(m), int(d)).strftime("%Y-%m-%d")
        except Exception:
            return ""
    return ""


def is_medical_query(user_input: str) -> bool:
    lowered = user_input.lower()
    keywords = [
        "孕", "宫缩", "出血", "流血", "腹痛", "疼", "呕吐", "发热", "发烧", "头痛",
        "头晕", "胎动", "破水", "血压", "心率", "恶心", "药", "用药", "注射",
        "反应", "症状", "hcg", "孕酮", "雌二醇", "产检", "复诊", "检查",
    ]
    return any(word in lowered for word in keywords)


def has_red_flag_symptom(user_input: str) -> bool:
    lowered = user_input.lower()
    red_flags = [
        "大量出血",
        "持续出血",
        "剧痛",
        "持续腹痛",
        "晕厥",
        "昏厥",
        "高热",
        "39",
        "无法进食",
        "呼吸困难",
        "胸痛",
        "胎动明显减少",
        "破水",
    ]
    return any(flag in lowered for flag in red_flags)


def ensure_medical_disclaimer(text: str) -> str:
    trimmed = text.strip()
    if not trimmed:
        return MEDICAL_DISCLAIMER
    if MEDICAL_DISCLAIMER in trimmed:
        return trimmed
    if trimmed.endswith(("。", "！", "？", "!", "?")):
        return f"{trimmed}{MEDICAL_DISCLAIMER}"
    return f"{trimmed}。{MEDICAL_DISCLAIMER}"


def enforce_medical_reply_policy(raw_json: str, user_input: str) -> str:
    obj = extract_json_dict(raw_json)
    if not obj:
        return raw_json

    intent = str(obj.get("intent", "unknown"))
    assistant_reply = str(obj.get("assistant_reply", "") or "").strip()

    if not is_medical_query(user_input):
        return json.dumps(
            {
                "intent": intent,
                "slots": obj.get("slots") if isinstance(obj.get("slots"), dict) else {},
                "need_clarify": bool(obj.get("need_clarify", False)),
                "clarify_question": str(obj.get("clarify_question", "")),
                "assistant_reply": assistant_reply,
            },
            ensure_ascii=False,
        )

    if intent == "unknown":
        if not assistant_reply:
            assistant_reply = "你这个情况我先给你一般建议：先休息、补水，继续观察症状变化。"
        if has_red_flag_symptom(user_input):
            urgent = "你提到的症状有潜在风险，建议尽快线下就医或联系产科。"
            if urgent not in assistant_reply:
                assistant_reply = f"{urgent}{assistant_reply}"
        assistant_reply = ensure_medical_disclaimer(assistant_reply)

    normalized = {
        "intent": intent,
        "slots": obj.get("slots") if isinstance(obj.get("slots"), dict) else {},
        "need_clarify": bool(obj.get("need_clarify", False)),
        "clarify_question": str(obj.get("clarify_question", "")),
        "assistant_reply": assistant_reply,
    }
    return json.dumps(normalized, ensure_ascii=False)


class BackendError(Exception):
    def __init__(self, message: str, status_code: int = 500):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def env_float(key: str, default: float) -> float:
    raw = env_trim(key, str(default))
    try:
        return float(raw)
    except ValueError:
        return default


def env_int(key: str, default: int) -> int:
    raw = env_trim(key, str(default))
    try:
        return int(raw)
    except ValueError:
        return default


def minimax_status_retryable(status_code: int) -> bool:
    return status_code in {429, 500, 502, 503, 504}


def minimax_exception_retryable(exc: Exception) -> bool:
    return isinstance(exc, (requests.Timeout, requests.ConnectionError))


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
    connect_timeout_seconds = env_float("MINIMAX_CONNECT_TIMEOUT_SECONDS", 8.0)
    read_timeout_seconds = env_float("MINIMAX_READ_TIMEOUT_SECONDS", 35.0)
    # Backward compatibility: if only legacy total timeout exists, cap read timeout by it.
    legacy_total_timeout = env_float("MINIMAX_TIMEOUT_SECONDS", 60.0)
    read_timeout_seconds = min(read_timeout_seconds, max(10.0, legacy_total_timeout))
    max_attempts = max(1, env_int("MINIMAX_MAX_ATTEMPTS", 2))
    retry_backoff_seconds = max(0.0, env_float("MINIMAX_RETRY_BACKOFF_SECONDS", 0.8))

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}",
    }
    body = {
        "model": effective_model,
        "messages": messages,
        "temperature": temperature,
    }

    last_error: BackendError | None = None

    for attempt in range(1, max_attempts + 1):
        started_at = time.monotonic()
        try:
            response = requests.post(
                endpoint,
                headers=headers,
                json=body,
                timeout=(connect_timeout_seconds, read_timeout_seconds),
            )
        except requests.RequestException as exc:
            elapsed = int((time.monotonic() - started_at) * 1000)
            print(
                f"[minimax] attempt={attempt}/{max_attempts} exception={type(exc).__name__} "
                f"elapsedMs={elapsed}"
            )
            if attempt < max_attempts and minimax_exception_retryable(exc):
                if retry_backoff_seconds > 0:
                    time.sleep(retry_backoff_seconds * attempt)
                continue
            status_code = 504 if isinstance(exc, requests.Timeout) else 502
            reason = "timeout" if isinstance(exc, requests.Timeout) else "connection_error"
            raise BackendError(f"Failed to reach Minimax ({reason}): {exc}", status_code) from exc

        elapsed = int((time.monotonic() - started_at) * 1000)
        print(
            f"[minimax] attempt={attempt}/{max_attempts} status={response.status_code} elapsedMs={elapsed}"
        )

        if not (200 <= response.status_code < 300):
            if response.status_code == 401:
                raise BackendError(
                    "Minimax API key is invalid. Please update MINIMAX_API_KEY on backend.",
                    401,
                )
            if attempt < max_attempts and minimax_status_retryable(response.status_code):
                if retry_backoff_seconds > 0:
                    time.sleep(retry_backoff_seconds * attempt)
                continue
            raise BackendError(
                f"Minimax API error ({response.status_code}): {response.text[:800]}",
                502,
            )

        try:
            payload = response.json()
        except ValueError as exc:
            last_error = BackendError("Minimax returned non-JSON response.", 502)
            if attempt < max_attempts:
                if retry_backoff_seconds > 0:
                    time.sleep(retry_backoff_seconds * attempt)
                continue
            raise last_error from exc

        text = extract_text_from_provider(payload)
        if text:
            return text

        last_error = BackendError("Minimax returned empty content.", 502)
        if attempt < max_attempts:
            if retry_backoff_seconds > 0:
                time.sleep(retry_backoff_seconds * attempt)
            continue
        raise last_error

    raise last_error or BackendError("Minimax call failed.", 502)


def build_chat_system_prompt(context: str) -> str:
    now_text = current_cn_datetime_text()
    safe_context = context.strip() or "无"
    return f"""
你是孕期健康助手。你必须以 JSON 输出，不要输出额外文字。
你的任务：从用户输入中提取结构化意图与槽位，用于记录用药/检查报告/预约/提醒。
如果用户只是闲聊（如讲笑话、问候、聊天），也要返回 JSON，intent=unknown，并给出 assistant_reply。
语气风格：温柔、共情、清晰、可执行，像贴心陪伴者；不冷漠、不说教。
当前日期/时间：{now_text}（Asia/Shanghai）。如涉及今天/明天，必须基于该时间。

输出 JSON 结构：
{{
  "intent": "create_medication|create_check_record|create_appointment|create_reminder|update_profile|query_schedule|update_reminder_time|unknown",
  "slots": {{
    "item_name": "",
    "dosage": "",
    "frequency": "",
    "time_semantic": "",
    "time_exact": "",
    "date_semantic": "",
    "minutes_before": null,
    "duration_days": null,
    "height_cm": null,
    "weight_kg": null,
    "check_type": "",
    "check_date": "",
    "hcg": null,
    "progesterone": null,
    "estradiol": null,
    "note": "",
    "medications": [
      {{
        "item_name": "",
        "dosage": "",
        "time_semantic": "",
        "note": ""
      }}
    ]
  }},
  "need_clarify": false,
  "clarify_question": "",
  "assistant_reply": ""
}}

规则：
1) 只输出 JSON，禁止解释、禁止附加文字。
2) 如果关键信息不全，need_clarify=true，并提供简短追问。
3) 不做医学诊断与处方；但可给孕期常见情况的一般性分级建议（居家观察/生活调整/何时就医阈值），先安抚再给建议。
4) 若用户询问“今天/明天吃什么药、用药安排”，intent=query_schedule，date_semantic=今天/明天/后天。
5) 若用户表达“复诊/回诊/产检/就诊/挂号/去医院”等就医计划，应优先 intent=create_appointment，而不是 create_check_record；
   可复用 slots.item_name/check_date/time_exact/note（例如 item_name=产检复诊，check_date=下周五，time_exact=09:00）。
6) 若用户修改作息或提醒时间（如“晚饭后改到19:30”、“提醒提前10分钟”），intent=update_reminder_time。
7) 若用户要求记录或更新身高/体重（如“身高165体重52.3”、“帮我记体重53公斤”），intent=update_profile；
   能提取就直接填 slots.height_cm / slots.weight_kg（仅数字，不带单位），不追问。
   同一句里有身高和体重时，两个字段都要填，不允许只填一个。
8) 若用户询问孕反或不适症状，可给可执行建议；若涉及红旗症状（大量出血、持续剧痛、晕厥、高热不退等），assistant_reply 必须优先建议尽快就医。
9) 医疗相关 assistant_reply 结尾必须加：以上为孕期健康参考，若症状加重或持续，请及时联系医生/专业人士。
10) 不支持的操作（如修改既有用药、确认已服用）统一返回 intent=unknown，并在 assistant_reply 给出可执行替代建议。
11) 如果用户一次输入多条用药（例如按“起床后/早饭后/晚饭后/睡前”列出多个药），intent=create_medication，
   slots.medications 必须返回完整数组，每个元素填写 item_name/dosage/time_semantic/note；
   不要只填第一项。单条用药时可仅填 item_name/dosage/time_semantic。
12) 对提醒类意图（create_reminder / update_reminder_time）：
   只要能识别到 time_semantic（如“起床后/早饭后/午饭后/晚饭后/睡前”）就可以执行，
   不要因为没有具体时钟时间就追问。用户说“和早餐后吃药一起提醒”时，time_semantic=早饭后，need_clarify=false。
13) 参考用户资料与用药计划：
{safe_context}
""".strip()


HOME_SUMMARY_SYSTEM_PROMPT = """
你是孕期健康伙伴，请把“今日情况 + 下一步提醒 + 近期复查”总结成 1-2 句中文自然句。
要求：
1) 语气温柔、鼓励、好理解，不用冰冷术语，不做诊断。
2) 必须提到今天的状态和接下来要做什么。
3) 若有近期复查要点明时间；若没有，明确说“近期暂无复查安排”。
4) 控制在 40-80 字，输出纯文本，不要 JSON/Markdown/项目符号。
5) 严禁输出任何思考过程标签或内容（例如 <think>、分析过程、步骤列表）。
""".strip()


DAILY_GUIDE_SYSTEM_PROMPT = """
你是孕期健康内容助手。请根据用户给定日期和孕周信息，输出当天的简短指南内容。
仅输出 JSON：
{
  "week_guide": "",
  "baby_change": "",
  "mom_change": ""
}
要求：
1) 语气温暖、陪伴感强、可执行。
2) 每个字段 20-80 字。
3) 不要输出 Markdown、不要额外解释。
4) 不要给处方或诊断。
""".strip()


PANEL_GROUP_SYSTEM_PROMPT = """
你是医学报告结构化助手。任务是从多张 OCR 文本中提取“妊娠三项”记录，并智能判断是一次检查还是多次检查。
仅输出 JSON：
{
  "records": [
    {
      "check_type": "pregnancy_panel",
      "check_date": "YYYY-MM-DD",
      "hcg": 0,
      "progesterone": 0,
      "estradiol": 0,
      "note": "",
      "source_indexes": [0]
    }
  ],
  "failed_indexes": []
}
规则：
1) 如果多张图片属于同一次检查（同日且指标互补/重复），应合并为一条记录。
2) 如果明显是不同日期或不同检查，应拆分为多条记录。
3) source_indexes 使用 0-based 索引，表示该记录来自哪些 OCR 文本。
4) 没法提取完整三项的图片索引写入 failed_indexes。
5) 只输出 JSON。
""".strip()


INGREDIENT_ANALYZE_SYSTEM_PROMPT = f"""
你是孕期成分识别助手。根据 OCR 文本判断成分对孕期使用的风险等级。
仅输出 JSON：
{{
  "overall": "可用|谨慎|避免",
  "usable": [{{"name": "", "reason": ""}}],
  "caution": [{{"name": "", "reason": ""}}],
  "avoid": [{{"name": "", "reason": ""}}],
  "summary": "",
  "alternatives": [""]
}}
规则：
1) 使用“三档结论”：可用/谨慎/避免。
2) 每条 reason 简短明确，优先给孕期关注点，语气温和。
3) 可给 1-3 条替代建议到 alternatives。
4) 不输出任何 Markdown 或额外文本。
5) 不做诊断与处方。
6) 响应仅 JSON，免责声明由系统追加：{MEDICAL_DISCLAIMER}
""".strip()


def normalize_daily_guide_payload(raw_text: str, date_text: str) -> dict:
    obj = extract_json_dict(raw_text) or {}
    week_guide = first_non_empty(
        [
            str(obj.get("week_guide", "")),
            str(obj.get("weekGuide", "")),
            str(obj.get("guide", "")),
        ]
    )
    baby_change = first_non_empty(
        [
            str(obj.get("baby_change", "")),
            str(obj.get("babyChange", "")),
            str(obj.get("fetus_change", "")),
        ]
    )
    mom_change = first_non_empty(
        [
            str(obj.get("mom_change", "")),
            str(obj.get("momChange", "")),
            str(obj.get("mother_change", "")),
        ]
    )

    if not week_guide:
        week_guide = "今天保持规律作息和均衡饮食，按计划完成用药与休息。"
    if not baby_change:
        baby_change = "宝宝在按节奏发育，稳定作息和营养摄入有助于整体状态。"
    if not mom_change:
        mom_change = "妈妈今天重点是补水、规律进食和避免过度劳累。"

    return {
        "date_key": date_text,
        "week_guide": week_guide,
        "baby_change": baby_change,
        "mom_change": mom_change,
        "source": "ai",
    }


def extract_panel_record_from_text(text: str, source_index: int, now: datetime) -> dict | None:
    hcg_match = re.search(r"(?i)(?:β-?hcg|hcg)[^0-9]{0,20}([-+]?\d+(?:\.\d+)?)", text)
    p_match = re.search(r"(?i)(?:孕酮|progesterone|\bp\b)[^0-9]{0,20}([-+]?\d+(?:\.\d+)?)", text)
    e2_match = re.search(r"(?i)(?:雌二醇|estradiol|\be2\b)[^0-9]{0,20}([-+]?\d+(?:\.\d+)?)", text)
    if not hcg_match or not p_match or not e2_match:
        return None

    hcg = parse_loose_float(hcg_match.group(1))
    progesterone = parse_loose_float(p_match.group(1))
    estradiol = parse_loose_float(e2_match.group(1))
    if hcg is None or progesterone is None or estradiol is None:
        return None

    date_match = re.search(r"(20\d{2}\s*[年/\-.]\s*\d{1,2}\s*[月/\-.]\s*\d{1,2}\s*日?)", text)
    if not date_match:
        date_match = re.search(r"(\d{1,2}\s*[月/\-.]\s*\d{1,2}\s*日?)", text)
    check_date = parse_flexible_date_text(date_match.group(1) if date_match else "", now=now)

    return {
        "check_type": "pregnancy_panel",
        "check_date": check_date,
        "hcg": hcg,
        "progesterone": progesterone,
        "estradiol": estradiol,
        "note": "",
        "source_indexes": [source_index],
    }


def normalize_panel_group_payload(raw_text: str, ocr_texts: list[str], now: datetime) -> dict:
    parsed = extract_json_dict(raw_text) or {}
    records_raw = parsed.get("records") if isinstance(parsed.get("records"), list) else []
    failed_indexes_raw = parsed.get("failed_indexes") if isinstance(parsed.get("failed_indexes"), list) else []

    normalized_records: list[dict] = []
    used_indexes: set[int] = set()
    explicit_failed: set[int] = set()

    for index in failed_indexes_raw:
        try:
            idx = int(index)
        except Exception:
            continue
        if 0 <= idx < len(ocr_texts):
            explicit_failed.add(idx)

    for item in records_raw:
        if not isinstance(item, dict):
            continue
        hcg = parse_loose_float(item.get("hcg"))
        progesterone = parse_loose_float(item.get("progesterone"))
        estradiol = parse_loose_float(item.get("estradiol"))
        if hcg is None or progesterone is None or estradiol is None:
            continue

        source_indexes: list[int] = []
        raw_sources = item.get("source_indexes")
        if isinstance(raw_sources, list):
            for raw_idx in raw_sources:
                try:
                    idx = int(raw_idx)
                except Exception:
                    continue
                if 0 <= idx < len(ocr_texts):
                    source_indexes.append(idx)
        else:
            single_idx = item.get("source_index")
            if single_idx is not None:
                try:
                    idx = int(single_idx)
                    if 0 <= idx < len(ocr_texts):
                        source_indexes.append(idx)
                except Exception:
                    pass

        source_indexes = sorted(set(source_indexes))
        used_indexes.update(source_indexes)
        note = str(item.get("note", "") or "").strip()
        check_date = parse_flexible_date_text(item.get("check_date"), now=now)
        normalized_records.append(
            {
                "check_type": "pregnancy_panel",
                "check_date": check_date,
                "hcg": hcg,
                "progesterone": progesterone,
                "estradiol": estradiol,
                "note": note,
                "source_indexes": source_indexes,
            }
        )

    if not normalized_records:
        for idx, text in enumerate(ocr_texts):
            fallback = extract_panel_record_from_text(text, idx, now=now)
            if fallback:
                normalized_records.append(fallback)
                used_indexes.add(idx)

    failed_indexes = set(explicit_failed)
    for idx in range(len(ocr_texts)):
        if idx not in used_indexes:
            failed_indexes.add(idx)

    return {
        "records": normalized_records,
        "failed_indexes": sorted(failed_indexes),
    }


def parse_ingredient_items(raw_items: object) -> list[dict]:
    if not isinstance(raw_items, list):
        return []
    parsed: list[dict] = []
    for item in raw_items:
        if isinstance(item, dict):
            name = str(item.get("name", "") or "").strip()
            reason = str(item.get("reason", "") or "").strip()
            if name or reason:
                parsed.append({"name": name or "未命名成分", "reason": reason})
        elif isinstance(item, str):
            trimmed = item.strip()
            if trimmed:
                parsed.append({"name": trimmed, "reason": ""})
    return parsed


def normalize_ingredient_payload(raw_text: str) -> dict:
    obj = extract_json_dict(raw_text) or {}
    usable = parse_ingredient_items(obj.get("usable"))
    caution = parse_ingredient_items(obj.get("caution"))
    avoid = parse_ingredient_items(obj.get("avoid"))

    overall = str(obj.get("overall", "") or "").strip()
    if overall not in {"可用", "谨慎", "避免"}:
        if avoid:
            overall = "避免"
        elif caution:
            overall = "谨慎"
        else:
            overall = "可用"

    summary = str(obj.get("summary", "") or "").strip()
    if not summary:
        if overall == "避免":
            summary = "检测到对孕期风险较高的成分，建议暂不使用。"
        elif overall == "谨慎":
            summary = "存在需谨慎评估的成分，建议减少频次并关注反应。"
        else:
            summary = "暂未发现明显高风险成分，可按需使用并观察反应。"

    alternatives_raw = obj.get("alternatives")
    alternatives: list[str] = []
    if isinstance(alternatives_raw, list):
        for item in alternatives_raw:
            text = str(item or "").strip()
            if text:
                alternatives.append(text)

    return {
        "overall": overall,
        "usable": usable,
        "caution": caution,
        "avoid": avoid,
        "summary": summary,
        "alternatives": alternatives,
        "disclaimer": MEDICAL_DISCLAIMER,
    }


@app.get("/healthz")
def healthz():
    return jsonify({"ok": True, "service": "pregnancy-ai-backend"})


@app.get("/")
def root():
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

    normalized = normalize_chat_json(text)
    normalized = enforce_medical_reply_policy(normalized, user_input)
    return jsonify({"content": normalized})


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


@app.post("/api/ai/guide/daily")
def ai_daily_guide():
    allowed, reject = require_backend_token()
    if not allowed:
        return reject

    payload = request.get_json(silent=True) or {}
    date_text = str(payload.get("date", "")).strip() or datetime.now().strftime("%Y-%m-%d")
    gestational_text = str(payload.get("gestational_text", "")).strip()
    profile_context = str(payload.get("profile_context", "")).strip()
    model = str(payload.get("model", "")).strip() or None

    user_message = (
        f"日期：{date_text}\n"
        f"孕周信息：{gestational_text or '未知'}\n"
        f"用户资料：{profile_context or '无'}\n"
        "请输出当天指南 JSON。"
    )

    messages = [
        {"role": "system", "content": DAILY_GUIDE_SYSTEM_PROMPT},
        {"role": "user", "content": user_message},
    ]

    try:
        raw_text = call_minimax_chat(messages=messages, model=model, temperature=0.4)
    except BackendError as err:
        return jsonify({"error": err.message}), err.status_code

    result = normalize_daily_guide_payload(raw_text, date_text=date_text)
    return jsonify(result)


@app.post("/api/ai/report/pregnancy-panel/group")
def ai_group_pregnancy_panel_report():
    allowed, reject = require_backend_token()
    if not allowed:
        return reject

    payload = request.get_json(silent=True) or {}
    ocr_texts = payload.get("ocr_texts")
    model = str(payload.get("model", "")).strip() or None
    now_text = str(payload.get("now", "")).strip()

    if not isinstance(ocr_texts, list) or not ocr_texts:
        return jsonify({"error": "ocr_texts is required"}), 400

    safe_ocr_texts: list[str] = []
    for item in ocr_texts:
        if isinstance(item, str):
            safe_ocr_texts.append(item.strip())
        else:
            safe_ocr_texts.append(str(item))

    try:
        if now_text:
            now = datetime.fromisoformat(now_text.replace("Z", "+00:00"))
        else:
            now = datetime.now(ZoneInfo(env_trim("APP_TIMEZONE", "Asia/Shanghai") or "Asia/Shanghai"))
    except Exception:
        now = datetime.now(ZoneInfo(env_trim("APP_TIMEZONE", "Asia/Shanghai") or "Asia/Shanghai"))

    ocr_payload = "\n\n".join(
        [f"=== OCR[{idx}] ===\n{text}" for idx, text in enumerate(safe_ocr_texts)]
    )
    user_message = (
        "请对以下 OCR 文本做妊娠三项分组提取：\n"
        f"{ocr_payload}\n"
        f"当前时间：{now.strftime('%Y-%m-%d %H:%M')}"
    )
    messages = [
        {"role": "system", "content": PANEL_GROUP_SYSTEM_PROMPT},
        {"role": "user", "content": user_message},
    ]

    try:
        raw_text = call_minimax_chat(messages=messages, model=model, temperature=0.2)
        normalized = normalize_panel_group_payload(raw_text, safe_ocr_texts, now=now)
    except BackendError as err:
        return jsonify({"error": err.message}), err.status_code

    return jsonify(normalized)


@app.post("/api/ai/ingredient/analyze")
def ai_ingredient_analyze():
    allowed, reject = require_backend_token()
    if not allowed:
        return reject

    payload = request.get_json(silent=True) or {}
    ocr_texts = payload.get("ocr_texts")
    profile_context = str(payload.get("profile_context", "")).strip()
    model = str(payload.get("model", "")).strip() or None

    if not isinstance(ocr_texts, list) or not ocr_texts:
        return jsonify({"error": "ocr_texts is required"}), 400

    safe_ocr_texts = [str(item or "").strip() for item in ocr_texts]
    user_message = (
        f"用户资料：{profile_context or '无'}\n"
        "以下是商品/食品成分 OCR：\n"
        + "\n\n".join([f"=== OCR[{idx}] ===\n{text}" for idx, text in enumerate(safe_ocr_texts)])
        + "\n请输出三档风险结论 JSON。"
    )
    messages = [
        {"role": "system", "content": INGREDIENT_ANALYZE_SYSTEM_PROMPT},
        {"role": "user", "content": user_message},
    ]

    try:
        raw_text = call_minimax_chat(messages=messages, model=model, temperature=0.2)
    except BackendError as err:
        return jsonify({"error": err.message}), err.status_code

    return jsonify(normalize_ingredient_payload(raw_text))


if __name__ == "__main__":
    port = int(env_trim("PORT", env_trim("APP_PORT", "8787")) or "8787")
    app.run(host="0.0.0.0", port=port, debug=False)
