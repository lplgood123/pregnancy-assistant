import SwiftUI

enum RecordSegment: String, CaseIterable, Identifiable {
    case medication = "用药"
    case check = "检查"
    case appointment = "预约"

    var id: String { rawValue }
}

struct CheckListView: View {
    private struct MedicationPeriodSection: Identifiable {
        var period: TimePeriod
        var displayTime: String
        var items: [MedicationItem]
        var doneCount: Int
        var pendingCount: Int
        var isPast: Bool

        var id: String { period.id }
    }

    private enum PendingDelete: Identifiable {
        case medication(id: String, name: String)
        case checkRecord(String)
        case appointment(id: String, title: String)

        var id: String {
            switch self {
            case .medication(let id, _):
                return "med-\(id)"
            case .checkRecord(let id):
                return "check-\(id)"
            case let .appointment(id, _):
                return "appt-\(id)"
            }
        }

        var message: String {
            switch self {
            case .medication(_, let name):
                return "将删除用药“\(name)”，此操作不可撤销。"
            case .checkRecord:
                return "将删除这条检查记录，此操作不可撤销。"
            case .appointment(_, let title):
                return "将删除预约“\(title)”，此操作不可撤销。"
            }
        }
    }

    @EnvironmentObject private var store: PregnancyStore
    @State private var selectedSegment: RecordSegment = .medication
    @State private var selectedCheckType: CheckType?
    @State private var showAddMedication = false
    @State private var showAddCheck = false
    @State private var showAddAppointment = false
    @State private var editingAppointment: AppointmentItem?
    @State private var pendingDelete: PendingDelete?
    @State private var collapsedPastPeriods: Set<TimePeriod> = []
    @State private var expandedPastPeriods: Set<TimePeriod> = []

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

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

                    TabView(selection: $selectedSegment) {
                        segmentPage { medicationSection }
                            .tag(RecordSegment.medication)
                        segmentPage { checkSection }
                            .tag(RecordSegment.check)
                        segmentPage { appointmentSection }
                            .tag(RecordSegment.appointment)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
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
                    .padding(.bottom, 8)

                    Color.clear
                        .frame(height: AppLayout.dockBottomInsetAboveTabBar)
                        .allowsHitTesting(false)
                }
                .background(AppTheme.background.allowsHitTesting(false))
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
            .alert("确认删除", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { shown in
                    if !shown { pendingDelete = nil }
                }
            )) {
                Button("取消", role: .cancel) {
                    pendingDelete = nil
                }
                Button("删除", role: .destructive) {
                    confirmDelete()
                }
            } message: {
                Text(pendingDelete?.message ?? "")
            }
        }
    }

    private func segmentPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.bottom, AppLayout.scrollTailPadding)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
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

            if medicationPeriodSections.isEmpty {
                AppCard {
                    Text("暂无用药记录")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .padding(.horizontal)
            } else {
                ForEach(medicationPeriodSections) { section in
                    medicationPeriodCard(section)
                        .padding(.horizontal)
                }
            }
        }
    }

    private func medicationPeriodCard(_ section: MedicationPeriodSection) -> some View {
        let collapsed = isPeriodCollapsed(section)
        return AppCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    togglePeriodCollapsed(section.period)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(section.period.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text("约 \(section.displayTime)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            HStack(spacing: 6) {
                                Text("已完成 \(section.doneCount)/\(section.items.count)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                if section.pendingCount > 0 {
                                    Text("未服 \(section.pendingCount) 项")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(section.isPast ? AppTheme.statusError : AppTheme.textSecondary)
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.textHint)
                    }
                }
                .buttonStyle(.plain)
                .appTapTarget(minHeight: 44)

                if !collapsed {
                    ForEach(section.items) { item in
                        medicationItemRow(item)
                    }
                }
            }
        }
        .opacity(section.pendingCount == 0 ? 0.88 : 1)
    }

    private func medicationItemRow(_ item: MedicationItem) -> some View {
        let isDone = isMedicationDone(item)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if !item.dosage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !item.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text([item.dosage, item.note].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                Spacer()
                Text(isDone ? "已完成" : "未完成")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isDone ? AppTheme.statusSuccessSoft : AppTheme.statusErrorSoft)
                    .foregroundStyle(isDone ? AppTheme.statusSuccess : AppTheme.statusError)
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                Button(isDone ? "改为未完成" : "标记完成") {
                    toggleMedicationDone(item)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(isDone ? AppTheme.surfaceMuted : AppTheme.actionPrimary)
                .foregroundStyle(isDone ? AppTheme.textSecondary : .white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityValue(isDone ? "已完成" : "未完成")

                Button("删除") {
                    pendingDelete = .medication(id: item.id, name: item.name)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(AppTheme.statusErrorSoft)
                .foregroundStyle(AppTheme.statusError)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()
            }
        }
        .padding(10)
        .background(AppTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                            Button("删除") {
                                pendingDelete = .checkRecord(record.id)
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(AppTheme.statusErrorSoft)
                            .foregroundStyle(AppTheme.statusError)
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

                                Button("删除") {
                                    pendingDelete = .appointment(id: appointment.id, title: appointment.title)
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(AppTheme.statusErrorSoft)
                                .foregroundStyle(AppTheme.statusError)
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

    private var medicationPeriodSections: [MedicationPeriodSection] {
        let nowMinutes = store.timeToMinutes(store.currentTimeText()) ?? 0

        return TimePeriod.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { period in
                let items = store.activeMedications
                    .filter { $0.period == period }
                    .sorted { lhs, rhs in
                        let left = lhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let right = rhs.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if left == right {
                            return lhs.id < rhs.id
                        }
                        return left.localizedCompare(right) == .orderedAscending
                    }
                guard !items.isEmpty else { return nil }

                let displayTime = ReminderScheduler.semanticAdjustedTimeText(
                    for: period,
                    baseTime: store.reminderTime(for: period)
                )
                let periodMinutes = store.timeToMinutes(displayTime) ?? 0
                let doneCount = items.filter { isMedicationDone($0) }.count
                return MedicationPeriodSection(
                    period: period,
                    displayTime: displayTime,
                    items: items,
                    doneCount: doneCount,
                    pendingCount: max(items.count - doneCount, 0),
                    isPast: nowMinutes > periodMinutes
                )
            }
    }

    private var activeAppointments: [AppointmentItem] {
        store.activeAppointments.sorted { $0.dueDate < $1.dueDate }
    }

    private var filteredRecords: [CheckRecord] {
        store.checkRecords(of: selectedCheckType)
    }

    private var medicationTotalCount: Int {
        medicationPeriodSections.reduce(0) { $0 + $1.items.count }
    }

    private var medicationDoneCount: Int {
        medicationPeriodSections.reduce(0) { $0 + $1.doneCount }
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

    private func isMedicationDone(_ item: MedicationItem) -> Bool {
        store.state.completedDailyTaskIDs.contains("med-\(item.id)")
    }

    private func toggleMedicationDone(_ item: MedicationItem) {
        let id = "med-\(item.id)"
        let doneBefore = store.state.completedDailyTaskIDs.contains(id)
        store.toggleDailyTask(id)
        if !doneBefore {
            ReminderScheduler.cancelFollowUp(for: item.period)
        }
    }

    private func isPeriodCollapsed(_ section: MedicationPeriodSection) -> Bool {
        if collapsedPastPeriods.contains(section.period) {
            return true
        }
        if section.isPast && !expandedPastPeriods.contains(section.period) {
            return true
        }
        return false
    }

    private func togglePeriodCollapsed(_ period: TimePeriod) {
        if collapsedPastPeriods.contains(period) {
            collapsedPastPeriods.remove(period)
            expandedPastPeriods.insert(period)
        } else {
            collapsedPastPeriods.insert(period)
            expandedPastPeriods.remove(period)
        }
    }

    private func confirmDelete() {
        guard let target = pendingDelete else { return }
        defer { pendingDelete = nil }

        switch target {
        case .medication(let id, _):
            store.deleteMedication(id: id)
        case .checkRecord(let id):
            store.deleteCheckRecord(id: id)
        case .appointment(let id, _):
            store.deleteAppointment(id: id)
        }
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
                            .foregroundStyle(AppTheme.statusError)
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
                        let delta = deltaText(key, previous: previous)
                        HStack(spacing: 3) {
                            Text(metricLabel(key))
                            Text(symbol)
                            if let delta {
                                Text(delta)
                            }
                        }
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

    private func deltaText(_ key: String, previous: CheckRecord) -> String? {
        guard
            let currentText = record.metrics.first(where: { $0.key == key })?.valueText,
            let previousText = previous.metrics.first(where: { $0.key == key })?.valueText,
            let current = Double(currentText),
            let previousValue = Double(previousText)
        else {
            return nil
        }
        let diff = current - previousValue
        let sign = diff >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", diff))"
    }

    private var typeColor: Color {
        switch record.type {
        case .pregnancyPanel: return AppTheme.actionPrimary
        case .nt: return AppTheme.statusInfo
        case .tang: return Color(hex: "A48BBF")
        case .ultrasound: return AppTheme.statusSuccess
        case .cbc: return Color(hex: "D4A94E")
        case .custom: return AppTheme.textSecondary
        }
    }

    private var typeSoftColor: Color {
        switch record.type {
        case .pregnancyPanel: return AppTheme.accentSoft
        case .nt: return AppTheme.statusInfoSoft
        case .tang: return Color(hex: "F3EFF8")
        case .ultrasound: return AppTheme.statusSuccessSoft
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
