import SwiftUI

enum RecordSegment: String, CaseIterable, Identifiable {
    case medication = "用药"
    case check = "检查"
    case appointment = "预约"

    var id: String { rawValue }
}

struct CheckListView: View {
    private struct MedicationGroup: Identifiable {
        var id: String
        var name: String
        var items: [MedicationItem]

        var periods: [TimePeriod] {
            Array(Set(items.map(\.period))).sorted { $0.sortOrder < $1.sortOrder }
        }

        var frequencyText: String {
            periods.count <= 1 ? "每天1次" : "每天\(periods.count)次"
        }
    }

    @EnvironmentObject private var store: PregnancyStore
    @State private var selectedSegment: RecordSegment = .medication
    @State private var selectedCheckType: CheckType?
    @State private var showAddMedication = false
    @State private var showAddCheck = false
    @State private var showAddAppointment = false
    @State private var editingAppointment: AppointmentItem?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                            .padding(.horizontal)

                        Picker("记录分段", selection: $selectedSegment) {
                            ForEach(RecordSegment.allCases) { segment in
                                Text(segment.rawValue).tag(segment)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        if selectedSegment == .medication {
                            medicationSection
                        } else if selectedSegment == .check {
                            checkSection
                        } else {
                            appointmentSection
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, AppLayout.scrollTailPadding)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(bottomButtonTitle) {
                    handleBottomAction()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(AppTheme.actionPrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, AppLayout.dockBottomInsetAboveTabBar)
                .background(AppTheme.background)
            }
            .sheet(isPresented: $showAddMedication) {
                RecordAddView(initialTab: .medication)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAddCheck) {
                RecordAddView(initialTab: .check)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAddAppointment) {
                AppointmentEditorSheet(appointment: nil) { item in
                    store.saveAppointment(item)
                }
            }
            .sheet(item: $editingAppointment) { item in
                AppointmentEditorSheet(appointment: item) { edited in
                    store.saveAppointment(edited)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("记录")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("用药 / 检查 / 预约，默认展示用药")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var medicationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusProgressCard(title: "今日用药完成", done: medicationDoneCount, total: medicationTotalCount)
                .padding(.horizontal)

            if medicationGroups.isEmpty {
                AppCard {
                    Text("暂无用药记录")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal)
            } else {
                ForEach(medicationGroups) { group in
                    medicationRow(group)
                        .padding(.horizontal)
                }
            }
        }
    }

    private func medicationRow(_ group: MedicationGroup) -> some View {
        let done = groupDone(group)

        return AppCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        HStack(spacing: 6) {
                            Text(group.frequencyText)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(done ? Color(hex: "EDF7F1") : AppTheme.surfaceMuted)
                                .foregroundStyle(done ? Color(hex: "6BAB8A") : AppTheme.textSecondary)
                                .clipShape(Capsule())
                            Text(periodText(group))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(nextTimeText(for: group))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                HStack(spacing: 10) {
                    Button(done ? "已完成" : "标记完成") {
                        toggleGroupDone(group)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(done ? Color(hex: "EDF7F1") : AppTheme.actionPrimary)
                    .foregroundStyle(done ? Color(hex: "6BAB8A") : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityValue(done ? "已完成" : "未完成")

                    Button("归档") {
                        store.archiveMedicationGroup(named: group.name)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(AppTheme.surfaceMuted)
                    .foregroundStyle(AppTheme.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()
                }
            }
        }
        .opacity(done ? 0.7 : 1)
    }

    private var checkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "全部", active: selectedCheckType == nil) {
                        selectedCheckType = nil
                    }
                    ForEach(store.supportedCheckTypes) { type in
                        FilterChip(title: type.title, active: selectedCheckType == type) {
                            selectedCheckType = type
                        }
                    }
                }
                .padding(.horizontal)
            }

            if filteredRecords.isEmpty {
                AppCard {
                    Text("暂无检查记录")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal)
            } else {
                ForEach(filteredRecords) { record in
                    VStack(spacing: 8) {
                        NavigationLink {
                            CheckDetailView(
                                record: record,
                                previous: store.previousCheckRecord(for: record),
                                gestationalText: store.gestationalWeekText(for: record.checkTime)
                            )
                            .environmentObject(store)
                        } label: {
                            CheckRecordCard(
                                record: record,
                                previous: store.previousCheckRecord(for: record),
                                gestationalText: store.gestationalWeekText(for: record.checkTime),
                                store: store
                            )
                        }
                        .buttonStyle(.plain)

                        HStack {
                            Spacer()
                            Button("归档") {
                                store.archiveCheckRecord(id: record.id)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(AppTheme.surfaceMuted)
                            .foregroundStyle(AppTheme.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var appointmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if activeAppointments.isEmpty {
                AppCard {
                    Text("暂无产检预约")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal)
            } else {
                ForEach(activeAppointments) { appointment in
                    AppCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appointment.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)

                            Text("\(store.formatDate(appointment.dueDate)) \(store.appointmentTimeText(appointment.dueDate)) · \(store.countdownText(to: appointment.dueDate))")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)

                            if !appointment.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(appointment.detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            HStack(spacing: 10) {
                                Button(appointment.isDone ? "改为未完成" : "标记完成") {
                                    store.toggleAppointment(appointment.id)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(appointment.isDone ? AppTheme.surfaceMuted : AppTheme.actionPrimary)
                                .foregroundStyle(appointment.isDone ? AppTheme.textSecondary : .white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityValue(appointment.isDone ? "已完成" : "未完成")

                                Button("编辑") {
                                    editingAppointment = appointment
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(AppTheme.statusInfoSoft)
                                .foregroundStyle(AppTheme.statusInfo)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Button("归档") {
                                    store.archiveAppointment(id: appointment.id)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(AppTheme.surfaceMuted)
                                .foregroundStyle(AppTheme.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var medicationGroups: [MedicationGroup] {
        let grouped = Dictionary(grouping: store.activeMedications) { med in
            med.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        return grouped
            .compactMap { key, values in
                guard let first = values.first else { return nil }
                return MedicationGroup(id: key, name: first.name, items: values)
            }
            .sorted { lhs, rhs in
                let l = lhs.periods.first?.sortOrder ?? 99
                let r = rhs.periods.first?.sortOrder ?? 99
                if l == r { return lhs.name < rhs.name }
                return l < r
            }
    }

    private var activeAppointments: [AppointmentItem] {
        store.activeAppointments.sorted { $0.dueDate < $1.dueDate }
    }

    private var filteredRecords: [CheckRecord] {
        store.checkRecords(of: selectedCheckType)
    }

    private var medicationTotalCount: Int {
        store.medicationSectionsForToday().flatMap { $0.rows }.count
    }

    private var medicationDoneCount: Int {
        store.medicationSectionsForToday().flatMap { $0.rows }.filter { $0.isCompleted }.count
    }

    private var bottomButtonTitle: String {
        switch selectedSegment {
        case .medication: return "+ 新增用药 / 补剂"
        case .check: return "+ 添加检查记录"
        case .appointment: return "+ 添加预约"
        }
    }

    private func handleBottomAction() {
        switch selectedSegment {
        case .medication:
            showAddMedication = true
        case .check:
            showAddCheck = true
        case .appointment:
            showAddAppointment = true
        }
    }

    private func groupDone(_ group: MedicationGroup) -> Bool {
        let ids = group.items.map { "med-\($0.id)" }
        return !ids.isEmpty && ids.allSatisfy { store.state.completedDailyTaskIDs.contains($0) }
    }

    private func toggleGroupDone(_ group: MedicationGroup) {
        let ids = group.items.map { "med-\($0.id)" }
        let shouldComplete = ids.contains { !store.state.completedDailyTaskIDs.contains($0) }

        for item in group.items {
            let id = "med-\(item.id)"
            let isDone = store.state.completedDailyTaskIDs.contains(id)
            if shouldComplete && !isDone {
                store.toggleDailyTask(id)
                ReminderScheduler.cancelFollowUp(for: item.period)
            } else if !shouldComplete && isDone {
                store.toggleDailyTask(id)
            }
        }
    }

    private func periodText(_ group: MedicationGroup) -> String {
        group.periods.map(\.rawValue).joined(separator: "、")
    }

    private func nextTimeText(for group: MedicationGroup) -> String {
        let now = store.timeToMinutes(store.currentTimeText()) ?? 0
        let times: [(text: String, minutes: Int)] = group.periods.compactMap { period in
            let base = store.reminderTime(for: period)
            let adjusted = ReminderScheduler.semanticAdjustedTimeText(for: period, baseTime: base)
            guard let minutes = store.timeToMinutes(adjusted) else { return nil }
            return (adjusted, minutes)
        }

        if let upcoming = times.filter({ $0.minutes >= now }).sorted(by: { $0.minutes < $1.minutes }).first {
            return upcoming.text
        }
        return times.sorted(by: { $0.minutes < $1.minutes }).first?.text ?? "--:--"
    }
}

struct AppointmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let appointment: AppointmentItem?
    let onSave: (AppointmentItem) -> Void

    @State private var title: String
    @State private var dueDate: Date
    @State private var detail: String
    @State private var errorText = ""

    init(appointment: AppointmentItem?, onSave: @escaping (AppointmentItem) -> Void) {
        self.appointment = appointment
        self.onSave = onSave

        let defaultDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _title = State(initialValue: appointment?.title ?? "")
        _dueDate = State(initialValue: appointment?.dueDate ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: defaultDate) ?? defaultDate)
        _detail = State(initialValue: appointment?.detail ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("预约标题", text: $title)
                            DatePicker("预约时间", selection: $dueDate)
                            TextField("备注（可选）", text: $detail, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "D4727A"))
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle(appointment == nil ? "新增预约" : "编辑预约")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errorText = "请填写预约标题"
            return
        }

        let item = AppointmentItem(
            id: appointment?.id ?? UUID().uuidString,
            title: trimmedTitle,
            dueDate: dueDate,
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            isDone: appointment?.isDone ?? false,
            isArchived: false
        )
        onSave(item)
        dismiss()
    }
}

struct CheckRecordCard: View {
    let record: CheckRecord
    let previous: CheckRecord?
    let gestationalText: String
    let store: PregnancyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.type.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeSoftColor)
                    .foregroundStyle(typeColor)
                    .clipShape(Capsule())
                Spacer()
                Text("\(formatDate(record.checkTime)) · 孕\(gestationalText)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 14) {
                ForEach(record.metrics.prefix(3)) { metric in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textHint)
                        Text(metric.valueText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if record.type == .pregnancyPanel, let previous {
                HStack(spacing: 8) {
                    ForEach(["hcg", "progesterone", "estradiol"], id: \.self) { key in
                        let current = metricValue(key)
                        let prev = previousMetricValue(key, previous)
                        let symbol = store.trendSymbol(current: current, previous: prev)
                        Text(metricLabel(key) + " " + symbol)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.surfaceMuted)
                            .foregroundStyle(AppTheme.textSecondary)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if let doubling = hcgDoubling(previous: previous) {
                        Text("翻倍 ~\(doubling)天")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.statusInfoSoft)
                            .foregroundStyle(AppTheme.statusInfo)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metricValue(_ key: String) -> String {
        record.metrics.first(where: { $0.key == key })?.valueText ?? "-"
    }

    private func previousMetricValue(_ key: String, _ previous: CheckRecord) -> String? {
        previous.metrics.first(where: { $0.key == key })?.valueText
    }

    private func metricLabel(_ key: String) -> String {
        switch key {
        case "hcg": return "HCG"
        case "progesterone": return "P"
        case "estradiol": return "E2"
        default: return key.uppercased()
        }
    }

    private func hcgDoubling(previous: CheckRecord) -> String? {
        let currentHcg = metricValue("hcg")
        let prevHcg = previousMetricValue("hcg", previous) ?? ""
        let hours = record.checkTime.timeIntervalSince(previous.checkTime) / 3600
        return store.hcgDoublingDays(current: currentHcg, previous: prevHcg, hoursBetween: hours)
    }

    private var typeColor: Color {
        switch record.type {
        case .pregnancyPanel: return AppTheme.actionPrimary
        case .nt: return AppTheme.statusInfo
        case .tang: return Color(hex: "A48BBF")
        case .ultrasound: return Color(hex: "6BAB8A")
        case .cbc: return Color(hex: "D4A94E")
        case .custom: return AppTheme.textSecondary
        }
    }

    private var typeSoftColor: Color {
        switch record.type {
        case .pregnancyPanel: return AppTheme.accentSoft
        case .nt: return AppTheme.statusInfoSoft
        case .tang: return Color(hex: "F3EFF8")
        case .ultrasound: return Color(hex: "EDF7F1")
        case .cbc: return Color(hex: "FFF8E8")
        case .custom: return AppTheme.surfaceMuted
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct FilterChip: View {
    let title: String
    let active: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(active ? AppTheme.accentSoft : AppTheme.card)
                .foregroundStyle(active ? AppTheme.actionPrimary : AppTheme.textSecondary)
                .overlay(
                    Capsule().stroke(active ? AppTheme.actionPrimary : AppTheme.border, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
    }
}

#Preview {
    CheckListView()
        .environmentObject(PregnancyStore())
}
