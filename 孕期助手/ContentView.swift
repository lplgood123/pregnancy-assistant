import SwiftUI
import UIKit

enum MainTab: Hashable {
    case home
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
        Group {
            switch selectedTab {
            case .home:
                ChatHomeView(tabBarVisible: !isKeyboardVisible)
            case .profile:
                ProfileView()
            }
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
        .onChange(of: store.reminderSyncRevision) { _ in
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
                    store.showGlobalBanner(message: "还没开启通知权限，这次提醒没有更新。", level: .error)
                case .localFailed(let reason):
                    store.showGlobalBanner(message: "提醒更新失败：\(reason)。稍后可以再试一次。", level: .error)
                case .localSuccess(let system):
                    switch system {
                    case .skippedDisabled:
                        store.showGlobalBanner(message: "提醒已更新，后续我会继续按时提醒你。", level: .success)
                    case .success:
                        store.showGlobalBanner(message: "提醒已更新（通知 + 提醒事项），可以放心啦。", level: .success)
                    case .permissionDenied:
                        store.showGlobalBanner(message: "通知已更新，但还没开启提醒事项权限。", level: .info)
                    case .failed:
                        store.showGlobalBanner(message: "通知已更新，但提醒事项同步失败，可稍后重试。", level: .info)
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

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "EFEFF4").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        profileCategoryRow(
                            title: "个人资料",
                            value: basicInfoSummary,
                            icon: "person.text.rectangle"
                        ) {
                            ProfileBasicInfoView()
                                .environmentObject(store)
                        }

                        profileCategoryRow(
                            title: "健康档案",
                            value: healthArchiveSummary,
                            icon: "heart.text.square"
                        ) {
                            ProfileHealthArchiveView()
                                .environmentObject(store)
                        }

                        profileCategoryRow(
                            title: "作息提醒",
                            value: routineSummary,
                            icon: "alarm"
                        ) {
                            ProfileRoutineSettingsView()
                                .environmentObject(store)
                        }

                        profileCategoryRow(
                            title: "记录中心",
                            value: "用药 / 检查报告 / 预约",
                            icon: "list.clipboard"
                        ) {
                            CheckListView(initialSegment: .medication, embeddedInParentNavigation: true)
                                .environmentObject(store)
                                .navigationTitle("记录中心")
                                .navigationBarTitleDisplayMode(.inline)
                        }

                        profileCategoryRow(
                            title: "家庭与邀请",
                            value: familySummary,
                            icon: "person.2"
                        ) {
                            ProfileFamilyInviteView()
                                .environmentObject(store)
                        }

                        profileCategoryRow(
                            title: "数据管理",
                            value: "重置与清理",
                            icon: "externaldrive.badge.person.crop"
                        ) {
                            ProfileDataManagementView()
                                .environmentObject(store)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, AppLayout.tabPageScrollTailPadding)
                    .padding(.horizontal, 12)
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .font(AppTheme.bodyFont)
        }
    }

    private var basicInfoSummary: String {
        let name = pendingText(ProfilePendingFieldKey.name, raw: store.state.profile.name)
        let period = pendingDateText(ProfilePendingFieldKey.lastPeriodDate, date: store.state.profile.lastPeriodDate)
        return "\(name) · 末次月经 \(period)"
    }

    private var healthArchiveSummary: String {
        let height = pendingText(ProfilePendingFieldKey.height, raw: store.state.profile.heightCM)
        let weight = pendingText(ProfilePendingFieldKey.weight, raw: store.state.profile.weightKG)
        return "身高 \(height) · 体重 \(weight)"
    }

    private var routineSummary: String {
        let config = store.currentReminderConfig()
        let wake = pendingReminderValue(ProfilePendingFieldKey.wakeUpTime, raw: config.wakeUpTime)
        let breakfast = pendingReminderValue(ProfilePendingFieldKey.breakfastTime, raw: config.breakfastTime)
        return "起床 \(wake) · 早餐 \(breakfast)"
    }

    private var familySummary: String {
        let relation = displayText(store.state.familyBindingDraft?.relationName, fallback: "未设置")
        return relation
    }

    private func profileCategoryRow<Destination: View>(
        title: String,
        value: String,
        icon: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.actionPrimary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.actionPrimary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(value)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: "B6B6BB"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pendingText(_ key: String, raw: String?) -> String {
        if store.isProfileFieldPending(key) {
            return "待填"
        }
        return displayText(raw, fallback: "待填")
    }

    private func pendingDateText(_ key: String, date: Date) -> String {
        if store.isProfileFieldPending(key) {
            return "待填"
        }
        return chineseDate(date)
    }

    private func pendingReminderValue(_ key: String, raw: String) -> String {
        if store.isProfileFieldPending(key) {
            return "待填"
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "待填" : trimmed
    }

    private func displayText(_ raw: String?, fallback: String = "待填") -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func chineseDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
}
