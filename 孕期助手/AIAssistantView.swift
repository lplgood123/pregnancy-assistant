import SwiftUI

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    var id = UUID()
    var role: Role
    var text: String
    var time: Date

    init(role: Role, text: String, time: Date) {
        self.role = role
        self.text = text
        self.time = time
    }

    init?(stored: StoredAIMessage) {
        if stored.role == "user" {
            self.role = .user
        } else if stored.role == "assistant" {
            self.role = .assistant
        } else {
            return nil
        }
        self.id = UUID(uuidString: stored.id) ?? UUID()
        if self.role == .assistant {
            self.text = assistantDisplayText(from: stored.content)
        } else {
            self.text = stored.content
        }
        self.time = stored.time
    }
}

private func assistantDisplayText(from raw: String) -> String {
    guard let action = AIParse.parse(raw) else {
        return "已收到，但解析失败，请换种说法。"
    }
    if action.needClarify {
        return action.clarifyQuestion.isEmpty ? "还需要一点信息～" : action.clarifyQuestion
    }
    if action.intent == "unknown" {
        return action.assistantReply.isEmpty ? "我在呢～" : action.assistantReply
    }
    switch action.intent {
    case "create_medication":
        let name = action.slots["item_name"] ?? "用药"
        return "已识别：新增用药（\(name)）"
    case "create_check_record":
        return "已识别：新增检查记录"
    case "create_reminder":
        let name = action.slots["item_name"] ?? "提醒"
        return "已识别：创建提醒（\(name)）"
    case "query_schedule":
        let date = action.slots["date_semantic"] ?? "今天"
        return "已识别：查询\(date)用药安排"
    case "update_reminder_time":
        return "已识别：更新提醒时间"
    default:
        return "已识别指令：\(action.intent)"
    }
}

struct AIBackendChatService {
    struct APIMessage: Codable {
        var role: String
        var content: String
    }

    struct ChatRequestBody: Codable {
        var context: String
        var history: [APIMessage]
        var userInput: String
        var model: String?
    }

    struct HomeSummaryRequestBody: Codable {
        var snapshot: String
        var model: String?
    }

    struct GenericTextResponse: Codable {
        var content: String?
        var reply: String?
        var text: String?
        var result: String?
        var output: String?
        var answer: String?
    }

    struct OpenAICompatibleResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                var content: String
            }
            var message: Message
        }
        var choices: [Choice]
    }

    func send(config: AIConfig, context: String, history: [StoredAIMessage], userInput: String) async throws -> String {
        let historyMessages: [APIMessage] = history.suffix(40).compactMap { item in
            guard item.role == "user" || item.role == "assistant" else { return nil }
            return APIMessage(role: item.role, content: item.content)
        }

        let body = ChatRequestBody(
            context: context,
            history: historyMessages,
            userInput: userInput,
            model: config.model
        )

        return try await requestText(
            config: config,
            endpoint: buildChatEndpoint(config.baseURL),
            body: body
        )
    }

    func sendHomeSummary(config: AIConfig, snapshot: String) async throws -> String {
        let body = HomeSummaryRequestBody(snapshot: snapshot, model: config.model)
        let raw = try await requestText(
            config: config,
            endpoint: buildHomeSummaryEndpoint(config.baseURL),
            body: body
        )
        let normalized = normalizePlainText(raw)
        if normalized.isEmpty {
            throw NSError(domain: "ai", code: 4, userInfo: [NSLocalizedDescriptionKey: "首页总结为空"])
        }
        return normalized
    }

    private func requestText<Body: Encodable>(config: AIConfig, endpoint: String, body: Body) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "ai", code: 1, userInfo: [NSLocalizedDescriptionKey: "AI 后端地址无效"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "请求失败"
            throw NSError(domain: "ai", code: 2, userInfo: [NSLocalizedDescriptionKey: text])
        }

        guard let output = decodeTextPayload(from: data), !output.isEmpty else {
            throw NSError(domain: "ai", code: 3, userInfo: [NSLocalizedDescriptionKey: "AI 返回为空"])
        }
        return output
    }

    private func decodeTextPayload(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(GenericTextResponse.self, from: data),
           let text = firstNonEmpty([
               decoded.content,
               decoded.reply,
               decoded.text,
               decoded.result,
               decoded.output,
               decoded.answer
           ]) {
            return text
        }

        if let openAI = try? JSONDecoder().decode(OpenAICompatibleResponse.self, from: data),
           let text = openAI.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        if
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let map = object as? [String: Any]
        {
            if let nested = map["data"] as? [String: Any] {
                let candidates = [
                    nested["content"] as? String,
                    nested["reply"] as? String,
                    nested["text"] as? String,
                    nested["result"] as? String,
                    nested["output"] as? String
                ]
                if let text = firstNonEmpty(candidates) {
                    return text
                }
            }

            if let rawDataText = map["data"] as? String,
               !rawDataText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return rawDataText
            }

            if
                map["intent"] != nil || map["slots"] != nil || map["assistant_reply"] != nil,
                let jsonData = try? JSONSerialization.data(withJSONObject: map, options: []),
                let jsonString = String(data: jsonData, encoding: .utf8)
            {
                return jsonString
            }
        }

        let plainText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (plainText?.isEmpty == false) ? plainText : nil
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func normalizePlainText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```text", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 有些推理模型会输出 <think>...</think>，这里只保留最终回答。
        if let closeRange = text.range(of: "</think>", options: [.caseInsensitive]) {
            let tail = text[closeRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                text = String(tail)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "(?is)<think\\b[^>]*>.*?</think>") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }

        if let openRange = text.range(of: "<think", options: [.caseInsensitive]) {
            text = String(text[..<openRange.lowerBound])
        }

        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }

        text = text.replacingOccurrences(of: "\n", with: " ")
        if let spaceRegex = try? NSRegularExpression(pattern: "\\s+") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = spaceRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 兜底：超长时仅保留末尾 1-2 句，避免把提示词/过程展示给用户。
        if text.count > 120 {
            let separators = CharacterSet(charactersIn: "。！？!?")
            let parts = text
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                let picked = parts.suffix(2).joined(separator: "。")
                text = picked.hasSuffix("。") ? picked : picked + "。"
            }
        }

        return text
    }

    private func buildChatEndpoint(_ input: String) -> String {
        buildEndpoint(input, path: "/api/ai/chat", suffixes: ["/api/ai/chat", "/ai/chat", "/chat"])
    }

    private func buildHomeSummaryEndpoint(_ input: String) -> String {
        buildEndpoint(
            input,
            path: "/api/ai/home-summary",
            suffixes: ["/api/ai/home-summary", "/ai/home-summary", "/home-summary", "/summary"]
        )
    }

    private func buildEndpoint(_ input: String, path: String, suffixes: [String]) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if suffixes.contains(where: { lower.hasSuffix($0) }) {
            return trimmed
        }
        if trimmed.hasSuffix("/") {
            return trimmed + String(path.dropFirst())
        }
        return trimmed + path
    }
}

struct AIAssistantView: View {
    @EnvironmentObject private var store: PregnancyStore

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var sending = false
    @State private var errorText = ""

    @State private var longTermMemory = ""

    private let chatService = AIBackendChatService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("助手设置") {
                        Text("当前通过后端统一接入 AI（建议后端使用 Minimax）；发布版可在 Info.plist 配置 AI_BACKEND_URL，调试可用 AI_BACKEND_URL / AI_BACKEND_TOKEN / AI_BACKEND_MODEL 覆盖。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("长期记忆（例如禁忌/偏好）", text: $longTermMemory, axis: .vertical)
                            .lineLimit(2...5)
                        Button("保存长期记忆") {
                            store.saveAILongTermMemory(longTermMemory.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        Button("清空对话历史") {
                            store.clearAIConversation()
                            messages = []
                        }
                    }

                    Section("提醒设置") {
                        ReminderSettingsView()
                            .environmentObject(store)
                    }

                    Section("对话") {
                        if messages.isEmpty {
                            Text("示例：\n1. 今天几点吃什么药？\n2. 我可以吃海鲜吗？\n3. 明天回诊要准备什么？")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role == .user ? "我" : "AI")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(message.text)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }

                HStack(spacing: 8) {
                    TextField("输入问题，例如：今天用药安排", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button(sending ? "发送中..." : "发送") {
                        Task { await sendMessage() }
                    }
                    .disabled(sending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("智能助手")
            .onAppear {
                longTermMemory = store.aiLongTermMemory()
                messages = store.aiConversation().compactMap { ChatMessage(stored: $0) }
            }
        }
    }

    private func sendMessage() async {
        errorText = ""
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let config = store.currentAIConfig()
        if config.baseURL.isEmpty {
            errorText = "AI 服务未配置。请在应用配置中设置 AI_BACKEND_URL（调试可用环境变量覆盖）。"
            return
        }

        inputText = ""
        sending = true
        let userMessage = ChatMessage(role: .user, text: text, time: Date())
        messages.append(userMessage)
        store.appendAIMessage(role: "user", content: text)

        do {
            let answer = try await chatService.send(
                config: config,
                context: store.aiContextSummary(),
                history: store.aiConversation(),
                userInput: text
            )
            let displayText = assistantDisplayText(from: answer)
            messages.append(ChatMessage(role: .assistant, text: displayText, time: Date()))
            store.appendAIMessage(role: "assistant", content: answer)
        } catch {
            errorText = "请求失败：\(error.localizedDescription)"
        }

        sending = false
    }
}

struct ReminderSettingsView: View {
    @EnvironmentObject private var store: PregnancyStore

    @State private var wakeUpTime = ""
    @State private var breakfastTime = ""
    @State private var lunchTime = ""
    @State private var dinnerTime = ""
    @State private var sleepTime = ""
    @State private var minutesBefore = 15
    @State private var reminderHint = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("起床时间（HH:mm）", text: $wakeUpTime)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            TextField("早餐时间（HH:mm）", text: $breakfastTime)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            TextField("午餐时间（HH:mm）", text: $lunchTime)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            TextField("晚餐时间（HH:mm）", text: $dinnerTime)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            TextField("睡觉时间（HH:mm）", text: $sleepTime)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Stepper("提前提醒：\(minutesBefore) 分钟", value: $minutesBefore, in: 0...120, step: 5)

            Button("保存提醒设置") {
                saveAndSchedule()
            }

            if !reminderHint.isEmpty {
                Text(reminderHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let config = store.currentReminderConfig()
            wakeUpTime = config.wakeUpTime
            breakfastTime = config.breakfastTime
            lunchTime = config.lunchTime
            dinnerTime = config.dinnerTime
            sleepTime = config.sleepTime
            minutesBefore = config.minutesBefore
        }
    }

    private func saveAndSchedule() {
        let newConfig = ReminderConfig(
            wakeUpTime: wakeUpTime,
            breakfastTime: breakfastTime,
            lunchTime: lunchTime,
            dinnerTime: dinnerTime,
            sleepTime: sleepTime,
            minutesBefore: minutesBefore
        )
        store.saveReminderConfig(newConfig)
        reminderHint = "提醒设置已保存，将自动同步通知。"
    }
}
