import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var store: PregnancyStore

    @State private var step = 1
    @State private var didLoad = false
    @State private var profileDraft = OnboardingFlowView.defaultProfile()
    @State private var reminderDraft = ReminderConfig(
        wakeUpTime: "07:00",
        breakfastTime: "08:30",
        lunchTime: "12:30",
        dinnerTime: "18:30",
        sleepTime: "22:30",
        minutesBefore: 0
    )
    @State private var breakfastTime = Date()
    @State private var lunchTime = Date()
    @State private var dinnerTime = Date()
    @State private var sleepTime = Date()
    @State private var skippedFields: Set<String> = []
    @State private var errorText = ""

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if step == 1 {
                            stepOneView
                        } else if step == 2 {
                            stepTwoView
                        } else {
                            stepThreeView
                        }

                        if !errorText.isEmpty {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.statusError)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }

                actionBar
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(AppTheme.card)
            }
        }
        .onAppear {
            loadFromStoreIfNeeded()
        }
        .font(AppTheme.bodyFont)
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("先完善资料，提醒才会准")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("第 \(step)/3 步")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.surfaceMuted)
                        .frame(height: 8)
                    Capsule()
                        .fill(AppTheme.actionPrimary)
                        .frame(width: proxy.size.width * CGFloat(step) / 3.0, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var stepOneView: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Step 1 · 必填核心信息")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textHint)

                    fieldRow(title: "姓名", text: binding(\.name), placeholder: "例如：小李")
                    dateRow(title: "末次月经", date: binding(\.lastPeriodDate))
                    timeRow(title: "早餐时间", selection: $breakfastTime)
                    timeRow(title: "午餐时间", selection: $lunchTime)
                    timeRow(title: "晚餐时间", selection: $dinnerTime)
                    timeRow(title: "睡觉时间", selection: $sleepTime)
                }
            }
            .padding(.horizontal)

            AppCard {
                Text("说明：本次更新后，所有用户都需要重走一次引导，这是为了让提醒更准确。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal)
        }
    }

    private var stepTwoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Step 2 · 可选信息（可逐项暂不填写）")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textHint)

                    optionalFieldRow(title: "身高(cm)", key: "height", text: optionalBinding(\.heightCM))
                    optionalFieldRow(title: "体重(kg)", key: "weight", text: optionalBinding(\.weightKG))
                    optionalFieldRow(title: "过敏史", key: "allergy", text: optionalBinding(\.allergyHistory))
                    optionalFieldRow(title: "主治医生/联系方式", key: "doctor", text: optionalBinding(\.doctorContact))
                }
            }
            .padding(.horizontal)
        }
    }

    private var stepThreeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Step 3 · 确认信息")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textHint)
                    confirmRow(label: "姓名", value: profileDraft.name)
                    confirmRow(label: "当前孕周", value: gestationalText(for: profileDraft.lastPeriodDate))
                    confirmRow(label: "预产期", value: formatDate(dueDate(for: profileDraft.lastPeriodDate)))
                    confirmRow(label: "早餐提醒", value: reminderDraft.breakfastTime)
                    confirmRow(label: "午餐提醒", value: reminderDraft.lunchTime)
                    confirmRow(label: "晚餐提醒", value: reminderDraft.dinnerTime)
                    confirmRow(label: "睡前提醒", value: reminderDraft.sleepTime)
                }
            }
            .padding(.horizontal)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if step > 1 {
                Button("上一步") {
                    errorText = ""
                    step -= 1
                    store.updateOnboardingStep(step)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(AppTheme.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(step == 3 ? "确认并进入首页" : "下一步") {
                handleNext()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(AppTheme.actionPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func handleNext() {
        errorText = ""

        if step == 1 {
            guard validateStepOne() else { return }
            step = 2
            store.updateOnboardingStep(step)
            return
        }

        if step == 2 {
            step = 3
            store.updateOnboardingStep(step)
            return
        }

        store.completeOnboarding(
            profile: profileDraft,
            reminder: reminderDraft,
            skippedFields: Array(skippedFields).sorted()
        )
    }

    private func validateStepOne() -> Bool {
        if profileDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorText = "请先填写姓名"
            return false
        }

        reminderDraft.breakfastTime = hhmmFromDate(breakfastTime)
        reminderDraft.lunchTime = hhmmFromDate(lunchTime)
        reminderDraft.dinnerTime = hhmmFromDate(dinnerTime)
        reminderDraft.sleepTime = hhmmFromDate(sleepTime)
        reminderDraft.minutesBefore = 0
        return true
    }

    private func optionalFieldRow(title: String, key: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 110, alignment: .leading)

            TextField("可填写", text: text)
                .textFieldStyle(.roundedBorder)

            Button(skippedFields.contains(key) ? "已跳过" : "暂不填写") {
                if skippedFields.contains(key) {
                    skippedFields.remove(key)
                } else {
                    skippedFields.insert(key)
                    text.wrappedValue = ""
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(skippedFields.contains(key) ? AppTheme.actionPrimary : AppTheme.textSecondary)
        }
    }

    private func confirmRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
        }
    }

    private func fieldRow(title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 88, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func dateRow(title: String, date: Binding<Date>) -> some View {
        AppDateField(title, selection: date, titleWidth: 88)
    }

    private func timeRow(title: String, selection: Binding<Date>) -> some View {
        AppTimeField(title, selection: selection, titleWidth: 88)
    }

    private func dateFromHHmm(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let normalized = store.normalizeTimeText(text) ?? text
        guard let parsed = formatter.date(from: normalized) else {
            return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        return Calendar.current.date(bySettingHour: comps.hour ?? 8, minute: comps.minute ?? 0, second: 0, of: Date()) ?? Date()
    }

    private func hhmmFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Profile, Value>) -> Binding<Value> {
        Binding(
            get: { profileDraft[keyPath: keyPath] },
            set: { profileDraft[keyPath: keyPath] = $0 }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<Profile, String?>) -> Binding<String> {
        Binding(
            get: { profileDraft[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                profileDraft[keyPath: keyPath] = trimmed.isEmpty ? nil : trimmed
                if !trimmed.isEmpty {
                    skippedFields.remove(optionalKey(for: keyPath))
                }
            }
        )
    }

    private func optionalKey(for keyPath: WritableKeyPath<Profile, String?>) -> String {
        if keyPath == \.heightCM { return "height" }
        if keyPath == \.weightKG { return "weight" }
        if keyPath == \.allergyHistory { return "allergy" }
        if keyPath == \.doctorContact { return "doctor" }
        return ""
    }

    private func loadFromStoreIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        profileDraft = store.state.profile
        reminderDraft = store.currentReminderConfig()
        breakfastTime = dateFromHHmm(reminderDraft.breakfastTime)
        lunchTime = dateFromHHmm(reminderDraft.lunchTime)
        dinnerTime = dateFromHHmm(reminderDraft.dinnerTime)
        sleepTime = dateFromHHmm(reminderDraft.sleepTime)
        skippedFields = Set(store.state.profileOptionalFieldsSkipped)
        step = max(1, min(store.state.onboardingStep, 3))
        store.updateOnboardingStep(step)
    }

    private func dueDate(for lastPeriod: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 280, to: lastPeriod) ?? Date()
    }

    private func gestationalText(for lastPeriod: Date) -> String {
        let days = max(Calendar.current.dateComponents([.day], from: lastPeriod, to: Date()).day ?? 0, 0)
        return "\(days / 7)周+\(days % 7)天"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func defaultProfile() -> Profile {
        let today = Date()
        return Profile(
            name: "",
            gender: "女",
            birthDate: Calendar.current.date(byAdding: .year, value: -28, to: today) ?? today,
            lastPeriodDate: Calendar.current.date(byAdding: .day, value: -42, to: today) ?? today,
            ivfTransferDate: today,
            firstPositiveDate: today,
            stepsGoal: 8000,
            waterGoalML: 1200,
            heightCM: nil,
            weightKG: nil,
            allergyHistory: nil,
            doctorContact: nil
        )
    }
}

#Preview {
    OnboardingFlowView()
        .environmentObject(PregnancyStore())
}
