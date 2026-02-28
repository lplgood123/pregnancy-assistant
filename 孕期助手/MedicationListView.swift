import SwiftUI

struct MedicationListView: View {
    private struct MedicationGroup: Identifiable {
        var id: String
        var name: String
        var items: [MedicationItem]

        var periods: [TimePeriod] {
            Array(Set(items.map(\.period))).sorted { $0.sortOrder < $1.sortOrder }
        }

        var dosageText: String {
            let values = Array(Set(items.map { $0.dosage.trimmingCharacters(in: .whitespacesAndNewlines) }))
                .filter { !$0.isEmpty }
            return values.joined(separator: " / ")
        }

        var detailText: String {
            let periodText = periods.map(\.rawValue).joined(separator: "、")
            if dosageText.isEmpty { return periodText }
            return "\(periodText) · \(dosageText)"
        }

        var frequencyText: String {
            periods.count <= 1 ? "每天1次" : "每天\(periods.count)次"
        }
    }

    @EnvironmentObject private var store: PregnancyStore

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("用药清单")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("当前 \(medicationGroups.count) 种用药/补剂")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .padding(.horizontal)

                        StatusProgressCard(
                            title: "今日用药完成",
                            done: medicationDoneCount,
                            total: medicationTotalCount
                        )
                        .padding(.horizontal)

                        if !dailyGroups.isEmpty {
                            groupSection(title: "每日服用", groups: dailyGroups)
                        }

                        if !multiGroups.isEmpty {
                            groupSection(title: "每日多次", groups: multiGroups)
                        }

                        AppCard {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "message")
                                    .foregroundStyle(AppTheme.actionPrimary)
                                Text("也可以在首页输入“帮我加一个药”，我会自动帮你创建并提醒。")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, AppLayout.scrollTailPadding)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                NavigationLink {
                    RecordAddView(initialTab: .medication)
                        .environmentObject(store)
                } label: {
                    Text("+ 新增用药 / 补剂")
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
            }
            .font(AppTheme.bodyFont)
        }
    }

    private func groupSection(title: String, groups: [MedicationGroup]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textHint)
                Text("\(groups.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.actionPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppTheme.accentSoft)
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            ForEach(groups) { group in
                medicationRow(group)
                    .padding(.horizontal)
            }
        }
    }

    private func medicationRow(_ group: MedicationGroup) -> some View {
        let done = groupDone(group)
        return HStack(spacing: 10) {
            Image(systemName: iconForMedication(group.name))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.actionPrimary)
                .frame(width: 36, height: 36)
                .background(AppTheme.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 10))

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
                    Text(group.detailText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(nextTimeText(for: group))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Button {
                    toggleGroupDone(group)
                } label: {
                    Circle()
                        .stroke(done ? Color(hex: "6BAB8A") : AppTheme.border, lineWidth: 2)
                        .background(done ? Color(hex: "6BAB8A") : Color.clear)
                        .clipShape(Circle())
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .opacity(done ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .appTapTarget()
                .accessibilityLabel(done ? "标记为未完成" : "标记为已完成")
                .accessibilityValue(done ? "已完成" : "未完成")
            }
        }
        .padding(12)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(done ? 0.65 : 1)
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
                let lOrder = lhs.periods.first?.sortOrder ?? 99
                let rOrder = rhs.periods.first?.sortOrder ?? 99
                if lOrder == rOrder { return lhs.name < rhs.name }
                return lOrder < rOrder
            }
    }

    private var dailyGroups: [MedicationGroup] {
        medicationGroups.filter { $0.periods.count <= 1 }
    }

    private var multiGroups: [MedicationGroup] {
        medicationGroups.filter { $0.periods.count > 1 }
    }

    private var medicationTotalCount: Int {
        store.medicationSectionsForToday().flatMap { $0.rows }.count
    }

    private var medicationDoneCount: Int {
        store.medicationSectionsForToday().flatMap { $0.rows }.filter { $0.isCompleted }.count
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

    private func nextTimeText(for group: MedicationGroup) -> String {
        let now = currentMinutes
        let times: [(text: String, minutes: Int)] = group.periods.compactMap { period in
            let base = store.reminderTime(for: period)
            let adjusted = ReminderScheduler.semanticAdjustedTimeText(for: period, baseTime: base)
            guard let minutes = timeToMinutes(adjusted) else { return nil }
            return (adjusted, minutes)
        }

        if let upcoming = times.filter({ $0.minutes >= now }).sorted(by: { $0.minutes < $1.minutes }).first {
            return upcoming.text
        }
        return times.sorted(by: { $0.minutes < $1.minutes }).first?.text ?? "--:--"
    }

    private var currentMinutes: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let text = formatter.string(from: Date())
        return timeToMinutes(text) ?? 0
    }

    private func timeToMinutes(_ text: String) -> Int? {
        let comps = text.split(separator: ":")
        guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]) else { return nil }
        return h * 60 + m
    }

    private func iconForMedication(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("钙") { return "circle.fill" }
        if lower.contains("dha") { return "drop.fill" }
        if lower.contains("维生素") { return "capsule.fill" }
        if lower.contains("叶酸") { return "leaf.fill" }
        return "pills"
    }
}

#Preview {
    MedicationListView()
        .environmentObject(PregnancyStore())
}
