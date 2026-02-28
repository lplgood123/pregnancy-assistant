import SwiftUI

struct ChatHomeView: View {
    @EnvironmentObject private var store: PregnancyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var inputText = ""
    @State private var chatMessages: [HomeChatMessage] = []
    @State private var pendingAction: AIPendingAction?
    @State private var showConfirm = false
    @State private var errorText = ""
    @State private var isTyping = false
    @State private var sessionAnchorIndex = 0
    @State private var didInitializeSessionAnchor = false
    @State private var openingLine = ""
    @State private var isRefreshingOpeningSummary = false
    @FocusState private var inputFocused: Bool

    private let bottomAnchor = "chat-bottom"
    private let chatService = AIBackendChatService()
    private let executableIntents: Set<String> = [
        "create_medication",
        "create_check_record",
        "create_reminder",
        "update_reminder_time"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            conversationSection

                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchor)
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, AppLayout.scrollTailPadding)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        store.refreshForTodayIfNeeded()
                        store.clearExpiredHomeSummaryCacheIfNeeded()
                        openingLine = immediateOpeningLine()
                        initializeSessionIfNeeded()
                        Task { await refreshOpeningLineWithAI(force: false) }
                        scrollToBottom(proxy)
                    }
                    .onChange(of: chatMessages.count) { _, _ in
                        store.saveHomeChatMessages(chatMessages)
                        scrollToBottom(proxy)
                    }
                    .onChange(of: isTyping) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: store.homeSummaryFingerprint()) { _, _ in
                        openingLine = immediateOpeningLine()
                        Task { await refreshOpeningLineWithAI(force: false) }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                topFixedInfoBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerDock
                    .padding(.bottom, AppLayout.mainTabBarHeight)
            }
            .font(AppTheme.bodyFont)
            .toolbar(.hidden, for: .navigationBar)
            .alert("确认记录", isPresented: $showConfirm) {
                Button("取消", role: .cancel) { }
                Button("确认") {
                    if let pendingAction {
                        let result = store.applyAIAction(pendingAction)
                        chatMessages.append(HomeChatMessage(role: .assistant, kind: .text, text: result))
                        self.pendingAction = nil
                        store.removePendingAction(id: pendingAction.id)
                        openingLine = immediateOpeningLine()
                        Task {
                            await refreshOpeningLineWithAI(force: false)
                        }
                    }
                }
            } message: {
                Text(pendingSummary())
            }
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            AssistantBubble {
                Text(openingLine.isEmpty ? store.homeOpeningLine() : openingLine)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            ForEach(visibleMessages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    if message.role == .assistant {
                        AssistantBubble {
                            Text(message.text.isEmpty ? "我在呢，你继续说。" : message.text)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        Text(timeLabel(message.createdAt))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textHint)
                            .padding(.leading, 34)
                    } else {
                        UserBubble {
                            Text(message.text)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }
                        Text(timeLabel(message.createdAt))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textHint)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }

            if isTyping {
                AssistantBubble {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("小助手正在思考…")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var topFixedInfoBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("孕期健康伙伴")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            HStack(spacing: 8) {
                BadgePill(text: "孕 \(store.gestationalWeekText)")
                BadgePill(text: "预产期 \(store.formatDate(store.dueDate))")
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(
            AppTheme.background
                .opacity(0.98)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.borderLight)
                .frame(height: 1)
        }
    }

    private var composerDock: some View {
        VStack(spacing: 6) {
            QuickCommandStrip(commands: Array(store.quickCommandPrompts().prefix(6))) { command in
                inputText = command.prompt
                inputFocused = true
            }
            .padding(.horizontal)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("像聊天一样告诉我：今晚饭后吃钙片", text: $inputText, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.cardAlt)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($inputFocused)

                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            (isTyping || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            ? AppTheme.textSecondary : AppTheme.actionPrimary
                        )
                        .clipShape(Circle())
                }
                .disabled(isTyping || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("发送消息")
                .accessibilityHint("发送当前输入内容")
                .accessibilityValue(isTyping ? "发送中" : "可发送")
            }
            .padding(.horizontal)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(
            AppTheme.card
        )
    }

    private func initializeSessionIfNeeded() {
        if chatMessages.isEmpty {
            chatMessages = store.homeChatMessages()
        }
        guard !didInitializeSessionAnchor else { return }
        sessionAnchorIndex = chatMessages.count
        openingLine = immediateOpeningLine()
        didInitializeSessionAnchor = true
    }

    private func refreshOpeningLineWithAI(force: Bool) async {
        if isRefreshingOpeningSummary {
            return
        }
        if !force && !store.shouldRefreshHomeSummary() {
            return
        }

        let config = store.currentAIConfig()
        guard !config.baseURL.isEmpty else { return }

        let requestFingerprint = store.homeSummaryFingerprint()
        isRefreshingOpeningSummary = true
        defer {
            isRefreshingOpeningSummary = false
        }

        do {
            let line = try await chatService.sendHomeSummary(
                config: config,
                snapshot: store.homeSummarySnapshotText()
            )
            let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            if store.homeSummaryFingerprint() != requestFingerprint {
                return
            }
            store.saveHomeSummaryCache(text: normalized, fingerprint: requestFingerprint)
            await MainActor.run {
                if openingLine != normalized {
                    openingLine = normalized
                }
            }
        } catch {
            // 保持本地兜底文案，不打断主流程
        }
    }

    private func immediateOpeningLine() -> String {
        if !store.shouldRefreshHomeSummary(), let cached = store.cachedHomeSummaryLine() {
            return cached
        }
        return store.homeOpeningLine()
    }

    private func sendMessage() async {
        errorText = ""
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        chatMessages.append(HomeChatMessage(role: .user, kind: .text, text: trimmed))
        inputText = ""
        isTyping = true

        let config = store.currentAIConfig()
        guard !config.baseURL.isEmpty else {
            errorText = "AI 服务未配置。请在应用配置中设置 AI_BACKEND_URL（调试可用环境变量覆盖）。"
            isTyping = false
            return
        }

        do {
            store.appendAIMessage(role: "user", content: trimmed)
            let jsonText = try await chatService.send(
                config: config,
                context: store.aiContextSummary(),
                history: store.aiConversation(),
                userInput: trimmed
            )
            store.appendAIMessage(role: "assistant", content: jsonText)

            if let action = AIParse.parse(jsonText) {
                let normalizedIntent = normalizedIntent(from: action.intent)
                if normalizedIntent == "unknown", action.intent != "unknown" {
                    chatMessages.append(
                        HomeChatMessage(
                            role: .assistant,
                            kind: .text,
                            text: "这个操作我现在还不支持，我先帮你走现有流程：例如“晚饭后吃钙片”或“明天吃什么药”。"
                        )
                    )
                } else if action.needClarify {
                    chatMessages.append(HomeChatMessage(role: .assistant, kind: .text, text: action.clarifyQuestion.isEmpty ? "我还需要一点信息～" : action.clarifyQuestion))
                } else if normalizedIntent == "query_schedule" {
                    chatMessages.append(HomeChatMessage(role: .assistant, kind: .text, text: scheduleReply(for: action, userInput: trimmed)))
                } else if normalizedIntent == "unknown" {
                    let reply = action.assistantReply.isEmpty ? "我在呢～" : action.assistantReply
                    chatMessages.append(HomeChatMessage(role: .assistant, kind: .text, text: reply))
                } else {
                    let pending = AIPendingAction(
                        id: UUID().uuidString,
                        intent: normalizedIntent,
                        slots: action.slots,
                        createdAt: Date()
                    )
                    pendingAction = pending
                    showConfirm = true
                    store.appendPendingAction(pending)
                }
            } else {
                chatMessages.append(HomeChatMessage(role: .assistant, kind: .text, text: "我没能解析出结构化指令，可以换个说法吗？比如“晚饭后吃钙片”或“明天吃什么药”。"))
            }
        } catch {
            errorText = "请求失败：\(error.localizedDescription)"
        }

        isTyping = false
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var visibleMessages: [HomeChatMessage] {
        let anchor = min(max(sessionAnchorIndex, 0), chatMessages.count)
        return Array(chatMessages.dropFirst(anchor))
    }

    private func pendingSummary() -> String {
        guard let pendingAction else { return "确认执行该操作？" }
        switch pendingAction.intent {
        case "create_medication":
            let name = pendingAction.slots["item_name"] ?? "用药"
            let time = displayTime(for: pendingAction)
            return "创建用药：\(name)\(time.isEmpty ? "" : " · \(time)")"
        case "create_check_record":
            let type = pendingAction.slots["check_type"] ?? "检查"
            return "保存检查记录：\(type)"
        case "create_reminder":
            let title = pendingAction.slots["item_name"] ?? "提醒"
            let time = displayTime(for: pendingAction)
            return "创建提醒：\(title)\(time.isEmpty ? "" : " · \(time)")"
        case "update_reminder_time":
            let time = displayTime(for: pendingAction)
            return "更新提醒配置：\(time.isEmpty ? "请确认" : time)"
        default:
            return "确认执行该操作？"
        }
    }

    private func displayTime(for action: AIPendingAction) -> String {
        let semantic = action.slots["time_semantic"] ?? ""
        if action.intent == "update_reminder_time" {
            var parts: [String] = []
            if let period = TimePeriod.fromSemantic(semantic) {
                let exact = action.slots["time_exact"] ?? ""
                let normalized = store.normalizeTimeText(exact) ?? exact
                if !normalized.isEmpty {
                    parts.append("\(period.rawValue) → \(normalized)")
                }
            }
            if let minutes = Int(action.slots["minutes_before"] ?? ""), minutes >= 0 {
                parts.append("提前 \(minutes) 分钟")
            }
            return parts.joined(separator: " · ")
        }

        guard let period = TimePeriod.fromSemantic(semantic) else { return semantic }
        let base = store.reminderTime(for: period)
        let adjusted = ReminderScheduler.semanticAdjustedTimeText(for: period, baseTime: base)
        return "\(period.rawValue)（约 \(adjusted)）"
    }

    private func normalizedIntent(from raw: String) -> String {
        let intent = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if intent == "query_schedule" || intent == "unknown" {
            return intent
        }
        if executableIntents.contains(intent) {
            return intent
        }
        return "unknown"
    }

    private func scheduleReply(for action: ParsedAction, userInput: String) -> String {
        let override = dateSemanticOverride(from: userInput)
        let semanticFromAI = action.slots["date_semantic"] ?? action.slots["time_semantic"] ?? ""
        let semantic = override ?? (semanticFromAI.isEmpty ? userInput : semanticFromAI)
        let (date, label) = dateFromSemantic(semantic)
        let sections = store.medicationSections(for: date)

        if sections.isEmpty {
            return "\(label)没有固定用药安排。"
        }

        let lines = sections.map { section in
            let names = section.rows.map { row in
                if row.subtitle.isEmpty {
                    return row.title
                }
                return "\(row.title)（\(row.subtitle)）"
            }.joined(separator: "、")
            return "\(section.title)：\(names)"
        }

        return "\(label)用药清单：\n" + lines.joined(separator: "\n")
    }

    private func dateFromSemantic(_ text: String) -> (date: Date, label: String) {
        let calendar = Calendar.current
        if text.contains("明天") || text.contains("明日") || text.lowercased().contains("tomorrow") {
            let date = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return (date, "明天")
        }
        if text.contains("后天") {
            let date = calendar.date(byAdding: .day, value: 2, to: Date()) ?? Date()
            return (date, "后天")
        }
        return (Date(), "今天")
    }

    private func dateSemanticOverride(from text: String) -> String? {
        if text.contains("后天") { return "后天" }
        if text.contains("明天") || text.contains("明日") { return "明天" }
        if text.contains("今天") { return "今天" }
        return nil
    }
}

enum AIParse {
    static func parse(_ text: String) -> ParsedAction? {
        guard let json = extractJSON(text) else { return nil }
        guard let data = json.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let intent = obj["intent"] as? String ?? "unknown"
        let needClarify = obj["need_clarify"] as? Bool ?? false
        let clarifyQuestion = obj["clarify_question"] as? String ?? ""
        let assistantReply = obj["assistant_reply"] as? String ?? ""

        var slots: [String: String] = [:]
        if let rawSlots = obj["slots"] as? [String: Any] {
            for (key, value) in rawSlots {
                if value is NSNull {
                    slots[key] = ""
                } else {
                    slots[key] = String(describing: value)
                }
            }
        }

        return ParsedAction(
            intent: intent,
            slots: slots,
            needClarify: needClarify,
            clarifyQuestion: clarifyQuestion,
            assistantReply: assistantReply
        )
    }

    private static func extractJSON(_ text: String) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
            trimmed = trimmed.replacingOccurrences(of: "```", with: "")
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return nil
    }
}

struct ParsedAction {
    var intent: String
    var slots: [String: String]
    var needClarify: Bool
    var clarifyQuestion: String
    var assistantReply: String
}

struct AssistantBubble<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Circle()
                .fill(AppTheme.accentSoft)
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.actionPrimary)
                )

            content
                .padding(12)
                .background(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
                .frame(maxWidth: 300, alignment: .leading)

            Spacer()
        }
    }
}

struct UserBubble<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack {
            Spacer()
            content
                .padding(12)
                .background(AppTheme.actionPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                .frame(maxWidth: 300, alignment: .trailing)
        }
    }
}

struct HighlightCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardAlt)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct QuickCardsBar: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NavigationLink {
                    TodayPlanView()
                } label: {
                    QuickActionChip(icon: "calendar", title: "今天计划")
                }

                NavigationLink {
                    MedicationListView()
                } label: {
                    QuickActionChip(icon: "pills", title: "用药清单")
                }

                NavigationLink {
                    AppointmentListView()
                } label: {
                    QuickActionChip(icon: "cross.case", title: "产检预约")
                }

                NavigationLink {
                    CheckListView()
                } label: {
                    QuickActionChip(icon: "list.bullet.clipboard", title: "检查记录")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}

struct QuickActionChip: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(AppTheme.accentSoft)
        .overlay(
            Capsule()
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

#Preview {
    ChatHomeView()
        .environmentObject(PregnancyStore())
}
