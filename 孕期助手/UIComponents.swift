import SwiftUI

struct AppDateField: View {
    let title: String
    @Binding var selection: Date
    var titleWidth: CGFloat? = 88
    var displayFormat: String = "yyyy年M月d日"
    var range: ClosedRange<Date>? = nil

    @State private var showingPicker = false
    @State private var draftSelection = Date()

    init(
        _ title: String,
        selection: Binding<Date>,
        titleWidth: CGFloat? = 88,
        displayFormat: String = "yyyy年M月d日",
        range: ClosedRange<Date>? = nil
    ) {
        self.title = title
        _selection = selection
        self.titleWidth = titleWidth
        self.displayFormat = displayFormat
        self.range = range
    }

    var body: some View {
        HStack(spacing: 8) {
            if let titleWidth {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: titleWidth, alignment: .leading)
            } else {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 0)

            Button {
                draftSelection = selection
                showingPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(formattedDate(selection))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Image(systemName: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textHint)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .appTapTarget()
        }
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                VStack(spacing: 0) {
                    if let range {
                        DatePicker("", selection: $draftSelection, in: range, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .padding(.horizontal)
                            .padding(.top, 12)
                    } else {
                        DatePicker("", selection: $draftSelection, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .padding(.horizontal)
                            .padding(.top, 12)
                    }

                    Spacer(minLength: 0)
                }
                .navigationTitle("选择日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定") {
                            selection = draftSelection
                            showingPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = displayFormat
        return formatter.string(from: date)
    }
}

struct AppTimeField: View {
    let title: String
    @Binding var selection: Date
    var titleWidth: CGFloat? = 88
    var displayFormat: String = "HH:mm"

    @State private var showingPicker = false
    @State private var draftSelection = Date()

    init(
        _ title: String,
        selection: Binding<Date>,
        titleWidth: CGFloat? = 88,
        displayFormat: String = "HH:mm"
    ) {
        self.title = title
        _selection = selection
        self.titleWidth = titleWidth
        self.displayFormat = displayFormat
    }

    var body: some View {
        HStack(spacing: 8) {
            if let titleWidth {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: titleWidth, alignment: .leading)
            } else {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 0)

            Button {
                draftSelection = selection
                showingPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(formattedTime(selection))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Image(systemName: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textHint)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .appTapTarget()
        }
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                VStack(spacing: 0) {
                    DatePicker("", selection: $draftSelection, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .padding(.horizontal)
                        .padding(.top, 12)

                    Spacer(minLength: 0)
                }
                .navigationTitle("选择时间")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingPicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定") {
                            selection = draftSelection
                            showingPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = displayFormat
        return formatter.string(from: date)
    }
}

struct BadgePill: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppTheme.accentBrand)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.actionPrimary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .background(AppTheme.accentSoft)
        .clipShape(Capsule())
    }
}

struct HomeSummaryCard: View {
    let summary: HomeSummary
    let onOpenPlan: () -> Void

    private var progressText: String {
        "今天共 \(summary.total) 项，已完成 \(summary.done) 项"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.dateText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    HStack(spacing: 6) {
                        BadgePill(text: summary.gestationalText)
                        BadgePill(text: summary.dueDateText)
                    }
                }
                Spacer()
                Button("今天计划", action: onOpenPlan)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.actionPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(progressText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(summary.tomorrowHint)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                Text(summary.warmLine)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textHint)
            }
        }
        .padding(14)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .shadow(color: AppTheme.shadowSm, radius: 6, x: 0, y: 3)
    }
}

struct QuickCommandStrip: View {
    let commands: [QuickCommand]
    let onTap: (QuickCommand) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(commands) { command in
                    Button {
                        onTap(command)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: command.icon)
                                .font(.caption.weight(.semibold))
                            Text(command.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minHeight: 34)
                        .background(AppTheme.cardAlt)
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .appTapTarget(minHeight: 44)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }
}

struct TimelineSectionHeader: View {
    let title: String
    let completedCount: Int
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            if completedCount > 0 {
                Button(expanded ? "收起已完成（\(completedCount)）" : "展开已完成（\(completedCount)）", action: onToggle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

struct GreetingCard: View {
    let title: String
    let subtitle: String
    let ctaTitle: String
    let ctaAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
            Button(ctaTitle, action: ctaAction)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.actionPrimary)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: "F9E8DB"), Color(hex: "FCEEE3"), Color(hex: "FFF5ED")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct AIInsightBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "figure.2")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.actionPrimary)
                .frame(width: 28, height: 28)
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppTheme.textPrimary)
                .padding(12)
                .background(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct ReminderCard: View {
    let title: String
    let timeText: String
    let detailText: String
    let doneEnabled: Bool
    let onDone: () -> Void
    let onAdjust: () -> Void
    let onAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("下一个提醒")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Button("全部提醒", action: onAll)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 12) {
                Image(systemName: "pills")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.actionPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    if !detailText.isEmpty {
                        Text(detailText)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textHint)
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button("✓ 已服用", action: onDone)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(doneEnabled ? AppTheme.statusSuccessSoft : AppTheme.surfaceMuted)
                    .foregroundStyle(doneEnabled ? AppTheme.statusSuccess : AppTheme.textHint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(!doneEnabled)
                Button("调整时间", action: onAdjust)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(AppTheme.actionPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .shadow(color: AppTheme.shadowSm, radius: 6, x: 0, y: 3)
    }
}

struct TipsCard: View {
    struct Tip: Identifiable {
        var id = UUID()
        var text: String
        var done: Bool
    }

    let tips: [Tip]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日注意事项")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tips) { tip in
                    HStack(spacing: 8) {
                        Circle()
                            .stroke(AppTheme.border, lineWidth: 1)
                            .background(tip.done ? AppTheme.statusSuccess : Color.clear)
                            .clipShape(Circle())
                            .frame(width: 16, height: 16)
                        Text(tip.text)
                            .font(.footnote)
                            .foregroundStyle(tip.done ? AppTheme.textHint : AppTheme.textPrimary)
                            .strikethrough(tip.done)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

struct TimelineRow: View {
    let item: TimelineItem
    let onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.timeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 44, alignment: .trailing)

            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(AppTheme.border, lineWidth: 2)
                    .background(item.dotColor)
                    .clipShape(Circle())
                    .frame(width: 12, height: 12)
                    .overlay(item.isCompleted ? Text("✓").font(.caption2).foregroundStyle(.white) : nil)
                Rectangle()
                    .fill(AppTheme.borderLight)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TagPill(kind: item.kind)
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.isCompleted ? AppTheme.textHint : AppTheme.textPrimary)
                        .strikethrough(item.isCompleted)
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                if let onAction {
                    Button(item.isCompleted ? "✓ 已完成" : "标记完成") { onAction() }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(item.isCompleted ? AppTheme.statusSuccessSoft : AppTheme.actionPrimary)
                        .foregroundStyle(item.isCompleted ? AppTheme.statusSuccess : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(12)
            .background(AppTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .opacity(item.isCompleted ? 0.6 : 1)
        }
    }
}

struct TagPill: View {
    let kind: TimelineItem.Kind

    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(kind.colorSoft)
            .foregroundStyle(kind.color)
            .clipShape(Capsule())
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textHint)
            content
        }
        .padding(14)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

struct ReadOnlyBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.statusInfo)
                .frame(width: 34, height: 34)
                .background(Color(hex: "DCEAF4"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.statusInfo)
            Spacer()
        }
        .padding(12)
        .background(AppTheme.statusInfoSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatusProgressCard: View {
    let title: String
    let done: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textHint)
                Spacer()
                Text("\(done)/\(max(total, 0)) 已完成")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            GeometryReader { proxy in
                let ratio = total > 0 ? CGFloat(done) / CGFloat(total) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.surfaceMuted)
                        .frame(height: 10)
                    Capsule()
                        .fill(AppTheme.actionPrimary)
                        .frame(width: proxy.size.width * min(max(ratio, 0), 1), height: 10)
                }
            }
            .frame(height: 10)
            .accessibilityLabel(title)
            .accessibilityValue("\(done)/\(max(total, 0))")
        }
        .padding(14)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

struct RecordTypeBadge: View {
    let type: CheckType

    var body: some View {
        Text(type.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(softColor)
            .foregroundStyle(textColor)
            .clipShape(Capsule())
    }

    private var textColor: Color {
        switch type {
        case .pregnancyPanel: return AppTheme.actionPrimary
        case .nt: return AppTheme.statusInfo
        case .tang: return Color(hex: "A48BBF")
        case .ultrasound: return AppTheme.statusSuccess
        case .cbc: return Color(hex: "D4A94E")
        case .custom: return AppTheme.textSecondary
        }
    }

    private var softColor: Color {
        switch type {
        case .pregnancyPanel: return AppTheme.accentSoft
        case .nt: return AppTheme.statusInfoSoft
        case .tang: return Color(hex: "F3EFF8")
        case .ultrasound: return AppTheme.statusSuccessSoft
        case .cbc: return Color(hex: "FFF8E8")
        case .custom: return AppTheme.surfaceMuted
        }
    }
}

struct PlanTaskRow: View {
    let item: TimelineItem
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.timeText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(item.isCompleted ? AppTheme.textHint : AppTheme.textPrimary)
                .frame(width: 52, alignment: .leading)
                .padding(.top, 1)

            Button(action: onToggle) {
                Circle()
                    .stroke(item.isCompleted ? AppTheme.statusSuccess : AppTheme.border, lineWidth: 2)
                    .background(item.isCompleted ? AppTheme.statusSuccess : Color.clear)
                    .clipShape(Circle())
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .opacity(item.isCompleted ? 1 : 0)
                    )
            }
            .buttonStyle(.plain)
            .appTapTarget()
            .accessibilityLabel(item.isCompleted ? "标记为未完成" : "标记为已完成")
            .accessibilityValue(item.isCompleted ? "已完成" : "未完成")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isCompleted ? AppTheme.textHint : AppTheme.textPrimary)
                    .strikethrough(item.isCompleted)
                HStack(spacing: 6) {
                    TagPill(kind: item.kind)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(item.isCompleted ? 0.65 : 1)
    }
}

struct ProfileInfoRow: View {
    let icon: String
    let label: String
    let value: String
    var accentValue: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .frame(width: 28, height: 28)
                .background(AppTheme.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(label)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accentValue ? AppTheme.actionPrimary : AppTheme.textPrimary)
        }
        .padding(.vertical, 2)
    }
}
