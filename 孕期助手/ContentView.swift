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
    @State private var relationName = ""
    @State private var relationPhone = ""
    @State private var inviteCodePlaceholder = "INVITE-准备中"
    @State private var showResetAllDataDialog = false
    @State private var isResettingAllData = false
    @State private var activeEditor: ProfileEditor?
    @State private var showReminderSettingsSheet = false

    private enum ProfileEditor: Identifiable {
        case text(TextEditorField)
        case date(DateEditorField)
        case integer(IntegerEditorField)
        case gender

        var id: String {
            switch self {
            case .text(let field): return "text_\(field.rawValue)"
            case .date(let field): return "date_\(field.rawValue)"
            case .integer(let field): return "integer_\(field.rawValue)"
            case .gender: return "gender"
            }
        }
    }

    private enum TextEditorField: String, CaseIterable {
        case name
        case height
        case weight
        case allergy
        case doctor
        case familyName
        case familyPhone

        var title: String {
            switch self {
            case .name: return "姓名"
            case .height: return "身高(cm)"
            case .weight: return "体重(kg)"
            case .allergy: return "过敏史"
            case .doctor: return "主治医生/联系方式"
            case .familyName: return "关系人称呼"
            case .familyPhone: return "关系人手机"
            }
        }

        var placeholder: String {
            switch self {
            case .name: return "请输入姓名"
            case .height: return "例如 165"
            case .weight: return "例如 52.3"
            case .allergy: return "例如 青霉素过敏"
            case .doctor: return "例如 王医生 13800000000"
            case .familyName: return "例如 老公"
            case .familyPhone: return "请输入手机号"
            }
        }

        var keyboardType: UIKeyboardType {
            switch self {
            case .height, .weight:
                return .decimalPad
            case .familyPhone:
                return .numberPad
            default:
                return .default
            }
        }
    }

    private enum DateEditorField: String, CaseIterable {
        case birthDate
        case lastPeriodDate
        case ivfTransferDate
        case firstPositiveDate

        var title: String {
            switch self {
            case .birthDate: return "出生日期"
            case .lastPeriodDate: return "末次月经"
            case .ivfTransferDate: return "试管植入日期"
            case .firstPositiveDate: return "首次验孕日期"
            }
        }
    }

    private enum IntegerEditorField: String, CaseIterable {
        case stepsGoal
        case waterGoal

        var title: String {
            switch self {
            case .stepsGoal: return "步数目标"
            case .waterGoal: return "饮水目标"
            }
        }

        var unit: String {
            switch self {
            case .stepsGoal: return "步"
            case .waterGoal: return "ml"
            }
        }

        var range: ClosedRange<Int> {
            switch self {
            case .stepsGoal: return 2000...30000
            case .waterGoal: return 500...4000
            }
        }

        var step: Int {
            switch self {
            case .stepsGoal: return 500
            case .waterGoal: return 100
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "EFEFF4").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        rowGroup {
                            listRow(title: "姓名", value: pendingText(ProfilePendingFieldKey.name, raw: store.state.profile.name)) {
                                activeEditor = .text(.name)
                            }
                            listRow(title: "性别", value: pendingText(ProfilePendingFieldKey.gender, raw: store.state.profile.gender)) {
                                activeEditor = .gender
                            }
                            listRow(title: "出生日期", value: pendingDateText(ProfilePendingFieldKey.birthDate, date: store.state.profile.birthDate)) {
                                activeEditor = .date(.birthDate)
                            }
                            listRow(title: "末次月经", value: pendingDateText(ProfilePendingFieldKey.lastPeriodDate, date: store.state.profile.lastPeriodDate)) {
                                activeEditor = .date(.lastPeriodDate)
                            }
                            listRow(title: "试管植入日期", value: pendingDateText(ProfilePendingFieldKey.ivfTransferDate, date: store.state.profile.ivfTransferDate)) {
                                activeEditor = .date(.ivfTransferDate)
                            }
                            listRow(title: "首次验孕日期", value: pendingDateText(ProfilePendingFieldKey.firstPositiveDate, date: store.state.profile.firstPositiveDate), showDivider: false) {
                                activeEditor = .date(.firstPositiveDate)
                            }
                        }

                        rowGroup {
                            listRow(title: "三餐与作息", value: reminderSummary, showDivider: false) {
                                showReminderSettingsSheet = true
                            }
                        }

                        rowGroup {
                            navigationListRow(title: "记录中心", value: "用药 / 检查报告 / 预约", showDivider: false) {
                                CheckListView(initialSegment: .medication, embeddedInParentNavigation: true)
                                    .environmentObject(store)
                                    .navigationTitle("记录中心")
                                    .navigationBarTitleDisplayMode(.inline)
                            }
                        }

                        rowGroup {
                            listRow(title: "身高(cm)", value: pendingText(ProfilePendingFieldKey.height, raw: store.state.profile.heightCM)) {
                                activeEditor = .text(.height)
                            }
                            listRow(title: "体重(kg)", value: pendingText(ProfilePendingFieldKey.weight, raw: store.state.profile.weightKG)) {
                                activeEditor = .text(.weight)
                            }
                            listRow(title: "过敏史", value: pendingText(ProfilePendingFieldKey.allergy, raw: store.state.profile.allergyHistory)) {
                                activeEditor = .text(.allergy)
                            }
                            listRow(title: "主治医生/联系方式", value: pendingText(ProfilePendingFieldKey.doctor, raw: store.state.profile.doctorContact)) {
                                activeEditor = .text(.doctor)
                            }
                            listRow(title: "步数目标", value: "\(store.state.profile.stepsGoal) 步") {
                                activeEditor = .integer(.stepsGoal)
                            }
                            listRow(title: "饮水目标", value: "\(store.state.profile.waterGoalML) ml", showDivider: false) {
                                activeEditor = .integer(.waterGoal)
                            }
                        }

                        rowGroup {
                            listRow(title: "关系人称呼", value: displayText(relationName)) {
                                activeEditor = .text(.familyName)
                            }
                            listRow(title: "关系人手机", value: displayText(relationPhone)) {
                                activeEditor = .text(.familyPhone)
                            }
                            readonlyRow(title: "邀请码", value: inviteCodePlaceholder, showDivider: false)
                        }

                        rowGroup {
                            destructiveRow(title: isResettingAllData ? "清除中..." : "清除所有数据并重置", showDivider: false) {
                                showResetAllDataDialog = true
                            }
                            .disabled(isResettingAllData)
                        }
                    }
                    .padding(.top, 10)
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
            .onAppear {
                reloadBindingsFromStore()
            }
            .sheet(item: $activeEditor) { editor in
                editorSheet(editor)
            }
            .sheet(isPresented: $showReminderSettingsSheet) {
                NavigationStack {
                    ReminderSettingsView()
                        .environmentObject(store)
                        .navigationTitle("三餐与作息")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .font(AppTheme.bodyFont)
        }
    }

    private var reminderSummary: String {
        let config = store.currentReminderConfig()
        let wake = pendingReminderValue(ProfilePendingFieldKey.wakeUpTime, raw: config.wakeUpTime)
        let breakfast = pendingReminderValue(ProfilePendingFieldKey.breakfastTime, raw: config.breakfastTime)
        let lunch = pendingReminderValue(ProfilePendingFieldKey.lunchTime, raw: config.lunchTime)
        let dinner = pendingReminderValue(ProfilePendingFieldKey.dinnerTime, raw: config.dinnerTime)
        let sleep = pendingReminderValue(ProfilePendingFieldKey.sleepTime, raw: config.sleepTime)
        return "\(wake) / \(breakfast) / \(lunch) / \(dinner) / \(sleep)"
    }

    private func rowGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.white)
    }

    private func listRow(
        title: String,
        value: String,
        showDivider: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "B6B6BB"))
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showDivider {
                Divider().padding(.leading, 16)
            }
        }
    }

    private func navigationListRow<Destination: View>(
        title: String,
        value: String,
        showDivider: Bool = true,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Color(hex: "1C1C1E"))
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color(hex: "8E8E93"))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "B6B6BB"))
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showDivider {
                Divider().padding(.leading, 16)
            }
        }
    }

    private func readonlyRow(title: String, value: String, showDivider: Bool = true) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Color(hex: "1C1C1E"))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color(hex: "8E8E93"))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) {
            if showDivider {
                Divider().padding(.leading, 16)
            }
        }
    }

    private func destructiveRow(
        title: String,
        showDivider: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color(hex: "D64545"))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "B6B6BB"))
            }
            .frame(minHeight: 56)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if showDivider {
                Divider().padding(.leading, 16)
            }
        }
    }

    private func profileBinding<Value>(_ keyPath: WritableKeyPath<Profile, Value>) -> Binding<Value> {
        Binding(
            get: { store.state.profile[keyPath: keyPath] },
            set: { newValue in
                var profile = store.state.profile
                profile[keyPath: keyPath] = newValue
                store.updateProfile(profile)
            }
        )
    }

    private func optionalProfileBinding(_ keyPath: WritableKeyPath<Profile, String?>) -> Binding<String> {
        Binding(
            get: { store.state.profile[keyPath: keyPath] ?? "" },
            set: { newValue in
                var profile = store.state.profile
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                profile[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                store.updateProfile(profile)
            }
        )
    }

    private var familyNameBinding: Binding<String> {
        Binding(
            get: { relationName },
            set: { newValue in
                relationName = newValue
                saveFamilyBindingDraft()
            }
        )
    }

    private var familyPhoneBinding: Binding<String> {
        Binding(
            get: { relationPhone },
            set: { newValue in
                relationPhone = newValue
                saveFamilyBindingDraft()
            }
        )
    }

    private func saveFamilyBindingDraft() {
        store.saveFamilyBindingDraft(
            relationName: relationName,
            relationPhone: relationPhone,
            inviteCodePlaceholder: inviteCodePlaceholder
        )
    }

    private func reloadBindingsFromStore() {
        relationName = store.state.familyBindingDraft?.relationName ?? ""
        relationPhone = store.state.familyBindingDraft?.relationPhone ?? ""
        inviteCodePlaceholder = store.state.familyBindingDraft?.inviteCodePlaceholder ?? "INVITE-准备中"
    }

    @ViewBuilder
    private func editorSheet(_ editor: ProfileEditor) -> some View {
        switch editor {
        case .text(let field):
            ProfileTextEditorSheet(
                title: field.title,
                text: textBinding(for: field),
                placeholder: field.placeholder,
                keyboardType: field.keyboardType
            )
        case .date(let field):
            ProfileDateEditorSheet(
                title: field.title,
                date: dateBinding(for: field)
            )
        case .integer(let field):
            ProfileIntegerEditorSheet(
                title: field.title,
                value: intBinding(for: field),
                range: field.range,
                step: field.step,
                unit: field.unit
            )
        case .gender:
            ProfileGenderEditorSheet(selection: pendingAwareTextBinding(profileBinding(\.gender), key: ProfilePendingFieldKey.gender))
        }
    }

    private func textBinding(for field: TextEditorField) -> Binding<String> {
        switch field {
        case .name:
            return pendingAwareTextBinding(profileBinding(\.name), key: ProfilePendingFieldKey.name)
        case .height:
            return pendingAwareTextBinding(optionalProfileBinding(\.heightCM), key: ProfilePendingFieldKey.height)
        case .weight:
            return pendingAwareTextBinding(optionalProfileBinding(\.weightKG), key: ProfilePendingFieldKey.weight)
        case .allergy:
            return pendingAwareTextBinding(optionalProfileBinding(\.allergyHistory), key: ProfilePendingFieldKey.allergy)
        case .doctor:
            return pendingAwareTextBinding(optionalProfileBinding(\.doctorContact), key: ProfilePendingFieldKey.doctor)
        case .familyName:
            return familyNameBinding
        case .familyPhone:
            return familyPhoneBinding
        }
    }

    private func dateBinding(for field: DateEditorField) -> Binding<Date> {
        switch field {
        case .birthDate:
            return pendingAwareDateBinding(profileBinding(\.birthDate), key: ProfilePendingFieldKey.birthDate)
        case .lastPeriodDate:
            return pendingAwareDateBinding(profileBinding(\.lastPeriodDate), key: ProfilePendingFieldKey.lastPeriodDate)
        case .ivfTransferDate:
            return pendingAwareDateBinding(profileBinding(\.ivfTransferDate), key: ProfilePendingFieldKey.ivfTransferDate)
        case .firstPositiveDate:
            return pendingAwareDateBinding(profileBinding(\.firstPositiveDate), key: ProfilePendingFieldKey.firstPositiveDate)
        }
    }

    private func intBinding(for field: IntegerEditorField) -> Binding<Int> {
        switch field {
        case .stepsGoal:
            return profileBinding(\.stepsGoal)
        case .waterGoal:
            return profileBinding(\.waterGoalML)
        }
    }

    private func pendingAwareTextBinding(_ base: Binding<String>, key: String) -> Binding<String> {
        Binding(
            get: { base.wrappedValue },
            set: { newValue in
                base.wrappedValue = newValue
                let isBlank = newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isBlank {
                    store.markProfileFieldPending(key)
                } else {
                    store.markProfileFieldFilled(key)
                }
            }
        )
    }

    private func pendingAwareDateBinding(_ base: Binding<Date>, key: String) -> Binding<Date> {
        Binding(
            get: { base.wrappedValue },
            set: { newValue in
                base.wrappedValue = newValue
                store.markProfileFieldFilled(key)
            }
        )
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

    @MainActor
    private func performReset(mode: ResetMode) async {
        guard !isResettingAllData else { return }
        isResettingAllData = true
        defer { isResettingAllData = false }

        let result = await store.resetAllDataToFreshInstall(mode: mode)
        reloadBindingsFromStore()

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

private struct ProfileTextEditorSheet: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("修改后会自动保存")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 16)

                TextField(placeholder, text: $text)
                    .font(.title3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .overlay(
                        Rectangle()
                            .fill(Color(hex: "E5E5EA"))
                            .frame(height: 0.5),
                        alignment: .bottom
                    )
                    .keyboardType(keyboardType)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit {
                        dismiss()
                    }

                Spacer()
            }
            .padding(.top, 12)
            .background(Color(hex: "EFEFF4").ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                focused = true
            }
        }
    }
}

private struct ProfileDateEditorSheet: View {
    let title: String
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("修改后会自动保存")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 16)

                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .padding(.horizontal, 10)

                Spacer()
            }
            .padding(.top, 10)
            .background(Color(hex: "EFEFF4").ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProfileIntegerEditorSheet: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("修改后会自动保存")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(value) \(unit)")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Stepper(
                    "",
                    value: $value,
                    in: range,
                    step: step
                )
                .labelsHidden()
                .tint(AppTheme.actionPrimary)

                Spacer()
            }
            .padding(16)
            .background(Color(hex: "EFEFF4").ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ProfileGenderEditorSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    private let choices = ["女", "男"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.element) { index, option in
                    Button {
                        selection = option
                        dismiss()
                    } label: {
                        HStack {
                            Text(option)
                                .font(.system(size: 19, weight: .regular))
                                .foregroundStyle(Color(hex: "1C1C1E"))
                            Spacer()
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppTheme.actionPrimary)
                            }
                        }
                        .frame(minHeight: 56)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        if index < choices.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
            .background(Color.white)
            .padding(.top, 10)
            .background(Color(hex: "EFEFF4").ignoresSafeArea())
            .navigationTitle("性别")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PregnancyStore())
}
