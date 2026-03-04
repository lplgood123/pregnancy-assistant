import Foundation
import SwiftUI
import UIKit

private struct ComposerDockHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatHomeView: View {
    private enum OCRProcessingState: Equatable {
        case idle
        case processing
        case failed(String)
    }

    private enum VoicePressState: Equatable {
        case idle
        case recording
        case canceling
    }

    private enum ComposerInputMode: Equatable {
        case text
        case voice
    }

    private enum ImageSource: Identifiable {
        case camera
        case library

        var id: Int {
            switch self {
            case .camera: return 1
            case .library: return 2
            }
        }

        var sourceType: UIImagePickerController.SourceType {
            switch self {
            case .camera: return .camera
            case .library: return .photoLibrary
            }
        }
    }

    let tabBarVisible: Bool

    @EnvironmentObject private var store: PregnancyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var inputText = ""
    @State private var chatMessages: [HomeChatMessage] = []
    @State private var pendingAction: AIPendingAction?
    @State private var showConfirm = false
    @State private var errorText = ""
    @State private var isTyping = false
    @State private var typingStageText = "小助手正在思考…"
    @State private var openingLine = ""
    @State private var isRefreshingOpeningSummary = false
    @State private var failedMessageID: String?
    @State private var failedUserInput: String?
    @State private var isRetryingFailedMessage = false
    @State private var didTriggerBackendWarmup = false
    @State private var composerInputMode: ComposerInputMode = .text
    @State private var voicePressState: VoicePressState = .idle
    @State private var voiceDragOffset: CGSize = .zero
    @State private var liveVoiceTranscript = ""
    @State private var activeVoiceSessionID: UUID?
    @State private var ocrProcessingState: OCRProcessingState = .idle
    @State private var showImageSourceDialog = false
    @State private var imageSource: ImageSource?
    @State private var composerDockHeight: CGFloat = 0
    @FocusState private var inputFocused: Bool
    @StateObject private var speechInput = SpeechInputService()

    private let bottomAnchor = "chat-bottom"
    private let voiceCancelThreshold: CGFloat = 70
    private let chatService = AIBackendChatService()
    private let executableIntents: Set<String> = [
        "create_medication",
        "create_check_record",
        "create_appointment",
        "create_reminder",
        "update_profile",
        "update_reminder_time"
    ]

    private var isRecordingVoice: Bool {
        voicePressState != .idle
    }

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
                        .padding(.bottom, conversationBottomPadding)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if inputFocused {
                                inputFocused = false
                            }
                        }
                    )
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        store.refreshForTodayIfNeeded()
                        store.clearExpiredHomeSummaryCacheIfNeeded()
                        openingLine = immediateOpeningLine()
                        initializeSessionIfNeeded()
                        injectDailyGreetingIfNeeded()
                        triggerBackendWarmupIfNeeded()
                        Task { await refreshOpeningLineWithAI(force: false) }
                        scrollToBottomStable(proxy)
                    }
                    .onChange(of: chatMessages.count) { _, _ in
                        store.saveHomeChatMessages(chatMessages)
                        scrollToBottomStable(proxy)
                    }
                    .onChange(of: isTyping) { _, _ in
                        scrollToBottomStable(proxy)
                    }
                    .onChange(of: inputFocused) { _, _ in
                        scrollToBottomStable(proxy)
                    }
                    .onChange(of: tabBarVisible) { _, _ in
                        scrollToBottomStable(proxy)
                    }
                    .onChange(of: composerDockHeight) { _, _ in
                        scrollToBottomStable(proxy)
                    }
                    .onChange(of: store.homeSummaryFingerprint()) { _, _ in
                        openingLine = immediateOpeningLine()
                        Task { await refreshOpeningLineWithAI(force: false) }
                    }
                    .onChange(of: store.resetEpoch) { _, _ in
                        clearLocalSessionState()
                        initializeSessionIfNeeded()
                        injectDailyGreetingIfNeeded()
                        scrollToBottomStable(proxy)
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        guard newPhase == .active else { return }
                        injectDailyGreetingIfNeeded()
                        scrollToBottomStable(proxy)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                topFixedInfoBar
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerDock
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: ComposerDockHeightPreferenceKey.self, value: proxy.size.height)
                        }
                    )
            }
            .onPreferenceChange(ComposerDockHeightPreferenceKey.self) { height in
                let normalizedHeight = max(height, 0)
                guard abs(normalizedHeight - composerDockHeight) > 0.5 else { return }
                composerDockHeight = normalizedHeight
            }
            .font(AppTheme.bodyFont)
            .toolbar(.hidden, for: .navigationBar)
            .alert("确认记录", isPresented: $showConfirm) {
                Button("取消", role: .cancel) {
                    if let pendingAction {
                        store.removePendingAction(id: pendingAction.id)
                        self.pendingAction = nil
                    }
                }
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
            .confirmationDialog("上传检查报告", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
                Button("拍照") {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        errorText = "当前设备不支持拍照，请改用相册上传。"
                        return
                    }
                    imageSource = .camera
                }
                Button("从相册选择") {
                    imageSource = .library
                }
                Button("取消", role: .cancel) { }
            }
            .sheet(item: $imageSource) { source in
                AppImagePicker(sourceType: source.sourceType) { image in
                    Task {
                        await processPickedImage(image)
                    }
                }
            }
            .onDisappear {
                resetVoiceState(stopRecognition: true)
                store.saveHomeChatMessages(chatMessages)
            }
            .onChange(of: inputText) { oldValue, newValue in
                handlePotentialKeyboardSend(previous: oldValue, current: newValue)
            }
        }
    }

    private var conversationSection: some View {
        let openingText = openingLine.isEmpty ? store.homeOpeningLine() : openingLine
        return VStack(alignment: .leading, spacing: 10) {
            AssistantBubble {
                Text(openingText)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("复制") {
                            copyToPasteboard(openingText)
                        }
                    }
            }

            ForEach(visibleMessages) { message in
                VStack(alignment: .leading, spacing: 4) {
                    if message.role == .assistant {
                        let assistantText = message.text.isEmpty ? "我在呢，你继续说。" : message.text
                        AssistantBubble {
                            Text(assistantText)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textPrimary)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button("复制") {
                                        copyToPasteboard(assistantText)
                                    }
                                }
                        }
                        Text(timeLabel(message.createdAt))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textHint.opacity(0.7))
                            .padding(.leading, 38)
                    } else {
                        UserBubble {
                            Text(message.text)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button("复制") {
                                        copyToPasteboard(message.text)
                                    }
                                }
                        }
                        if message.deliveryStatus == .failed {
                            HStack(spacing: 8) {
                                Text(message.deliveryError ?? "发送失败")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.bannerError)
                                Button {
                                    Task {
                                        await retryFailedMessage(messageID: message.id, input: message.text)
                                    }
                                } label: {
                                    Text((isRetryingFailedMessage && failedMessageID == message.id) ? "重试中..." : "重试发送")
                                        .font(.caption2.weight(.semibold))
                                }
                                .buttonStyle(.plain)
                                .disabled(isTyping || (isRetryingFailedMessage && failedMessageID == message.id))
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
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
                        Text(typingStageText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        UIPasteboard.general.string = text
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
        VStack(spacing: 0) {
            // 快捷命令条
            if tabBarVisible {
                QuickCommandStrip(commands: Array(store.quickCommandPrompts().prefix(6))) { command in
                    handleQuickCommandTap(command)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            HStack(alignment: .center, spacing: 8) {
                composerModeToggleButton
                composerMainSlot
                imageUploadButton
            }
            .padding(.horizontal, 12)
            .padding(.top, tabBarVisible ? 0 : 10)
            .padding(.bottom, 8)

            // TabBar 占位 — 和记录页按钮到 TabBar 的高度一致
            if tabBarVisible {
                Color.clear
                    .frame(height: AppLayout.tabBarVisibleHeight)
            }

            // 状态提示
            if isRecordingVoice {
                Text(voicePressState == .canceling ? "松开取消" : "松开发送")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(voicePressState == .canceling ? AppTheme.statusError : AppTheme.statusInfo)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if case .processing = ocrProcessingState {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("图片识别中...")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            if !errorText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.statusError)
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.statusError)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background {
            Color(hex: "F7F8FA")
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: -2)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(hex: "E9EDF2").opacity(0.6))
                .frame(height: 0.5)
        }
    }

    private var composerModeToggleButton: some View {
        Button {
            toggleComposerInputMode()
        } label: {
            Image(systemName: composerInputMode == .voice ? "keyboard" : "mic.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(composerInputMode == .voice ? AppTheme.actionPrimary : AppTheme.textSecondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .appTapTarget()
        .accessibilityLabel(composerInputMode == .voice ? "切换到文字输入" : "切换到语音输入")
    }

    private var imageUploadButton: some View {
        Button {
            showImageSourceDialog = true
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 32, height: 32)
        }
        .disabled(isTyping)
        .buttonStyle(.plain)
        .appTapTarget()
        .accessibilityLabel("上传图片")
    }

    private var composerMainSlot: some View {
        Group {
            if composerInputMode == .text {
                textInputSlot
            } else {
                voiceInputSlot
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.9))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(composerBorderColor, lineWidth: composerBorderWidth)
        )
        .shadow(
            color: composerShadowColor,
            radius: composerInputMode == .text && inputFocused ? 8 : 4,
            x: 0,
            y: 2
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: inputFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: composerInputMode)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: voicePressState)
    }

    private var textInputSlot: some View {
        TextField("", text: $inputText, axis: .vertical)
            .placeholder(when: inputText.isEmpty) {
                Text("说点什么...")
                    .foregroundStyle(AppTheme.textHint)
            }
            .lineLimit(1...4)
            .font(.system(size: 15))
            .foregroundStyle(AppTheme.textPrimary)
            .tint(AppTheme.actionPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .focused($inputFocused)
            .submitLabel(.send)
            .onSubmit {
                Task {
                    await sendMessage()
                }
            }
    }

    private var voiceInputSlot: some View {
        let dragGesture = DragGesture(minimumDistance: 0)
            .onChanged { value in
                if voicePressState == .idle {
                    beginPressToTalk()
                }
                updatePressToTalkDrag(value.translation.height)
            }
            .onEnded { _ in
                endPressToTalk()
            }

        return HStack(spacing: 8) {
            Image(systemName: voiceButtonSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(voiceButtonForegroundColor)
            Text(voiceActionText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(voicePressState == .canceling ? AppTheme.statusError : AppTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture)
        .accessibilityElement()
        .accessibilityLabel("按住说话")
        .accessibilityHint("按住录音，松开发送；上滑取消")
        .accessibilityValue(voicePressState == .canceling ? "将取消" : (isRecordingVoice ? "录音中" : "待机"))
    }

    private var voiceActionText: String {
        switch voicePressState {
        case .idle:
            return "按住说话"
        case .recording:
            return "松开发送"
        case .canceling:
            return "松开取消"
        }
    }

    private var composerBorderColor: Color {
        if composerInputMode == .text {
            return inputFocused ? AppTheme.actionPrimary.opacity(0.5) : AppTheme.border
        }
        switch voicePressState {
        case .idle:
            return AppTheme.border
        case .recording:
            return AppTheme.actionPrimary.opacity(0.55)
        case .canceling:
            return AppTheme.statusError.opacity(0.6)
        }
    }

    private var composerBorderWidth: CGFloat {
        if composerInputMode == .text {
            return inputFocused ? 1.5 : 1
        }
        return voicePressState == .idle ? 1 : 1.5
    }

    private var composerShadowColor: Color {
        if composerInputMode == .text {
            return inputFocused ? AppTheme.actionPrimary.opacity(0.15) : Color.black.opacity(0.05)
        }
        switch voicePressState {
        case .idle:
            return Color.black.opacity(0.05)
        case .recording:
            return AppTheme.actionPrimary.opacity(0.12)
        case .canceling:
            return AppTheme.statusError.opacity(0.12)
        }
    }

    private var voiceButtonForegroundColor: Color {
        switch voicePressState {
        case .idle:
            return AppTheme.textSecondary
        case .recording:
            return AppTheme.actionPrimary
        case .canceling:
            return AppTheme.statusError
        }
    }

    private var voiceButtonSymbol: String {
        switch voicePressState {
        case .idle:
            return "mic.fill"
        case .recording:
            return "waveform"
        case .canceling:
            return "xmark"
        }
    }

    private func toggleComposerInputMode() {
        if composerInputMode == .voice {
            if isRecordingVoice {
                resetVoiceState(stopRecognition: true)
            }
            composerInputMode = .text
            DispatchQueue.main.async {
                inputFocused = true
            }
        } else {
            composerInputMode = .voice
            inputFocused = false
        }
    }

    private func initializeSessionIfNeeded() {
        if chatMessages.isEmpty {
            chatMessages = store.homeChatMessages()
        }
        restorePendingActionIfNeeded()
        openingLine = immediateOpeningLine()
    }

    private func clearLocalSessionState() {
        resetVoiceState(stopRecognition: true)
        inputText = ""
        chatMessages = []
        pendingAction = nil
        showConfirm = false
        errorText = ""
        isTyping = false
        typingStageText = "小助手正在思考…"
        failedMessageID = nil
        failedUserInput = nil
        isRetryingFailedMessage = false
        ocrProcessingState = .idle
        showImageSourceDialog = false
        imageSource = nil
    }

    private func injectDailyGreetingIfNeeded(now: Date = Date()) {
        if chatMessages.isEmpty {
            let stored = store.homeChatMessages()
            if !stored.isEmpty {
                chatMessages = stored
            }
        }
        guard let greeting = store.takeDailyGreetingIfNeeded(now: now) else { return }
        chatMessages.append(greeting)
        store.saveHomeChatMessages(chatMessages)
    }

    private func restorePendingActionIfNeeded() {
        if pendingAction != nil { return }
        guard let lastPending = store.aiPendingActions().last else { return }
        pendingAction = lastPending
        showConfirm = true
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

    private func triggerBackendWarmupIfNeeded() {
        guard !didTriggerBackendWarmup else { return }
        let config = store.currentAIConfig()
        guard !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        didTriggerBackendWarmup = true
        Task {
            await chatService.warmup(config: config)
        }
    }

    private func handlePotentialKeyboardSend(previous: String, current: String) {
        guard composerInputMode == .text else { return }
        guard !isTyping else { return }
        let oldBreakCount = previous.filter { $0 == "\n" }.count
        let newBreakCount = current.filter { $0 == "\n" }.count
        guard newBreakCount > oldBreakCount else { return }

        // 仅在“原文本 + 单个末尾换行”时视为键盘发送，避免粘贴多行文本被误发送。
        let isSingleTrailingNewlineSubmit =
            current.hasSuffix("\n") &&
            current.dropLast() == previous &&
            newBreakCount == oldBreakCount + 1
        guard isSingleTrailingNewlineSubmit else { return }

        let candidate = current
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty {
            inputText = ""
            return
        }

        inputText = candidate
        Task {
            await sendMessage()
        }
    }

    private func sendMessage() async {
        errorText = ""
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        await submitUserInput(trimmed)
    }

    private func submitUserInput(_ input: String) async {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard !isTyping else {
            inputText = normalized
            return
        }

        let message = HomeChatMessage(
            role: .user,
            kind: .text,
            text: normalized,
            deliveryStatus: .sent,
            deliveryError: nil
        )
        chatMessages.append(message)
        store.saveHomeChatMessages(chatMessages)
        await sendUserMessage(normalized, messageID: message.id)
    }

    private func handleQuickCommandTap(_ command: QuickCommand) {
        let prompt = command.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let directSendTodayPlan =
            command.title.contains("今日安排") ||
            prompt.contains("今天需要注意的安排") ||
            prompt.contains("今日安排")

        if directSendTodayPlan {
            Task {
                await submitUserInput(prompt)
            }
        } else {
            inputText = prompt
            inputFocused = true
        }
    }

    private func beginPressToTalk() {
        guard voicePressState == .idle else { return }

        errorText = ""
        liveVoiceTranscript = ""
        voiceDragOffset = .zero
        voicePressState = .recording

        let sessionID = UUID()
        activeVoiceSessionID = sessionID

        Task {
            do {
                try await speechInput.startRecognition(
                    onPartial: { partial in
                        guard activeVoiceSessionID == sessionID else { return }
                        liveVoiceTranscript = partial
                    },
                    onFinal: { finalText in
                        guard activeVoiceSessionID == sessionID else { return }
                        liveVoiceTranscript = finalText
                    }
                )
                if activeVoiceSessionID != sessionID {
                    speechInput.stopRecognition()
                }
            } catch {
                guard activeVoiceSessionID == sessionID else { return }
                resetVoiceState(stopRecognition: true)
                let message = (error as? LocalizedError)?.errorDescription ?? "语音输入失败，请稍后重试。"
                errorText = message
            }
        }
    }

    private func updatePressToTalkDrag(_ translationY: CGFloat) {
        guard voicePressState != .idle else { return }
        voiceDragOffset = CGSize(width: 0, height: translationY)
        if translationY <= -voiceCancelThreshold {
            voicePressState = .canceling
        } else {
            voicePressState = .recording
        }
    }

    private func endPressToTalk() {
        guard voicePressState != .idle else { return }

        let shouldCancel = voicePressState == .canceling
        let finalTranscript = liveVoiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        resetVoiceState(stopRecognition: true)

        guard !shouldCancel else { return }
        guard !finalTranscript.isEmpty else {
            errorText = "未识别到语音内容，请重试。"
            return
        }

        Task {
            await submitUserInput(finalTranscript)
        }
    }

    private func resetVoiceState(stopRecognition: Bool) {
        if stopRecognition {
            speechInput.stopRecognition()
        }
        activeVoiceSessionID = nil
        voicePressState = .idle
        voiceDragOffset = .zero
        liveVoiceTranscript = ""
    }

    private func processPickedImage(_ image: UIImage) async {
        guard !isTyping else { return }
        errorText = ""
        ocrProcessingState = .processing
        do {
            let recognized = try await ImageOCRService.recognizeText(from: image)
            ocrProcessingState = .idle
            let prompt = "以下是我上传图片识别出的文本，请帮我整理关键提醒并给出下一步建议：\n\(recognized)"
            await submitUserInput(prompt)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "图片识别失败，请稍后重试。"
            ocrProcessingState = .failed(message)
            errorText = message
        }
    }

    private func retryFailedMessage(messageID: String, input: String) async {
        guard !isTyping else { return }
        let sourceInput = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (failedUserInput ?? "") : input
        guard !sourceInput.isEmpty else { return }
        failedMessageID = messageID
        failedUserInput = sourceInput
        isRetryingFailedMessage = true
        defer { isRetryingFailedMessage = false }

        await sendUserMessage(sourceInput, messageID: messageID)
    }

    private func sendUserMessage(_ input: String, messageID: String) async {
        isTyping = true
        typingStageText = stageText(for: .connecting)
        defer {
            isTyping = false
            typingStageText = stageText(for: .finished)
        }

        let config = store.currentAIConfig()
        guard !config.baseURL.isEmpty else {
            markMessageFailed(
                id: messageID,
                input: input,
                reason: "AI 服务未配置。请设置 AI_BACKEND_URL。"
            )
            return
        }

        do {
            let jsonText = try await chatService.sendWithRecovery(
                config: config,
                context: store.aiContextSummary(),
                history: store.aiConversation(),
                userInput: input
            ) { stage in
                typingStageText = stageText(for: stage)
            }
            store.appendAIMessage(role: "user", content: input)
            store.appendAIMessage(role: "assistant", content: jsonText)

            markMessageSent(id: messageID)
            applyAssistantResponse(jsonText, userInput: input)

            if failedMessageID == messageID {
                failedMessageID = nil
                failedUserInput = nil
            }
            errorText = ""
        } catch {
            let mapped = AIRequestError.map(error)
            markMessageFailed(id: messageID, input: input, reason: mapped.userMessage)
        }
    }

    private func stageText(for stage: AIRequestStage) -> String {
        switch stage {
        case .connecting:
            return "正在连接 AI 服务…"
        case let .retrying(current, total):
            return "网络波动，正在第 \(current)/\(total) 次重试…"
        case .compensating:
            return "正在执行补偿重试…"
        case .finished:
            return "小助手正在思考…"
        }
    }

    private func applyAssistantResponse(_ jsonText: String, userInput: String) {
        if let action = AIParse.parse(jsonText) {
            let normalizedIntent = normalizedIntent(from: action.intent)
            let profileSlots = mergedProfileSlots(aiSlots: action.slots, userInput: userInput)
            var effectiveIntent: String
            var effectiveSlots: [String: String]
            if normalizedIntent == "update_profile" {
                effectiveIntent = "update_profile"
                effectiveSlots = profileSlots ?? action.slots
            } else if normalizedIntent == "unknown", let profileSlots {
                effectiveIntent = "update_profile"
                effectiveSlots = profileSlots
            } else {
                effectiveIntent = normalizedIntent
                effectiveSlots = action.slots
            }

            if shouldConvertToAppointment(intent: effectiveIntent, slots: effectiveSlots, userInput: userInput) {
                effectiveIntent = "create_appointment"
                effectiveSlots = mergedAppointmentSlots(aiSlots: effectiveSlots, userInput: userInput)
            }

            if effectiveIntent == "unknown", normalizedIntent == "unknown", action.intent != "unknown" {
                chatMessages.append(
                    HomeChatMessage(
                        role: .assistant,
                        kind: .text,
                        text: "这个操作我现在还不支持，我先帮你走现有流程：例如“晚饭后吃钙片”或“明天吃什么药”。"
                    )
                )
            } else if action.needClarify && effectiveIntent != "update_profile" {
                chatMessages.append(
                    HomeChatMessage(
                        role: .assistant,
                        kind: .text,
                        text: action.clarifyQuestion.isEmpty ? "我还需要一点信息～" : action.clarifyQuestion
                    )
                )
            } else if effectiveIntent == "query_schedule" {
                chatMessages.append(HomeChatMessage(role: .assistant, kind: .text, text: scheduleReply(for: action, userInput: userInput)))
            } else if effectiveIntent == "unknown" {
                if looksLikeProfileMetricRequest(userInput) {
                    chatMessages.append(
                        HomeChatMessage(
                            role: .assistant,
                            kind: .text,
                            text: "要记录身高体重，请带上数值，例如“身高165厘米，体重52.3公斤”，也可以只说“记录体重53公斤”。"
                        )
                    )
                } else {
                    let reply = action.assistantReply.isEmpty ? "我在呢～" : action.assistantReply
                    chatMessages.append(HomeChatMessage(role: .assistant, kind: .text, text: reply))
                }
            } else {
                let pending = AIPendingAction(
                    id: UUID().uuidString,
                    intent: effectiveIntent,
                    slots: effectiveSlots,
                    createdAt: Date()
                )
                pendingAction = pending
                showConfirm = true
                store.appendPendingAction(pending)
            }
        } else {
            chatMessages.append(
                HomeChatMessage(
                    role: .assistant,
                    kind: .text,
                    text: "我没能解析出结构化指令，可以换个说法吗？比如“晚饭后吃钙片”或“明天吃什么药”。"
                )
            )
        }
    }

    private func markMessageFailed(id: String, input: String, reason: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            errorText = reason
            failedMessageID = id
            failedUserInput = input
            return
        }

        chatMessages[index].deliveryStatus = .failed
        chatMessages[index].deliveryError = reason
        store.saveHomeChatMessages(chatMessages)
        errorText = reason
        failedMessageID = id
        failedUserInput = input
    }

    private func markMessageSent(id: String) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else { return }
        chatMessages[index].deliveryStatus = .sent
        chatMessages[index].deliveryError = nil
        store.saveHomeChatMessages(chatMessages)
    }

    private var conversationBottomPadding: CGFloat {
        max(AppLayout.scrollTailPadding, composerDockHeight + 12)
    }

    private func scrollToBottomStable(_ proxy: ScrollViewProxy) {
        scrollToBottom(proxy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            scrollToBottom(proxy)
        }
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
        chatMessages
    }

    private func pendingSummary() -> String {
        guard let pendingAction else { return "确认执行该操作？" }
        switch pendingAction.intent {
        case "create_medication":
            if let preview = medicationBatchPreview(from: pendingAction.slots), preview.count > 1 {
                let names = preview.names.joined(separator: "、")
                let tail = preview.count > preview.names.count ? " 等" : ""
                return "创建用药 \(preview.count) 项：\(names)\(tail)"
            }
            let name = pendingAction.slots["item_name"] ?? "用药"
            let time = displayTime(for: pendingAction)
            return "创建用药：\(name)\(time.isEmpty ? "" : " · \(time)")"
        case "create_check_record":
            let type = pendingAction.slots["check_type"] ?? "检查报告"
            return "保存检查报告：\(type)"
        case "create_appointment":
            let title = pendingAction.slots["item_name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let dateText = pendingAction.slots["check_date"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? pendingAction.slots["date_semantic"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            let timeText = pendingAction.slots["time_exact"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let displayTitle = title.isEmpty ? "复诊预约" : title
            let displayDate = dateText.isEmpty ? "待定日期" : dateText
            let displayTime = timeText.isEmpty ? "09:00" : timeText
            return "创建预约：\(displayTitle) · \(displayDate) \(displayTime)"
        case "create_reminder":
            let title = pendingAction.slots["item_name"] ?? "提醒"
            let time = displayTime(for: pendingAction)
            return "创建提醒：\(title)\(time.isEmpty ? "" : " · \(time)")"
        case "update_profile":
            var parts: [String] = []
            if let height = pendingAction.slots["height_cm"]?.trimmingCharacters(in: .whitespacesAndNewlines), !height.isEmpty {
                parts.append("身高 \(height) cm")
            }
            if let weight = pendingAction.slots["weight_kg"]?.trimmingCharacters(in: .whitespacesAndNewlines), !weight.isEmpty {
                parts.append("体重 \(weight) kg")
            }
            if parts.isEmpty {
                return "更新个人信息：请确认"
            }
            return "记录个人信息：\(parts.joined(separator: " · "))"
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

    private func medicationBatchPreview(from slots: [String: String]) -> (count: Int, names: [String])? {
        for key in ["medications", "medication_items", "items"] {
            guard let raw = slots[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let list = json as? [[String: Any]] else {
                continue
            }

            let names = list.compactMap { item in
                firstNonEmptyString(
                    item["item_name"],
                    item["name"],
                    item["title"]
                )
            }
            if !names.isEmpty {
                return (names.count, Array(names.prefix(4)))
            }
        }
        return nil
    }

    private func firstNonEmptyString(_ values: Any?...) -> String? {
        for value in values {
            let text: String
            if let stringValue = value as? String {
                text = stringValue
            } else if let numberValue = value as? NSNumber {
                text = numberValue.stringValue
            } else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
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
        let injectionDue = store.isInjectionDue(on: date)

        if sections.isEmpty && !injectionDue {
            return "\(label)没有固定用药安排。"
        }

        var lines: [String] = sections.map { section in
            let names = section.rows
                .map { row in
                    if row.subtitle.isEmpty {
                        return row.title
                    }
                    return "\(row.title)（\(row.subtitle)）"
                }
                .joined(separator: "、")
            return "\(section.title)：\(names)"
        }
        if injectionDue {
            lines.append("打针：\(store.state.injectionPlan.title)（\(store.state.injectionPlan.detail)）")
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

    private func looksLikeProfileMetricRequest(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("身高") ||
        lowered.contains("体重") ||
        lowered.contains("height") ||
        lowered.contains("weight")
    }

    private func mergedProfileSlots(aiSlots: [String: String], userInput: String) -> [String: String]? {
        let parsedFromUser = parseProfileSlotsFromText(userInput)
        var merged: [String: String] = [:]

        if let height = normalizeBodyMetricSlot(
            aiSlots["height_cm"] ??
            aiSlots["heightCM"] ??
            aiSlots["height"] ??
            parsedFromUser["height_cm"]
        ) {
            merged["height_cm"] = height
        }

        if let weight = normalizeWeightSlot(
            aiSlots["weight_kg"] ??
            aiSlots["weightKG"] ??
            aiSlots["weight"] ??
            parsedFromUser["weight_kg"]
        ) {
            merged["weight_kg"] = weight
        }

        if let dateText = aiSlots["check_date"]?.trimmingCharacters(in: .whitespacesAndNewlines), !dateText.isEmpty {
            merged["check_date"] = dateText
        }
        return merged.isEmpty ? nil : merged
    }

    private func shouldConvertToAppointment(intent: String, slots: [String: String], userInput: String) -> Bool {
        guard intent == "create_check_record" || intent == "create_reminder" else { return false }

        let mergedText = [
            userInput,
            slots["item_name"] ?? "",
            slots["check_type"] ?? "",
            slots["note"] ?? "",
            slots["date_semantic"] ?? "",
            slots["check_date"] ?? ""
        ].joined(separator: " ").lowercased()

        let appointmentKeywords = ["复诊", "回诊", "产检", "门诊", "医院", "就诊", "挂号", "医生"]
        let hasAppointmentKeyword = appointmentKeywords.contains { mergedText.contains($0) }
        if !hasAppointmentKeyword {
            return false
        }

        let hasStrongLabMetrics = !((slots["hcg"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
        !((slots["progesterone"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
        !((slots["estradiol"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let reportKeywords = ["妊娠三项", "hcg", "孕酮", "雌二醇", "nt", "唐筛", "报告", "b超", "超声"]
        let hasReportKeyword = reportKeywords.contains { mergedText.contains($0) }
        return !(hasStrongLabMetrics || hasReportKeyword)
    }

    private func mergedAppointmentSlots(aiSlots: [String: String], userInput: String) -> [String: String] {
        var merged = aiSlots
        let rawTitle = firstNonEmptyString(
            aiSlots["item_name"],
            aiSlots["appointment_title"],
            aiSlots["title"],
            aiSlots["check_type"]
        ) ?? ""
        let normalizedTitle = normalizeAppointmentTitle(rawTitle, userInput: userInput)
        merged["item_name"] = normalizedTitle

        if (merged["check_date"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let dateText = firstNonEmptyString(
                aiSlots["check_date"],
                aiSlots["due_date"],
                aiSlots["appointment_date"],
                aiSlots["date_semantic"]
            ) {
                merged["check_date"] = dateText
            }
        }

        if (merged["time_exact"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let timeText = firstNonEmptyString(
                aiSlots["time_exact"],
                aiSlots["appointment_time"]
            ) {
                merged["time_exact"] = timeText
            }
        }

        if (merged["note"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleaned = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                merged["note"] = cleaned
            }
        }

        return merged
    }

    private func normalizeAppointmentTitle(_ rawTitle: String, userInput: String) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "提醒", trimmed != "检查", trimmed != "检查记录", trimmed != "检查报告" {
            return trimmed
        }
        if userInput.contains("产检") {
            return "产检复诊"
        }
        return "医院复诊"
    }

    private func parseProfileSlotsFromText(_ text: String) -> [String: String] {
        var slots: [String: String] = [:]
        let lowered = text.lowercased()

        if let height = firstRegexCapture(in: lowered, pattern: #"(?:身高|height)\s*(?:是|为|[:：])?\s*(\d{2,3}(?:\.\d+)?)"#)
            ?? firstRegexCapture(in: lowered, pattern: #"(\d{2,3}(?:\.\d+)?)\s*(?:cm|厘米|公分)"#) {
            slots["height_cm"] = height
        }

        if let weightWithUnit = firstRegexCaptures(in: lowered, pattern: #"(?:体重|weight)\s*(?:是|为|[:：])?\s*(\d{2,3}(?:\.\d+)?)\s*(kg|公斤|千克|斤)?"#) {
            if let converted = normalizedWeight(raw: weightWithUnit.value, unit: weightWithUnit.unit) {
                slots["weight_kg"] = converted
            }
        } else if let fallbackWeight = firstRegexCaptures(in: lowered, pattern: #"(\d{2,3}(?:\.\d+)?)\s*(kg|公斤|千克|斤)"#) {
            if let converted = normalizedWeight(raw: fallbackWeight.value, unit: fallbackWeight.unit) {
                slots["weight_kg"] = converted
            }
        }

        return slots
    }

    private func normalizeBodyMetricSlot(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed) {
            return formattedMetric(value)
        }
        if let capture = firstRegexCapture(in: trimmed, pattern: #"(\d+(?:\.\d+)?)"#), let value = Double(capture) {
            return formattedMetric(value)
        }
        return nil
    }

    private func normalizeWeightSlot(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let lowered = raw.lowercased()
        if let capture = firstRegexCaptures(
            in: lowered,
            pattern: #"(\d+(?:\.\d+)?)\s*(kg|公斤|千克|斤)?"#
        ) {
            return normalizedWeight(raw: capture.value, unit: capture.unit)
        }
        return normalizeBodyMetricSlot(raw)
    }

    private func normalizedWeight(raw: String, unit: String?) -> String? {
        guard let value = Double(raw) else { return nil }
        let normalizedValue: Double
        if let unit, unit == "斤" {
            normalizedValue = value / 2.0
        } else {
            normalizedValue = value
        }
        return formattedMetric(normalizedValue)
    }

    private func formattedMetric(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    private func firstRegexCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    private func firstRegexCaptures(in text: String, pattern: String) -> (value: String, unit: String?)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        var unit: String?
        if match.numberOfRanges > 2,
           let unitRange = Range(match.range(at: 2), in: text) {
            unit = String(text[unitRange])
        }
        return (String(text[valueRange]), unit)
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
                slots[key] = slotValueToString(value)
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

    private static func slotValueToString(_ value: Any) -> String {
        if value is NSNull { return "" }
        if let stringValue = value as? String { return stringValue }
        if let dictValue = value as? [String: Any],
           JSONSerialization.isValidJSONObject(dictValue),
           let data = try? JSONSerialization.data(withJSONObject: dictValue, options: [.sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        if let arrayValue = value as? [Any],
           JSONSerialization.isValidJSONObject(arrayValue),
           let data = try? JSONSerialization.data(withJSONObject: arrayValue, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return String(describing: value)
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
        HStack(alignment: .bottom, spacing: 10) {
            // 助手头像 - 渐变圆形
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "FFD4E5"),
                            Color(hex: "E8B4D9")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppTheme.actionPrimary, AppTheme.accentBrand],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: AppTheme.actionPrimary.opacity(0.2), radius: 8, x: 0, y: 2)

            // 气泡 - Glassmorphism 风格
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(0.85))
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                .frame(maxWidth: 280, alignment: .leading)

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
            // 用户气泡 - Glassmorphism 风格，女性向渐变
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "FFB6D9"),
                                    Color(hex: "E88B9C")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .opacity(0.9)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: AppTheme.actionPrimary.opacity(0.25), radius: 12, x: 0, y: 4)
                .frame(maxWidth: 280, alignment: .trailing)
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
                    QuickActionChip(icon: "list.bullet.clipboard", title: "检查报告")
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

struct AppImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onPicked: (UIImage) -> Void
        private let dismiss: DismissAction

        init(onPicked: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onPicked = onPicked
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onPicked(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

#Preview {
    ChatHomeView(tabBarVisible: true)
        .environmentObject(PregnancyStore())
}
