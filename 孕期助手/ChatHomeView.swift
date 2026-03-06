import Foundation
import AVFoundation
import Combine
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    enum HomeImageFlowMode: String, CaseIterable {
        case reportImport
        case ingredientScan
        case genericOcrChat

        var title: String {
            switch self {
            case .reportImport:
                return "记录报告单"
            case .ingredientScan:
                return "成分识别"
            case .genericOcrChat:
                return "通用识图问答"
            }
        }

        var cameraModeTitle: String {
            switch self {
            case .reportImport:
                return "报告"
            case .ingredientScan:
                return "成分"
            case .genericOcrChat:
                return "拍一下"
            }
        }

        var cameraHint: String {
            switch self {
            case .reportImport:
                return "对准报告单拍摄，建议包含日期与三项数值。"
            case .ingredientScan:
                return "对准成分表拍摄，尽量拍完整配料文字。"
            case .genericOcrChat:
                return "拍下图片后我会先识图，再按你的问题解读。"
            }
        }
    }

    private enum Formatters {
        static let hhmm: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "HH:mm"
            return formatter
        }()

        static let topDate: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        static let iso8601: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
    }

    private struct AnalysisOverlayState {
        var visible = false
        var title = "图片分析中"
        var stage = "准备中..."
        var current = 0
        var total = 0
        var successCount = 0
        var failedCount = 0

        var progressText: String {
            guard total > 0 else { return "" }
            return "第 \(max(current, 0)) / \(total) 张"
        }
    }

    private struct PregnancyPanelDraft: Identifiable {
        let id = UUID()
        let sourceIndex: Int
        let hcg: Double
        let progesterone: Double
        let estradiol: Double
        var checkDate: Date?

        var checkDateText: String {
            guard let checkDate else { return "未识别日期" }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: checkDate)
        }
    }

    let tabBarVisible: Bool

    @EnvironmentObject private var store: PregnancyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var inputText = ""
    @State private var previousInputTextForSubmit = ""
    @State private var chatMessages: [HomeChatMessage] = []
    @State private var pendingAction: AIPendingAction?
    @State private var showConfirm = false
    @State private var errorText = ""
    @State private var isTyping = false
    @State private var typingStageText = "小助手正在思考…"
    @State private var selectedHomeDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedGuideSnapshot: DailyWarmSnapshot?
    @State private var showGuideDetailSheet = false
    @State private var isTopCardCollapsed = false
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
    @State private var showSmartCameraSheet = false
    @State private var showMultiImagePicker = false
    @State private var showImageFileImporter = false
    @State private var activeImageFlowMode: HomeImageFlowMode = .genericOcrChat
    @State private var analysisOverlay = AnalysisOverlayState()
    @State private var pendingPregnancyPanelDrafts: [PregnancyPanelDraft] = []
    @State private var pendingImageFailMessages: [String] = []
    @State private var showPregnancyPanelDateReview = false
    @State private var composerDockHeight: CGFloat = 0
    @State private var pendingScrollWorkItem: DispatchWorkItem?
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
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10).onEnded { value in
                            if value.translation.height < -16 {
                                isTopCardCollapsed = true
                                inputFocused = false
                            }
                        }
                    )
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        store.refreshForTodayIfNeeded()
                        initializeSessionIfNeeded()
                        selectedHomeDate = Calendar.current.startOfDay(for: Date())
                        refreshHomeHeader(for: selectedHomeDate)
                        triggerBackendWarmupIfNeeded()
                        scrollToBottomStable(proxy, animated: false)
                    }
                    .onChange(of: chatMessages.count) { _ in
                        store.saveHomeChatMessages(chatMessages)
                        scrollToBottomStable(proxy, animated: true)
                    }
                    .onChange(of: isTyping) { _ in
                        scrollToBottomStable(proxy, animated: true)
                    }
                    .onChange(of: inputFocused) { focused in
                        if focused {
                            isTopCardCollapsed = true
                        }
                        scrollToBottomStable(proxy, animated: false)
                    }
                    .onChange(of: tabBarVisible) { _ in
                        scrollToBottomStable(proxy, animated: false)
                    }
                    .onChange(of: composerDockHeight) { _ in
                        scrollToBottomStable(proxy, animated: false)
                    }
                    .onChange(of: selectedHomeDate) { newDate in
                        refreshHomeHeader(for: newDate)
                    }
                    .onChange(of: store.homeSummaryFingerprint()) { _ in
                        refreshHomeHeader(for: selectedHomeDate)
                    }
                    .onChange(of: store.resetEpoch) { _ in
                        clearLocalSessionState()
                        initializeSessionIfNeeded()
                        selectedHomeDate = Calendar.current.startOfDay(for: Date())
                        isTopCardCollapsed = false
                        refreshHomeHeader(for: selectedHomeDate)
                        scrollToBottomStable(proxy, animated: false)
                    }
                    .onChange(of: scenePhase) { newPhase in
                        guard newPhase == .active else { return }
                        refreshHomeHeader(for: selectedHomeDate)
                        scrollToBottomStable(proxy, animated: false)
                    }
                }

                if analysisOverlay.visible {
                    analysisBlockingOverlay
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
                    pendingPregnancyPanelDrafts = []
                }
                Button("确认") {
                    if let pendingAction {
                        let result = store.applyAIAction(pendingAction)
                        chatMessages.append(HomeChatMessage(role: .assistant, kind: .text, text: result))
                        self.pendingAction = nil
                        store.removePendingAction(id: pendingAction.id)
                        pendingPregnancyPanelDrafts = []
                        refreshHomeHeader(for: selectedHomeDate)
                    }
                }
            } message: {
                Text(pendingSummary())
            }
            .fullScreenCover(isPresented: $showSmartCameraSheet) {
                ChatSmartCameraSheet(
                    selectedMode: $activeImageFlowMode,
                    onClose: {
                        showSmartCameraSheet = false
                    },
                    onPickAlbum: {
                        showSmartCameraSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showMultiImagePicker = true
                        }
                    },
                    onPickFile: {
                        showSmartCameraSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showImageFileImporter = true
                        }
                    },
                    onCapture: { image in
                        let mode = activeImageFlowMode
                        showSmartCameraSheet = false
                        Task {
                            await processPickedImages([image], mode: mode)
                        }
                    }
                )
            }
            .sheet(isPresented: $showMultiImagePicker) {
                ChatMultiImagePicker(selectionLimit: 0) { images in
                    let mode = activeImageFlowMode
                    Task {
                        await processPickedImages(images, mode: mode)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImageFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                handleImageFileImportResult(result)
            }
            .sheet(isPresented: $showPregnancyPanelDateReview) {
                pregnancyPanelDateReviewSheet
            }
            .sheet(isPresented: $showGuideDetailSheet) {
                guideDetailSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onDisappear {
                resetVoiceState(stopRecognition: true)
                store.saveHomeChatMessages(chatMessages)
            }
            .onChange(of: inputText) { newValue in
                handlePotentialKeyboardSend(previous: previousInputTextForSubmit, current: newValue)
                previousInputTextForSubmit = newValue
            }
        }
    }

    private var conversationSection: some View {
        return VStack(alignment: .leading, spacing: 10) {
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

    private var selectedGuide: DailyWarmSnapshot {
        selectedGuideSnapshot ?? store.dailyWarmSnapshot(for: selectedHomeDate)
    }

    private var isTodaySelected: Bool {
        Calendar.current.isDate(selectedHomeDate, inSameDayAs: Date())
    }

    private var collapsedTopHint: String {
        let medicalItems = store.todayTimelineItems(scope: .medical, includeCompleted: true, now: selectedHomeDate)
        if medicalItems.isEmpty {
            return "今日暂无医疗安排"
        }
        return "今日医疗安排 \(medicalItems.count) 项"
    }

    private var topFixedInfoBar: some View {
        let guide = selectedGuide
        let weight = store.weeklyWeightSummary(for: selectedHomeDate)
        let medicalItems = store.todayTimelineItems(scope: .medical, includeCompleted: true, now: selectedHomeDate)
        let pendingCount = medicalItems.filter { !$0.isCompleted }.count
        let topDateTitle = "孕\(store.gestationalWeekText(for: selectedHomeDate)) · \(store.homeDisplayDateText(for: selectedHomeDate))"
        let dueDateText = "预产期：\(store.formatDate(store.dueDate))（\(store.daysToDueText(on: selectedHomeDate))）"

        return VStack(alignment: .leading, spacing: 8) {
            Text("孕期健康伙伴")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)

            if isTopCardCollapsed {
                HStack(spacing: 8) {
                    Text("\(topDateTitle) · \(collapsedTopHint)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if !isTodaySelected {
                        Button {
                            selectedHomeDate = Calendar.current.startOfDay(for: Date())
                        } label: {
                            Text("回今天")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.actionPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.75))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .appTapTarget()
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textHint)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "FFE8F2"),
                                    Color(hex: "FFD8E9")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Button {
                            shiftSelectedHomeDate(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.actionPrimary)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .appTapTarget()

                        Text(topDateTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .lineLimit(1)

                        if !isTodaySelected {
                            Button {
                                selectedHomeDate = Calendar.current.startOfDay(for: Date())
                            } label: {
                                Text("回今天")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.actionPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.72))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .appTapTarget()
                        }

                        Button {
                            shiftSelectedHomeDate(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.actionPrimary)
                                .frame(width: 30, height: 30)
                                .background(Color.white.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .appTapTarget()
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 15).onEnded { value in
                            if value.translation.width < -26 {
                                shiftSelectedHomeDate(by: 1)
                            } else if value.translation.width > 26 {
                                shiftSelectedHomeDate(by: -1)
                            }
                        }
                    )

                    Text(dueDateText)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(weight.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(weight.detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Button {
                        showGuideDetailSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            guideSummaryRow(icon: "figure.and.child.holdinghands", title: "宝宝变化", text: guide.babyChange)
                            guideSummaryRow(icon: "figure.walk", title: "妈妈变化", text: guide.momChange)
                        }
                    }
                    .buttonStyle(.plain)
                    .appTapTarget()

                    Text("当日医疗待办：\(pendingCount) 项")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "FFE8F2"),
                                    Color(hex: "FFD8E9"),
                                    Color(hex: "FFCFE1")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(AppTheme.background.opacity(0.98))
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                inputFocused = false
                if isTopCardCollapsed {
                    isTopCardCollapsed = false
                }
            }
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.borderLight)
                .frame(height: 1)
        }
    }

    private var guideDetailSheet: some View {
        let weekGuide = store.weeklyWarmSnapshot(for: selectedHomeDate)
        let title = "孕\(weekGuide.week)周详情"

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.homeDisplayDateText(for: selectedHomeDate))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textHint)

                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("宝宝本周状况")
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(weekGuide.babyWeekSummary)
                                .font(.body)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("发育数据")
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("身长：\(weekGuide.growthLengthCM)")
                                Text("体重：\(weekGuide.growthWeightG)")
                                Text("大小类比：\(weekGuide.growthAnalogy)")
                            }
                            .font(.body)
                            .foregroundStyle(AppTheme.textSecondary)
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("妈妈的状况与建议")
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(weekGuide.momWeekSummary)
                                .font(.body)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        showGuideDetailSheet = false
                    }
                }
            }
        }
    }

    private func guideSummaryRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.actionPrimary)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var analysisBlockingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text(analysisOverlay.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(analysisOverlay.stage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                if !analysisOverlay.progressText.isEmpty {
                    Text(analysisOverlay.progressText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textHint)
                }
                if analysisOverlay.successCount > 0 || analysisOverlay.failedCount > 0 {
                    Text("成功 \(analysisOverlay.successCount) 张 · 失败 \(analysisOverlay.failedCount) 张")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.borderLight, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
        .zIndex(999)
    }

    private func shiftSelectedHomeDate(by days: Int) {
        guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: selectedHomeDate) else {
            return
        }
        selectedHomeDate = Calendar.current.startOfDay(for: shifted)
    }

    private var hasMissingDraftDate: Bool {
        pendingPregnancyPanelDrafts.contains { $0.checkDate == nil }
    }

    private var pregnancyPanelDateReviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("有部分报告未识别到日期，请先补全日期再保存。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)

                    ForEach(Array(pendingPregnancyPanelDrafts.enumerated()), id: \.element.id) { index, draft in
                        AppCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("第\(draft.sourceIndex)张报告")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text("HCG \(formatLabValue(draft.hcg)) · 孕酮 \(formatLabValue(draft.progesterone)) · E2 \(formatLabValue(draft.estradiol))")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)

                                if draft.checkDate == nil {
                                    AppDateField(
                                        "报告日期",
                                        selection: Binding(
                                            get: { pendingPregnancyPanelDrafts[index].checkDate ?? Date() },
                                            set: { pendingPregnancyPanelDrafts[index].checkDate = $0 }
                                        ),
                                        titleWidth: 72,
                                        displayFormat: "yyyy年M月d日"
                                    )
                                } else if let checkDate = draft.checkDate {
                                    Text("报告日期：\(isoDateText(checkDate))")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .navigationTitle("导入前校对")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showPregnancyPanelDateReview = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("继续保存") {
                        queuePregnancyPanelDraftsForConfirmation()
                    }
                    .disabled(hasMissingDraftDate)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
            beginImageFlow(.genericOcrChat)
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
    }

    private func clearLocalSessionState() {
        resetVoiceState(stopRecognition: true)
        inputText = ""
        previousInputTextForSubmit = ""
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
        showSmartCameraSheet = false
        showMultiImagePicker = false
        showImageFileImporter = false
        activeImageFlowMode = .genericOcrChat
        analysisOverlay = AnalysisOverlayState()
        pendingPregnancyPanelDrafts = []
        pendingImageFailMessages = []
        showPregnancyPanelDateReview = false
        showGuideDetailSheet = false
        selectedGuideSnapshot = nil
        isTopCardCollapsed = false
        pendingScrollWorkItem?.cancel()
        pendingScrollWorkItem = nil
    }

    private func handleImageFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            errorText = "文件读取失败了，请重试一次。"
        case .success(let urls):
            guard !urls.isEmpty else { return }
            let mode = activeImageFlowMode
            Task {
                let images = loadImagesFromFiles(urls)
                guard !images.isEmpty else {
                    errorText = "这些文件暂时不是可识别的图片，请换图片文件再试。"
                    return
                }
                await processPickedImages(images, mode: mode)
            }
        }
    }

    private func loadImagesFromFiles(_ urls: [URL]) -> [UIImage] {
        urls.compactMap { url in
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if let image = UIImage(contentsOfFile: url.path) {
                return image
            }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                return nil
            }
            return UIImage(data: data)
        }
    }

    private func refreshHomeHeader(for date: Date) {
        selectedGuideSnapshot = store.dailyWarmSnapshot(for: date)
    }

    private func restorePendingActionIfNeeded() {
        if pendingAction != nil { return }
        guard let lastPending = store.aiPendingActions().last else { return }
        pendingAction = lastPending
        showConfirm = true
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

        if command.title == "成分识别" {
            inputFocused = false
            beginImageFlow(.ingredientScan)
            return
        }

        if command.title == "今日安排" {
            let dateText = store.homeDisplayDateText(for: selectedHomeDate)
            let customPrompt = "请汇总我\(dateText)需要注意的安排：用药、打针、回诊和其他提醒。"
            Task {
                await submitUserInput(customPrompt)
            }
            return
        }

        Task {
            await submitUserInput(prompt)
        }
    }

    private func beginImageFlow(_ mode: HomeImageFlowMode) {
        activeImageFlowMode = mode
        inputFocused = false
        showSmartCameraSheet = true
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
            errorText = "这段语音我没听清，我们再试一次。"
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

    private func processPickedImages(_ images: [UIImage], mode: HomeImageFlowMode) async {
        guard !isTyping else { return }
        let validImages = images
        guard !validImages.isEmpty else { return }

        errorText = ""
        pendingImageFailMessages = []
        ocrProcessingState = .processing

        switch mode {
        case .reportImport:
            await processReportImportImages(validImages)
        case .ingredientScan:
            await processIngredientImages(validImages)
        case .genericOcrChat:
            await processGenericOCRImages(validImages)
        }

        if case .processing = ocrProcessingState {
            ocrProcessingState = .idle
        }
    }

    private func processReportImportImages(_ images: [UIImage]) async {
        showAnalysisOverlay(title: "报告分析中", stage: "OCR识别中", current: 0, total: images.count)

        var recognizedTexts: [String] = []
        var sourceIndexes: [Int] = []
        var failedMessages: [String] = []

        for (index, image) in images.enumerated() {
            updateAnalysisOverlay(stage: "OCR识别中", current: index + 1, total: images.count)
            do {
                let recognized = try await ImageOCRService.recognizeText(from: image)
                let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    failedMessages.append("第\(index + 1)张：OCR 未识别到有效文本")
                    continue
                }
                recognizedTexts.append(trimmed)
                sourceIndexes.append(index + 1)
                analysisOverlay.successCount += 1
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "识别失败"
                failedMessages.append("第\(index + 1)张：\(message)")
                analysisOverlay.failedCount += 1
            }
        }

        guard !recognizedTexts.isEmpty else {
            hideAnalysisOverlay()
            ocrProcessingState = .failed("未识别到可保存的检查报告，请重试。")
            errorText = failedMessages.joined(separator: "；")
            return
        }

        updateAnalysisOverlay(stage: "结构化提取中", current: recognizedTexts.count, total: recognizedTexts.count)

        do {
            let config = store.currentAIConfig()
            guard !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                hideAnalysisOverlay()
                ocrProcessingState = .failed("AI 服务未配置")
                errorText = "AI 服务还没配置好，请先补充后端地址。"
                return
            }

            let grouped = try await chatService.groupPregnancyPanelReports(
                config: config,
                ocrTexts: recognizedTexts,
                nowISO8601: Self.Formatters.iso8601.string(from: Date())
            )
            updateAnalysisOverlay(stage: "分组判定中", current: recognizedTexts.count, total: recognizedTexts.count)

            let drafts = grouped.records.enumerated().map { offset, record in
                let sourceLabel: Int
                if let first = record.source_indexes?.first, first >= 0, first < sourceIndexes.count {
                    sourceLabel = sourceIndexes[first]
                } else if offset < sourceIndexes.count {
                    sourceLabel = sourceIndexes[offset]
                } else {
                    sourceLabel = offset + 1
                }
                return PregnancyPanelDraft(
                    sourceIndex: sourceLabel,
                    hcg: record.hcg,
                    progesterone: record.progesterone,
                    estradiol: record.estradiol,
                    checkDate: parseOCRDate(record.check_date)
                )
            }

            grouped.failed_indexes.forEach { failedIdx in
                let display: Int
                if failedIdx >= 0, failedIdx < sourceIndexes.count {
                    display = sourceIndexes[failedIdx]
                } else {
                    display = min(max(failedIdx + 1, 1), images.count)
                }
                failedMessages.append("第\(display)张：未提取到完整妊娠三项")
            }

            hideAnalysisOverlay()

            guard !drafts.isEmpty else {
                ocrProcessingState = .failed("未识别到可保存的妊娠三项报告。")
                errorText = failedMessages.isEmpty ? "未识别到可保存的妊娠三项报告。" : failedMessages.joined(separator: "；")
                return
            }

            pendingPregnancyPanelDrafts = drafts
            pendingImageFailMessages = failedMessages
            if drafts.contains(where: { $0.checkDate == nil }) {
                showPregnancyPanelDateReview = true
            } else {
                queuePregnancyPanelDraftsForConfirmation()
            }
            if !failedMessages.isEmpty {
                errorText = "已识别 \(drafts.count) 条，\(failedMessages.count) 张失败。"
            }
        } catch {
            hideAnalysisOverlay()
            let mapped = AIRequestError.map(error)
            ocrProcessingState = .failed(mapped.userMessage)
            errorText = mapped.userMessage
        }
    }

    private func processIngredientImages(_ images: [UIImage]) async {
        showAnalysisOverlay(title: "成分识别中", stage: "OCR识别中", current: 0, total: images.count)

        var recognizedTexts: [String] = []
        var failedMessages: [String] = []

        for (index, image) in images.enumerated() {
            updateAnalysisOverlay(stage: "OCR识别中", current: index + 1, total: images.count)
            do {
                let recognized = try await ImageOCRService.recognizeText(from: image)
                let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    failedMessages.append("第\(index + 1)张：OCR 未识别到有效文本")
                    continue
                }
                recognizedTexts.append(trimmed)
                analysisOverlay.successCount += 1
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "识别失败"
                failedMessages.append("第\(index + 1)张：\(message)")
                analysisOverlay.failedCount += 1
            }
        }

        guard !recognizedTexts.isEmpty else {
            hideAnalysisOverlay()
            ocrProcessingState = .failed("未识别到可分析的成分文本。")
            errorText = failedMessages.joined(separator: "；")
            return
        }

        updateAnalysisOverlay(stage: "风险分级中", current: recognizedTexts.count, total: recognizedTexts.count)

        do {
            let config = store.currentAIConfig()
            guard !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                hideAnalysisOverlay()
                ocrProcessingState = .failed("AI 服务未配置")
                errorText = "AI 服务还没配置好，请先补充后端地址。"
                return
            }

            let result = try await chatService.analyzeIngredients(
                config: config,
                ocrTexts: recognizedTexts,
                profileContext: store.aiContextSummary(for: selectedHomeDate)
            )
            hideAnalysisOverlay()
            let text = ingredientResultText(result)
            chatMessages.append(HomeChatMessage(role: .assistant, kind: .text, text: text))
            if !failedMessages.isEmpty {
                errorText = "已识别 \(recognizedTexts.count) 张，\(failedMessages.count) 张失败。"
            }
        } catch {
            hideAnalysisOverlay()
            let mapped = AIRequestError.map(error)
            ocrProcessingState = .failed(mapped.userMessage)
            errorText = mapped.userMessage
        }
    }

    private func processGenericOCRImages(_ images: [UIImage]) async {
        showAnalysisOverlay(title: "识图处理中", stage: "OCR识别中", current: 0, total: images.count)
        var recognizedTexts: [String] = []
        var failedMessages: [String] = []

        for (index, image) in images.enumerated() {
            updateAnalysisOverlay(stage: "OCR识别中", current: index + 1, total: images.count)
            do {
                let recognized = try await ImageOCRService.recognizeText(from: image)
                let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    failedMessages.append("第\(index + 1)张：OCR 未识别到有效文本")
                    continue
                }
                recognizedTexts.append(trimmed)
                analysisOverlay.successCount += 1
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "识别失败"
                failedMessages.append("第\(index + 1)张：\(message)")
                analysisOverlay.failedCount += 1
            }
        }

        hideAnalysisOverlay()

        guard !recognizedTexts.isEmpty else {
            ocrProcessingState = .failed("未识别到有效文本，请重试。")
            errorText = failedMessages.joined(separator: "；")
            return
        }

        let userQuestion = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userQuestion.isEmpty {
            inputText = ""
        }
        let ocrPayload = recognizedTexts.enumerated().map { index, text in
            "图片\(index + 1)：\n\(text)"
        }.joined(separator: "\n\n")
        let promptPrefix = userQuestion.isEmpty ? "请根据我上传的图片内容进行解读：" : "\(userQuestion)\n请结合以下图片识别文本回答："
        let prompt = "\(promptPrefix)\n\n\(ocrPayload)"

        await submitUserInput(prompt)
        if !failedMessages.isEmpty {
            errorText = "已识别 \(recognizedTexts.count) 张，\(failedMessages.count) 张失败。"
        }
    }

    private func showAnalysisOverlay(title: String, stage: String, current: Int, total: Int) {
        analysisOverlay.visible = true
        analysisOverlay.title = title
        analysisOverlay.stage = stage
        analysisOverlay.current = current
        analysisOverlay.total = total
        analysisOverlay.successCount = 0
        analysisOverlay.failedCount = 0
    }

    private func updateAnalysisOverlay(stage: String, current: Int, total: Int) {
        analysisOverlay.stage = stage
        analysisOverlay.current = current
        analysisOverlay.total = total
    }

    private func hideAnalysisOverlay() {
        analysisOverlay.visible = false
    }

    private func ingredientResultText(_ result: AIBackendChatService.IngredientAnalyzeResponse) -> String {
        var lines: [String] = []
        lines.append("成分识别结论：\(result.overall)")
        if !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(result.summary)
        }

        func section(_ title: String, _ items: [AIBackendChatService.IngredientEvidenceItem]) {
            guard !items.isEmpty else { return }
            lines.append("\(title)：")
            for item in items.prefix(5) {
                let reason = item.reason.trimmingCharacters(in: .whitespacesAndNewlines)
                if reason.isEmpty {
                    lines.append("• \(item.name)")
                } else {
                    lines.append("• \(item.name)：\(reason)")
                }
            }
        }

        section("可用", result.usable)
        section("谨慎", result.caution)
        section("避免", result.avoid)

        if !result.alternatives.isEmpty {
            lines.append("可替代建议：\(result.alternatives.prefix(3).joined(separator: "；"))")
        }

        let disclaimer = result.disclaimer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !disclaimer.isEmpty {
            lines.append(disclaimer)
        }
        return lines.joined(separator: "\n")
    }

    private func queuePregnancyPanelDraftsForConfirmation() {
        guard !pendingPregnancyPanelDrafts.isEmpty else { return }
        let readyDrafts = pendingPregnancyPanelDrafts.filter { $0.checkDate != nil }
        guard !readyDrafts.isEmpty else {
            errorText = "还有报告日期没补全，先完成校对再保存哦。"
            return
        }

        let records: [[String: String]] = readyDrafts.compactMap { draft in
            guard let checkDate = draft.checkDate else { return nil }
            return [
                "check_type": "pregnancy_panel",
                "hcg": String(draft.hcg),
                "progesterone": String(draft.progesterone),
                "estradiol": String(draft.estradiol),
                "check_date": isoDateText(checkDate)
            ]
        }
        guard !records.isEmpty else {
            errorText = "这次还没生成可保存的检查记录，我们再试一次。"
            return
        }

        guard let data = try? JSONSerialization.data(withJSONObject: records, options: []),
              let payload = String(data: data, encoding: .utf8) else {
            errorText = "整理检查记录时出了一点问题，请再试一次。"
            return
        }

        let pending = AIPendingAction(
            id: UUID().uuidString,
            intent: "create_check_record",
            slots: ["check_records": payload],
            createdAt: Date()
        )
        pendingAction = pending
        showConfirm = true
        store.appendPendingAction(pending)
        showPregnancyPanelDateReview = false
    }

    private func extractPregnancyPanelDraft(from recognizedText: String, sourceIndex: Int) async -> PregnancyPanelDraft? {
        if let aiDraft = await extractPregnancyPanelDraftViaAI(from: recognizedText, sourceIndex: sourceIndex) {
            return aiDraft
        }
        return extractPregnancyPanelDraftViaRegex(from: recognizedText, sourceIndex: sourceIndex)
    }

    private func extractPregnancyPanelDraftViaAI(from recognizedText: String, sourceIndex: Int) async -> PregnancyPanelDraft? {
        let config = store.currentAIConfig()
        guard !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let prompt = """
        你是医学报告结构化助手。请从以下 OCR 文本里提取妊娠三项和报告日期，只返回 JSON，不要解释。
        JSON 模板：
        {
          "intent": "create_check_record",
          "slots": {
            "check_type": "pregnancy_panel",
            "hcg": "",
            "progesterone": "",
            "estradiol": "",
            "check_date": ""
          },
          "need_clarify": false,
          "clarify_question": "",
          "assistant_reply": ""
        }
        OCR 文本：
        \(recognizedText)
        """

        do {
            let jsonText = try await chatService.sendWithRecovery(
                config: config,
                context: "妊娠三项图片结构化提取",
                history: [],
                userInput: prompt,
                onStage: nil
            )
            guard let action = AIParse.parse(jsonText) else { return nil }
            let hcg = parseLabNumeric(action.slots["hcg"])
            let progesterone = parseLabNumeric(action.slots["progesterone"])
            let estradiol = parseLabNumeric(action.slots["estradiol"])
            guard let hcg, let progesterone, let estradiol else { return nil }

            let checkDate = parseOCRDate(action.slots["check_date"])
            return PregnancyPanelDraft(
                sourceIndex: sourceIndex,
                hcg: hcg,
                progesterone: progesterone,
                estradiol: estradiol,
                checkDate: checkDate
            )
        } catch {
            return nil
        }
    }

    private func extractPregnancyPanelDraftViaRegex(from text: String, sourceIndex: Int) -> PregnancyPanelDraft? {
        let hcgText = firstRegexCapture(in: text, pattern: #"(?i)(?:β-?hcg|hcg)[^0-9]{0,20}([0-9]+(?:\.[0-9]+)?)"#)
            ?? firstRegexCapture(in: text, pattern: #"HCG[:：\s]*([0-9]+(?:\.[0-9]+)?)"#)
        let progesteroneText = firstRegexCapture(in: text, pattern: #"孕酮[^0-9]{0,20}([0-9]+(?:\.[0-9]+)?)"#)
            ?? firstRegexCapture(in: text, pattern: #"(?i)progesterone[^0-9]{0,20}([0-9]+(?:\.[0-9]+)?)"#)
        let estradiolText = firstRegexCapture(in: text, pattern: #"雌二醇[^0-9]{0,20}([0-9]+(?:\.[0-9]+)?)"#)
            ?? firstRegexCapture(in: text, pattern: #"(?i)(?:\bE2\b|estradiol)[^0-9]{0,20}([0-9]+(?:\.[0-9]+)?)"#)

        guard let hcg = parseLabNumeric(hcgText),
              let progesterone = parseLabNumeric(progesteroneText),
              let estradiol = parseLabNumeric(estradiolText) else {
            return nil
        }

        let dateCandidate = firstRegexCapture(in: text, pattern: #"(20\d{2}\s*[年/\-\.]\s*\d{1,2}\s*[月/\-\.]\s*\d{1,2}\s*日?)"#)
            ?? firstRegexCapture(in: text, pattern: #"(\d{1,2}\s*[月/\-\.]\s*\d{1,2}\s*日?)"#)

        return PregnancyPanelDraft(
            sourceIndex: sourceIndex,
            hcg: hcg,
            progesterone: progesterone,
            estradiol: estradiol,
            checkDate: parseOCRDate(dateCandidate)
        )
    }

    private func parseLabNumeric(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let normalized = raw.replacingOccurrences(of: ",", with: "")
        if let direct = Double(normalized.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return direct
        }
        guard let capture = firstRegexCapture(in: normalized, pattern: #"([-+]?\d+(?:\.\d+)?)"#) else {
            return nil
        }
        return Double(capture)
    }

    private func parseOCRDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"(?:(\d{4})\s*[年/\-\.])?\s*(\d{1,2})\s*[月/\-\.]\s*(\d{1,2})\s*日?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else { return nil }

        let year = intCapture(match: match, group: 1, source: trimmed) ?? Calendar.current.component(.year, from: Date())
        guard let month = intCapture(match: match, group: 2, source: trimmed),
              let day = intCapture(match: match, group: 3, source: trimmed) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

    private func intCapture(match: NSTextCheckingResult, group: Int, source: String) -> Int? {
        guard group < match.numberOfRanges else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: source) else { return nil }
        return Int(source[swiftRange])
    }

    private func isoDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatLabValue(_ value: Double) -> String {
        String(format: "%.2f", value)
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
                context: store.aiContextSummary(for: selectedHomeDate),
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

    private func scrollToBottomStable(_ proxy: ScrollViewProxy, animated: Bool) {
        scrollToBottom(proxy, animated: animated)
        pendingScrollWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            scrollToBottom(proxy, animated: animated)
        }
        pendingScrollWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if reduceMotion || !animated {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    private func timeLabel(_ date: Date) -> String {
        Self.Formatters.hhmm.string(from: date)
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
            if let preview = checkRecordBatchPreview(from: pendingAction.slots), preview.count > 1 {
                if preview.dates.isEmpty {
                    return "保存检查报告 \(preview.count) 条"
                }
                let previewDates = preview.dates.joined(separator: "、")
                let tail = preview.count > preview.dates.count ? " 等" : ""
                return "保存检查报告 \(preview.count) 条（\(previewDates)\(tail)）"
            }
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

    private func checkRecordBatchPreview(from slots: [String: String]) -> (count: Int, dates: [String])? {
        guard let raw = slots["check_records"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        let list: [[String: Any]]
        if let array = json as? [[String: Any]] {
            list = array
        } else if let dict = json as? [String: Any], let nested = dict["records"] as? [[String: Any]] {
            list = nested
        } else {
            return nil
        }

        let dates = list.compactMap { item in
            firstNonEmptyString(item["check_date"], item["date"])
        }
        guard !dates.isEmpty else {
            return (list.count, [])
        }
        return (list.count, Array(dates.prefix(3)))
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
        let (date, label) = dateFromSemantic(semantic, fallback: selectedHomeDate)
        let sections = store.medicationSections(for: date)
        let injectionDue = store.isInjectionDue(on: date)
        let appointmentLines = scheduleAppointmentLines(on: date)

        if sections.isEmpty && !injectionDue && appointmentLines.isEmpty {
            return "\(label)暂无已记录安排。"
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
            return "用药 · \(section.title)：\(names)"
        }
        if injectionDue {
            let detail = store.state.injectionPlan.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                lines.append("打针：\(store.state.injectionPlan.title)")
            } else {
                lines.append("打针：\(store.state.injectionPlan.title)（\(detail)）")
            }
        }
        lines.append(contentsOf: appointmentLines)

        return "\(label)安排：\n" + lines.joined(separator: "\n")
    }

    private func scheduleAppointmentLines(on date: Date) -> [String] {
        let sameDayAppointments = store.activeAppointments
            .filter { appointment in
                !appointment.isDone && Calendar.current.isDate(appointment.dueDate, inSameDayAs: date)
            }
            .sorted { $0.dueDate < $1.dueDate }

        return sameDayAppointments.map { appointment in
            let timeText = store.appointmentTimeText(appointment.dueDate)
            let detail = appointment.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "复诊：\(timeText) \(appointment.title)"
            }
            return "复诊：\(timeText) \(appointment.title)（\(detail)）"
        }
    }

    private func dateFromSemantic(_ text: String, fallback: Date) -> (date: Date, label: String) {
        let calendar = Calendar.current
        if text.contains("明天") || text.contains("明日") || text.lowercased().contains("tomorrow") {
            let date = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            return (date, "明天")
        }
        if text.contains("后天") {
            let date = calendar.date(byAdding: .day, value: 2, to: Date()) ?? Date()
            return (date, "后天")
        }
        if let parsedDate = parseOCRDate(text) {
            return (parsedDate, store.homeDisplayDateText(for: parsedDate))
        }
        return (fallback, store.homeDisplayDateText(for: fallback))
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

struct ChatSmartCameraSheet: View {
    @Binding var selectedMode: ChatHomeView.HomeImageFlowMode
    let onClose: () -> Void
    let onPickAlbum: () -> Void
    let onPickFile: () -> Void
    let onCapture: (UIImage) -> Void

    @StateObject private var camera = ChatCameraCaptureController()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            Group {
                if camera.permissionDenied {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("相机权限未开启")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("你可以先用相册或文件导入图片继续识别。")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                } else if camera.isConfigured {
                    ChatCameraPreview(session: camera.session)
                        .ignoresSafeArea()
                } else {
                    ProgressView("相机启动中…")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 16).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    guard abs(value.translation.width) > 28 else { return }
                    shiftMode(value.translation.width < 0 ? 1 : -1)
                }
            )

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomPanel
            }
        }
        .statusBarHidden(true)
        .onAppear {
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text("AI 智能相机")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            modeSelector

            Text(selectedMode.cameraHint)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: 36) {
                actionButton(icon: "photo.on.rectangle.angled", title: "相册", action: onPickAlbum)
                captureButton
                actionButton(icon: "doc", title: "文件", action: onPickFile)
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var modeSelector: some View {
        HStack(spacing: 12) {
            ForEach(ChatHomeView.HomeImageFlowMode.allCases, id: \.self) { mode in
                let selected = mode == selectedMode
                Button {
                    selectedMode = mode
                } label: {
                    Text(mode.cameraModeTitle)
                        .font(.system(size: 18, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? AppTheme.actionPrimary : AppTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? AppTheme.accentSoft : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var captureButton: some View {
        Button {
            camera.capturePhoto { image in
                guard let image else { return }
                onCapture(image)
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(AppTheme.actionPrimary.opacity(0.25), lineWidth: 8)
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.actionPrimary, AppTheme.accentBrand],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 66, height: 66)
            }
        }
        .buttonStyle(.plain)
        .disabled(!camera.canCapture)
        .opacity(camera.canCapture ? 1 : 0.55)
    }

    private func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color(hex: "1F2559"))
                    .frame(width: 44, height: 44)
                    .background(Color(hex: "EEF0FF"))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: "1F2559"))
            }
        }
        .buttonStyle(.plain)
    }

    private func shiftMode(_ offset: Int) {
        let modes = ChatHomeView.HomeImageFlowMode.allCases
        guard let currentIndex = modes.firstIndex(of: selectedMode) else { return }
        let nextIndex = min(max(currentIndex + offset, 0), modes.count - 1)
        selectedMode = modes[nextIndex]
    }
}

final class ChatCameraCaptureController: NSObject, ObservableObject {
    @Published private(set) var permissionDenied = false
    @Published private(set) var isConfigured = false
    @Published private(set) var canCapture = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "chat.smart.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var didSetup = false
    private var captureCompletion: ((UIImage?) -> Void)?
}

extension ChatCameraCaptureController {
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.permissionDenied = !granted
                }
                guard granted else { return }
                self.configureAndStartSession()
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.didSetup else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            self.captureCompletion = completion
            let settings = AVCapturePhotoSettings()
            if self.photoOutput.supportedFlashModes.contains(.auto) {
                settings.flashMode = .auto
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.didSetup {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: camera),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.permissionDenied = true
                    }
                    return
                }
                self.session.addInput(input)

                guard self.session.canAddOutput(self.photoOutput) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.permissionDenied = true
                    }
                    return
                }
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                self.session.commitConfiguration()
                self.didSetup = true
                DispatchQueue.main.async {
                    self.isConfigured = true
                    self.canCapture = true
                }
            }

            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }
}

extension ChatCameraCaptureController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let completion = captureCompletion
        captureCompletion = nil

        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                completion?(nil)
            }
            return
        }
        DispatchQueue.main.async {
            completion?(image)
        }
    }
}

struct ChatCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
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

struct ChatMultiImagePicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onPicked: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, dismiss: dismiss)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: ([UIImage]) -> Void
        private let dismiss: DismissAction

        init(onPicked: @escaping ([UIImage]) -> Void, dismiss: DismissAction) {
            self.onPicked = onPicked
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                dismiss()
                return
            }

            var images = Array<UIImage?>(repeating: nil, count: results.count)
            let group = DispatchGroup()

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    if let image = object as? UIImage {
                        images[index] = image
                    }
                }
            }

            group.notify(queue: .main) {
                self.onPicked(images.compactMap { $0 })
                self.dismiss()
            }
        }
    }
}

#Preview {
    ChatHomeView(tabBarVisible: true)
        .environmentObject(PregnancyStore())
}
