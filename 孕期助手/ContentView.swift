import SwiftUI
import UIKit

enum MainTab: Hashable {
    case home
    case records
    case profile
}

struct ContentView: View {
    @EnvironmentObject private var store: PregnancyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: MainTab = .home
    @State private var isKeyboardVisible = false
    @State private var isReminderSyncing = false
    @State private var hasPendingReminderSync = false
    @State private var lastSyncedReminderRevision = 0

    var body: some View {
        ZStack {
            ChatHomeView(tabBarVisible: selectedTab == .home && !isKeyboardVisible)
                .opacity(selectedTab == .home ? 1 : 0)
                .allowsHitTesting(selectedTab == .home)
                .accessibilityHidden(selectedTab != .home)

            CheckListView()
                .opacity(selectedTab == .records ? 1 : 0)
                .allowsHitTesting(selectedTab == .records)
                .accessibilityHidden(selectedTab != .records)

            ProfileView()
                .opacity(selectedTab == .profile ? 1 : 0)
                .allowsHitTesting(selectedTab == .profile)
                .accessibilityHidden(selectedTab != .profile)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isKeyboardVisible {
                customTabBar
            }
        }
        .overlay(alignment: .top) {
            if let banner = store.globalBanner {
                GlobalBannerBar(banner: banner) {
                    store.dismissGlobalBanner()
                }
                .padding(.top, 6)
                .padding(.horizontal, 12)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.globalBanner?.id)
        .onAppear {
            syncRemindersIfNeeded()
        }
        .onChange(of: store.reminderSyncRevision) { _, _ in
            syncRemindersIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            handleKeyboardFrameChange(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            setKeyboardVisibility(false)
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabItemButton(tab: .home, title: "首页", icon: "house.fill")
            tabItemButton(tab: .records, title: "记录", icon: "list.bullet.rectangle.portrait.fill")
            tabItemButton(tab: .profile, title: "我的", icon: "person.crop.circle.fill")
        }
        .frame(height: AppLayout.mainTabBarHeight)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Color.white.opacity(0.66)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: -4)
        }
        .zIndex(50)
        .overlay(alignment: .top) {
            // 顶部高光线
            LinearGradient(
                colors: [.white.opacity(0.3), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 1)
        }
    }

    private func tabItemButton(tab: MainTab, title: String, icon: String) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(selected ? AppTheme.actionPrimary : AppTheme.textSecondary)
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? AppTheme.actionPrimary : AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appTapTarget(minHeight: AppLayout.mainTabBarHeight)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func syncRemindersIfNeeded() {
        let currentRevision = store.reminderSyncRevision
        guard currentRevision > lastSyncedReminderRevision else { return }

        if isReminderSyncing {
            hasPendingReminderSync = true
            return
        }

        isReminderSyncing = true

        Task {
            let revisionSnapshot = store.reminderSyncRevision
            let outcome = await ReminderSyncCoordinator.sync(using: store)

            await MainActor.run {
                lastSyncedReminderRevision = max(lastSyncedReminderRevision, revisionSnapshot)
                isReminderSyncing = false

                switch outcome {
                case .localPermissionDenied:
                    store.showGlobalBanner(message: "未开启通知权限，提醒未更新。", level: .error)
                case .localFailed(let reason):
                    store.showGlobalBanner(message: "提醒更新失败：\(reason)", level: .error)
                case .localSuccess(let system):
                    switch system {
                    case .skippedDisabled:
                        store.showGlobalBanner(message: "提醒已自动更新。", level: .success)
                    case .success:
                        store.showGlobalBanner(message: "提醒已更新（通知+提醒事项）。", level: .success)
                    case .permissionDenied:
                        store.showGlobalBanner(message: "通知已更新，未授予提醒事项权限。", level: .info)
                    case .failed:
                        store.showGlobalBanner(message: "通知已更新，提醒事项同步失败。", level: .info)
                    }
                }

                if hasPendingReminderSync {
                    hasPendingReminderSync = false
                    syncRemindersIfNeeded()
                }
            }
        }
    }

    private func handleKeyboardFrameChange(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }

        // Keyboard is considered visible when its end frame intersects the screen.
        let screenHeight = UIScreen.main.bounds.height
        let keyboardVisible = endFrame.minY < (screenHeight - 1)
        setKeyboardVisibility(keyboardVisible)
    }

    private func setKeyboardVisibility(_ visible: Bool) {
        guard visible != isKeyboardVisible else { return }
        if reduceMotion {
            isKeyboardVisible = visible
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                isKeyboardVisible = visible
            }
        }
    }
}

struct GlobalBannerBar: View {
    let banner: GlobalBanner
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption.weight(.bold))
            Text(banner.message)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
    }

    private var iconName: String {
        switch banner.level {
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var backgroundColor: Color {
        switch banner.level {
        case .success:
            return AppTheme.bannerSuccess
        case .info:
            return AppTheme.bannerInfo
        case .error:
            return AppTheme.bannerError
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: PregnancyStore
    @State private var draft: Profile?
    @State private var relationName = ""
    @State private var relationPhone = ""
    @State private var inviteCodePlaceholder = "INVITE-准备中"
    @State private var showResetAllDataDialog = false
    @State private var isResettingAllData = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        profileHeaderCard
                            .padding(.horizontal)

                        profileSection(title: "基础信息") {
                            AppCard {
                                VStack(spacing: 10) {
                                    rowTextField("姓名", text: binding(\.name))
                                    rowTextField("性别", text: binding(\.gender))
                                    rowDatePicker("出生日期", selection: binding(\.birthDate))
                                    rowDatePicker("末次月经", selection: binding(\.lastPeriodDate))
                                    rowDatePicker("试管植入日期", selection: binding(\.ivfTransferDate))
                                    rowDatePicker("首次验孕日期", selection: binding(\.firstPositiveDate))
                                }
                            }
                        }

                        profileSection(title: "三餐与作息") {
                            AppCard {
                                ReminderSettingsView()
                                    .environmentObject(store)
                            }
                            AppCard {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb")
                                        .foregroundStyle(AppTheme.actionPrimary)
                                    Text("提醒映射说明：饭后=对应餐点 +20 分钟；睡前=睡觉时间 -30 分钟。")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                        }

                        profileSection(title: "健康信息") {
                            AppCard {
                                VStack(spacing: 10) {
                                    rowTextField("身高(cm)", text: optionalBinding(\.heightCM))
                                    rowTextField("体重(kg)", text: optionalBinding(\.weightKG))
                                    rowTextField("过敏史", text: optionalBinding(\.allergyHistory))
                                    rowTextField("主治医生/联系方式", text: optionalBinding(\.doctorContact))

                                    Divider().overlay(AppTheme.borderLight)
                                    Stepper("步数目标：\(draft?.stepsGoal ?? 0) 步", value: binding(\.stepsGoal), in: 2000...30000, step: 500)
                                    Stepper("饮水目标：\(draft?.waterGoalML ?? 0) ml", value: binding(\.waterGoalML), in: 500...4000, step: 100)
                                }
                            }
                        }

                        profileSection(title: "家属绑定准备") {
                            AppCard {
                                VStack(spacing: 10) {
                                    rowTextField("关系人称呼", text: $relationName)
                                    rowTextField("关系人手机", text: $relationPhone)
                                    HStack {
                                        Text("邀请码")
                                            .font(.footnote)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .frame(width: 88, alignment: .leading)
                                        Text(inviteCodePlaceholder)
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(AppTheme.actionPrimary)
                                        Spacer()
                                    }
                                    Text("说明：本版本先做绑定准备，真正家属端会在后续版本上线。")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        profileSection(title: "数据管理") {
                            AppCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("一键清除所有记录、聊天与提醒设置，恢复到首次进入 App 的状态。")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Button(role: .destructive) {
                                        showResetAllDataDialog = true
                                    } label: {
                                        Text(isResettingAllData ? "清除中..." : "清除所有数据并重置")
                                            .font(.footnote.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .frame(minHeight: 44)
                                            .background(AppTheme.statusErrorSoft)
                                            .foregroundStyle(AppTheme.statusError)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isResettingAllData)
                                }
                            }
                        }

                    }
                    .padding(.top, 12)
                    .padding(.bottom, AppLayout.tabPageScrollTailPadding)
                }
            }
            .confirmationDialog("选择清除范围", isPresented: $showResetAllDataDialog, titleVisibility: .visible) {
                Button("仅清空 App 内数据", role: .destructive) {
                    Task {
                        await performReset(mode: .appOnly)
                    }
                }
                Button("清空 App 数据 + 系统提醒", role: .destructive) {
                    Task {
                        await performReset(mode: .includeSystemReminders)
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("此操作不可恢复。将清除资料、用药、检查、预约、聊天记录和提醒配置。")
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveDraftIfNeeded()
                    }
                }
            }
            .onAppear {
                reloadDraftFromStore()
            }
            .onDisappear {
                saveDraftIfNeeded()
            }
            .font(AppTheme.bodyFont)
        }
    }

    private var profileHeaderCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.2")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.actionPrimary)
                .frame(width: 56, height: 56)
                .background(LinearGradient(colors: [Color(hex: "FCEEE3"), Color(hex: "F9DCC8")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(draft?.name ?? store.state.profile.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("孕 \(store.gestationalWeekText) · 预产期 \(store.formatDate(store.dueDate))")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                Text("为了提醒更准确，可随时更新资料")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textHint)
            }
            Spacer()
        }
        .padding(16)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }

    private func profileSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textHint)
                .padding(.horizontal)
            content()
                .padding(.horizontal)
        }
    }

    private func rowTextField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 88, alignment: .leading)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func rowDatePicker(_ title: String, selection: Binding<Date>) -> some View {
        AppDateField(title, selection: selection, titleWidth: 88)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Profile, Value>) -> Binding<Value> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? store.state.profile[keyPath: keyPath] },
            set: { newValue in
                guard var profile = draft else { return }
                profile[keyPath: keyPath] = newValue
                draft = profile
            }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<Profile, String?>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? store.state.profile[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard var profile = draft else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                profile[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                draft = profile
            }
        )
    }

    private func saveDraftIfNeeded() {
        guard let draft else { return }
        store.updateProfile(draft)
        store.saveFamilyBindingDraft(
            relationName: relationName,
            relationPhone: relationPhone,
            inviteCodePlaceholder: inviteCodePlaceholder
        )
    }

    private func reloadDraftFromStore() {
        draft = store.state.profile
        relationName = store.state.familyBindingDraft?.relationName ?? ""
        relationPhone = store.state.familyBindingDraft?.relationPhone ?? ""
        inviteCodePlaceholder = store.state.familyBindingDraft?.inviteCodePlaceholder ?? "INVITE-准备中"
    }

    @MainActor
    private func performReset(mode: ResetMode) async {
        guard !isResettingAllData else { return }
        isResettingAllData = true
        defer { isResettingAllData = false }

        let result = await store.resetAllDataToFreshInstall(mode: mode)
        reloadDraftFromStore()

        switch result {
        case .appOnly:
            store.showGlobalBanner(message: "已清空 App 数据，已恢复到新用户状态。", level: .success)
        case .appAndSystemCleared:
            store.showGlobalBanner(message: "已清空 App 数据和系统提醒。", level: .success)
        case .appClearedSystemPermissionDenied:
            store.showGlobalBanner(message: "App 数据已清空；未授予提醒事项权限，系统提醒可能仍保留。", level: .info)
        case .appClearedSystemFailed(let reason):
            store.showGlobalBanner(message: "App 数据已清空；系统提醒清理失败：\(reason)", level: .info)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PregnancyStore())
}
