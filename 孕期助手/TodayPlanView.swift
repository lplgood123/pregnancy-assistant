import SwiftUI

struct TodayPlanView: View {
    @EnvironmentObject private var store: PregnancyStore
    @State private var showingAddSheet = false
    @State private var expandedBuckets: Set<TimelineBucket> = []

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .padding(.horizontal)

                        StatusProgressCard(title: "今日完成进度", done: doneCount, total: allItems.count)
                            .padding(.horizontal)

                        if sections.isEmpty {
                            AppCard {
                                Text("今天已清空，可新增事项")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .padding(.horizontal)
                        } else {
                            ForEach(sections) { section in
                                sectionView(section)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, AppLayout.scrollTailPadding)
                }
            }
            .navigationTitle("今日计划")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Text("+ 新增今日事项")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(AppTheme.actionPrimary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    Color.clear
                        .frame(height: AppLayout.dockBottomInsetAboveTabBar)
                        .allowsHitTesting(false)
                }
                .background(AppTheme.card.allowsHitTesting(false))
            }
            .sheet(isPresented: $showingAddSheet) {
                RecordAddView()
                    .environmentObject(store)
            }
            .onAppear {
                store.refreshForTodayIfNeeded()
            }
            .font(AppTheme.bodyFont)
        }
    }

    private var sections: [TimelineSection] {
        store.timelineSections(for: Date())
    }

    private var allItems: [TimelineItem] {
        sections.flatMap { $0.pendingItems + $0.completedItems }
    }

    private var doneCount: Int {
        allItems.filter(\.isCompleted).count
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(dateBadgeText())
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text("按时间段整理，今天共 \(allItems.count) 项")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func sectionView(_ section: TimelineSection) -> some View {
        let expanded = expandedBuckets.contains(section.bucket)
        return VStack(alignment: .leading, spacing: 8) {
            TimelineSectionHeader(
                title: section.bucket.title,
                completedCount: section.completedItems.count,
                expanded: expanded
            ) {
                toggleCompleted(in: section.bucket)
            }

            if section.pendingItems.isEmpty && !expanded && !section.completedItems.isEmpty {
                Text("本时段待办已清空")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textHint)
                    .padding(.vertical, 4)
            }

            ForEach(section.pendingItems) { item in
                PlanTaskRow(item: item) {
                    handleAction(item)
                }
            }

            if expanded {
                ForEach(section.completedItems) { item in
                    PlanTaskRow(item: item) {
                        handleAction(item)
                    }
                }
            }
        }
    }

    private func toggleCompleted(in bucket: TimelineBucket) {
        if expandedBuckets.contains(bucket) {
            expandedBuckets.remove(bucket)
        } else {
            expandedBuckets.insert(bucket)
        }
    }

    private func handleAction(_ item: TimelineItem) {
        switch item.kind {
        case .appointment:
            store.toggleAppointment(item.sourceID)
        case .medication, .habit, .check:
            store.toggleDailyTask(item.sourceID)
            if store.state.completedDailyTaskIDs.contains(item.sourceID),
               let period = store.periodFromSubtitle(item.subtitle) {
                ReminderScheduler.cancelFollowUp(for: period)
            }
        }
    }

    private func dateBadgeText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        let dateText = formatter.string(from: Date())
        let weekday = Calendar.current.component(.weekday, from: Date())
        let weekText = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][max(weekday - 1, 0)]
        return "\(dateText) · \(weekText)"
    }
}

#Preview {
    TodayPlanView()
        .environmentObject(PregnancyStore())
}
