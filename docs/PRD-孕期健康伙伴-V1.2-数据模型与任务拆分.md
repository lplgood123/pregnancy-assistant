# PRD-孕期健康伙伴 V1.2 数据模型与任务拆分

日期：2026-02-23

## 1. 数据模型（V1 本地存储）

### 1.1 用户档案 UserProfile
用于语义时间映射与个性化提醒。

字段（建议）：
- id: string
- name: string
- pregnancy_start_date: date（末次月经）
- due_date: date（预产期）
- meal_time_breakfast: time
- meal_time_lunch: time
- meal_time_dinner: time
- sleep_time: time
- height_cm: number
- weight_kg: number
- allergies: string
- doctor_name: string
- doctor_contact: string
- notes: string
- created_at: datetime
- updated_at: datetime

说明：
- pregnancy_start_date 与 due_date 只需其一；另一项可计算或补充。

### 1.2 提醒事项 ReminderItem
包含用药提醒、就医预约、健康习惯。

字段（建议）：
- id: string
- type: enum("medication", "appointment", "habit", "note")
- title: string（如“钙片”“产检预约”）
- dosage: string（可选）
- frequency: enum("once", "daily", "weekly", "custom")
- time_semantic: string（如“晚饭后”“睡前”，可空）
- time_exact: time（具体时间，优先于语义）
- time_offset_min: number（饭后 +20，睡前 -30）
- start_date: date
- end_date: date（可选）
- next_trigger_at: datetime
- status: enum("active", "paused", "done")
- confirmation_required: boolean（默认 true）
- last_confirmed_at: datetime（可选）
- last_prompted_at: datetime（追问时间）
- created_at: datetime
- updated_at: datetime

说明：
- 未确认则 30 分钟后追问一次。

### 1.3 检查记录 CheckRecord

字段（建议）：
- id: string
- check_type: string（如“妊娠三项”）
- check_date: date
- values: json（指标名/数值/单位）
- ref_ranges: json（报告单参考范围，可空）
- summary: string（可选，AI 生成摘要）
- created_at: datetime
- updated_at: datetime

规则：
- 仅使用报告单参考范围进行“正常/异常”提示。
- 无参考范围时仅展示趋势。

### 1.4 AI 对话记录 Conversation

字段（建议）：
- id: string
- user_text: string
- ai_text: string
- intent: string
- slots: json
- created_at: datetime

说明：
- 仅保存结构化结果与核心文本，避免隐私风险。

### 1.5 家属查看绑定 FamilyShare

字段（建议）：
- id: string
- user_id: string
- member_name: string
- permission: enum("read_only")
- created_at: datetime

## 2. AI 意图与结构化结果

### 2.1 意图枚举
- create_medication
- update_medication
- create_check_record
- update_check_record
- create_reminder
- confirm_intake
- query_schedule

### 2.2 标准返回结构（示例）
```json
{
  "intent": "create_medication",
  "slots": {
    "item_name": "钙片",
    "frequency": "daily",
    "time_semantic": "晚饭后",
    "time_exact": null,
    "duration_days": 30
  },
  "need_clarify": false,
  "clarify_question": null
}
```

### 2.3 澄清策略
- 若缺频率/时间：先追问补齐。
- 若用户表述冲突：要求用户确认。
- 追问失败：转表单录入。

## 3. 任务拆分（MVP）

### 3.1 需求与交互
- 确认语义时间规则与追问间隔（已定：饭后 +20，睡前 -30，追问 30 分钟）。
- 首页卡片流信息层级与文案确认。
- AI 交互文案库（提醒、追问、确认、错误）。

### 3.2 前端（React Native）
- 对话首页：卡片流 + 常驻输入框
- 今日时间线：按时间排序、可勾选完成
- 检查记录列表 + 详情对比
- 个人档案录入
- 家属只读查看页

### 3.3 本地存储与数据层
- 设计 SQLite/AsyncStorage schema
- 数据读写封装（CRUD）
- 数据迁移与版本号管理

### 3.4 提醒与通知
- 本地通知调度
- 追问逻辑（30 分钟后一次）
- “已服用/已完成”确认反馈

### 3.5 AI 解析与规则
- System Prompt 与意图解析
- 槽位校验与澄清逻辑
- 结构化结果写入本地数据库

### 3.6 QA 与验收
- 用药录入 → 提醒 → 追问 → 完成闭环
- 检查录入 → 趋势对比 → 提示
- 语义时间映射正确性

## 4. MVP 验收标准（建议）
- 语义时间映射正确（饭后 +20，睡前 -30）
- 提醒触发后 30 分钟追问一次
- 检查记录支持对比与趋势展示
- 无参考范围时不输出“正常/异常”
- 首屏卡片流可完成核心流程

## 5. 待确认
- 具体数据库方案：SQLite（建议）或 AsyncStorage
- 家属查看是否需要邀请码或二维码
- AI 对话记录是否全量保存或仅保存结构化结果
