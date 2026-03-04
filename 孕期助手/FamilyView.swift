import SwiftUI

struct FamilyView: View {
    @EnvironmentObject private var store: PregnancyStore

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ReadOnlyBanner(text: "当前为只读模式，家属只能查看，不能修改。")
                        .padding(.horizontal)

                    profileCard
                        .padding(.horizontal)

                    SectionCard(title: "今日提醒摘要") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(dateText())
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                Spacer()
                                Text("\(doneCount)/\(todayItems.count) 已完成")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.actionPrimary)
                            }

                            ForEach(todayItems.prefix(6)) { item in
                                HStack(spacing: 10) {
                                    Image(systemName: icon(for: item.kind))
                                        .foregroundStyle(AppTheme.actionPrimary)
                                        .frame(width: 26, height: 26)
                                        .background(AppTheme.surfaceMuted)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(AppTheme.textPrimary)
                                        Text("\(item.timeText) · \(item.subtitle)")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(statusText(for: item))
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(statusSoftColor(for: item))
                                        .foregroundStyle(statusColor(for: item))
                                        .clipShape(Capsule())
                                }
                            }

                            if todayItems.isEmpty {
                                Text("今天暂无提醒")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal)

                    SectionCard(title: "近期检查报告") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(store.sortedCheckRecords().prefix(2)) { record in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        RecordTypeBadge(type: record.type)
                                        Spacer()
                                        Text("\(store.formatDate(record.checkTime)) · 孕\(store.gestationalWeekText(for: record.checkTime))")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }

                                    HStack(spacing: 12) {
                                        ForEach(record.metrics.prefix(3)) { metric in
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(metric.label)
                                                    .font(.caption2)
                                                    .foregroundStyle(AppTheme.textHint)
                                                Text(metric.valueText)
                                                    .font(.footnote.weight(.semibold))
                                                    .foregroundStyle(AppTheme.textPrimary)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                .padding(.bottom, 4)
                            }

                            if store.sortedCheckRecords().isEmpty {
                                Text("暂无检查报告")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: AppLayout.tabPageScrollTailPadding)
                }
                .padding(.top, 12)
            }
        }
        .navigationTitle("家属查看")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: "eye")
                    .foregroundStyle(AppTheme.statusInfo)
                Text("只读模式 · 家属只能查看，不能修改")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(AppTheme.background)
            .padding(.bottom, AppLayout.dockBottomInsetAboveTabBar)
            .allowsHitTesting(false)
        }
        .font(AppTheme.bodyFont)
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.2")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.actionPrimary)
                .frame(width: 54, height: 54)
                .background(LinearGradient(colors: [Color(hex: "FCEEE3"), Color(hex: "F9DCC8")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(store.state.profile.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text("孕 \(store.gestationalWeekText)")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                Text("预产期 \(store.formatDate(store.dueDate))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.actionPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.accentSoft)
                    .clipShape(Capsule())
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

    private var todayItems: [TimelineItem] {
        store.timelineItems(for: Date()).sorted {
            timeToMinutes($0.timeText) < timeToMinutes($1.timeText)
        }
    }

    private var doneCount: Int {
        todayItems.filter { $0.isCompleted }.count
    }

    private func statusText(for item: TimelineItem) -> String {
        if item.isCompleted { return "已完成" }
        return timeToMinutes(item.timeText) <= currentMinutes ? "待完成" : "未到"
    }

    private func statusColor(for item: TimelineItem) -> Color {
        if item.isCompleted { return AppTheme.statusSuccess }
        return timeToMinutes(item.timeText) <= currentMinutes ? AppTheme.actionPrimary : AppTheme.textSecondary
    }

    private func statusSoftColor(for item: TimelineItem) -> Color {
        if item.isCompleted { return AppTheme.statusSuccessSoft }
        return timeToMinutes(item.timeText) <= currentMinutes ? AppTheme.accentSoft : AppTheme.surfaceMuted
    }

    private func icon(for kind: TimelineItem.Kind) -> String {
        switch kind {
        case .medication: return "pills"
        case .habit: return "drop.fill"
        case .check: return "cross.case"
        case .appointment: return "calendar"
        }
    }

    private func dateText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        let day = formatter.string(from: Date())
        let weekday = Calendar.current.component(.weekday, from: Date())
        let weekText = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][max(weekday - 1, 0)]
        return "\(day) · \(weekText)"
    }

    private var currentMinutes: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return timeToMinutes(formatter.string(from: Date()))
    }

    private func timeToMinutes(_ text: String) -> Int {
        let comps = text.split(separator: ":")
        guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]) else { return 0 }
        return h * 60 + m
    }
}

#Preview {
    NavigationStack {
        FamilyView()
            .environmentObject(PregnancyStore())
    }
}
