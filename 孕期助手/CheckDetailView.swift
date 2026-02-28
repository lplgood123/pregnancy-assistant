import SwiftUI

struct CheckDetailView: View {
    @EnvironmentObject private var store: PregnancyStore

    let record: CheckRecord
    let previous: CheckRecord?
    let gestationalText: String

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(record.type.title)详情")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("检查日期：\(formatDate(record.checkTime)) · 孕\(gestationalText)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("本次结果 vs 上次")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textHint)
                            VStack(spacing: 0) {
                                headerRow
                                ForEach(record.metrics) { metric in
                                    metricRow(metric: metric)
                                }
                            }
                            .background(AppTheme.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        }
                    }
                    .padding(.horizontal)

                    if record.type == .pregnancyPanel, let doublingCard = hcgDoublingCardText() {
                        HStack(spacing: 12) {
                            Image(systemName: "testtube.2")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.statusInfo)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(doublingCard)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                if let delta = panelDeltaText() {
                                    Text(delta)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(AppTheme.statusInfoSoft)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .padding(.horizontal)
                    }

                    if hasReferenceRange {
                        AppCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("参考范围对照")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.textHint)
                                ForEach(record.metrics) { metric in
                                    if let range = referenceRangeText(for: metric) {
                                        HStack {
                                            Text(metric.label)
                                                .font(.footnote.weight(.semibold))
                                                .foregroundStyle(AppTheme.textSecondary)
                                            Spacer()
                                            Text(range)
                                                .font(.footnote)
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                        if let status = referenceStatusText(for: metric) {
                                            Text(status)
                                                .font(.caption)
                                                .foregroundStyle(referenceStatusColor(for: metric))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        AppCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("备注")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                Text(record.note)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, AppLayout.scrollTailPadding)
            }
        }
        .navigationTitle("检查详情")
        .font(AppTheme.bodyFont)
    }

    private var headerRow: some View {
        HStack {
            Text("指标")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 72, alignment: .leading)
            Spacer()
            Text("本次")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 82)
            Text("上次")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textHint)
                .frame(width: 82)
            Text("趋势")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textHint)
                .frame(width: 40)
        }
        .padding(10)
        .background(AppTheme.surfaceMuted)
    }

    private func metricRow(metric: CheckMetric) -> some View {
        let previousMetric = previous?.metrics.first(where: { $0.key == metric.key })
        let previousText = previousMetric?.valueText
        let symbol = store.trendSymbol(current: metric.valueText, previous: previousText)

        return HStack {
            Text(metric.label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 72, alignment: .leading)
            Spacer()
            Text(displayValueText(metric))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 82)
            Text(previousDisplay(metric: previousMetric))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textHint)
                .frame(width: 82)
            Text(symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(trendColor(symbol: symbol))
                .frame(width: 40)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(AppTheme.card)
        .overlay(
            Rectangle()
                .fill(AppTheme.borderLight)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var hasReferenceRange: Bool {
        record.metrics.contains { metric in
            !(metric.referenceLowText?.isEmpty ?? true) || !(metric.referenceHighText?.isEmpty ?? true)
        }
    }

    private func referenceRangeText(for metric: CheckMetric) -> String? {
        let low = metric.referenceLowText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let high = metric.referenceHighText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if low.isEmpty && high.isEmpty { return nil }
        if !low.isEmpty && !high.isEmpty {
            return "\(low) - \(high) \(metric.unit)"
        }
        if !low.isEmpty {
            return ">= \(low) \(metric.unit)"
        }
        return "<= \(high) \(metric.unit)"
    }

    private func referenceStatusText(for metric: CheckMetric) -> String? {
        guard let current = Double(metric.valueText) else { return "仅展示参考范围，未自动判定" }
        let low = Double(metric.referenceLowText ?? "")
        let high = Double(metric.referenceHighText ?? "")

        if let low, current < low {
            return "低于参考范围"
        }
        if let high, current > high {
            return "高于参考范围"
        }
        if low != nil || high != nil {
            return "在参考范围内"
        }
        return nil
    }

    private func referenceStatusColor(for metric: CheckMetric) -> Color {
        guard let status = referenceStatusText(for: metric) else { return AppTheme.textSecondary }
        if status.contains("低于") || status.contains("高于") {
            return Color(hex: "D4727A")
        }
        if status.contains("参考范围内") {
            return Color(hex: "6BAB8A")
        }
        return AppTheme.textSecondary
    }

    private func panelDeltaText() -> String? {
        guard let previous else { return nil }
        let keys = ["hcg", "progesterone", "estradiol"]
        let labels = ["HCG", "P", "E2"]
        var parts: [String] = []

        for (index, key) in keys.enumerated() {
            guard
                let currentText = record.metrics.first(where: { $0.key == key })?.valueText,
                let previousText = previous.metrics.first(where: { $0.key == key })?.valueText,
                let current = Double(currentText),
                let previousValue = Double(previousText)
            else { continue }
            let diff = current - previousValue
            let sign = diff >= 0 ? "+" : ""
            parts.append("\(labels[index]) \(sign)\(String(format: "%.2f", diff))")
        }

        if parts.isEmpty { return nil }
        return "差异值：" + parts.joined(separator: " / ")
    }

    private func hcgDoublingCardText() -> String? {
        guard
            let previous,
            let currentHcg = record.metrics.first(where: { $0.key == "hcg" })?.valueText,
            let previousHcg = previous.metrics.first(where: { $0.key == "hcg" })?.valueText
        else { return nil }
        let hours = record.checkTime.timeIntervalSince(previous.checkTime) / 3600
        if let days = store.hcgDoublingDays(current: currentHcg, previous: previousHcg, hoursBetween: hours) {
            return "HCG 翻倍约 \(days) 天"
        }
        guard let c = Double(currentHcg), let p = Double(previousHcg), p > 0 else { return nil }
        return "HCG 倍数：\(String(format: "%.2f", c / p))x"
    }

    private func displayValueText(_ metric: CheckMetric) -> String {
        metric.unit.isEmpty ? metric.valueText : "\(metric.valueText)"
    }

    private func previousDisplay(metric: CheckMetric?) -> String {
        guard let metric else { return "-" }
        return metric.valueText
    }

    private func trendColor(symbol: String) -> Color {
        switch symbol {
        case "↑": return Color(hex: "6BAB8A")
        case "↓": return Color(hex: "D4727A")
        default: return AppTheme.textHint
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

#Preview {
    let store = PregnancyStore()
    let record = store.sortedCheckRecords().first ?? CheckRecord(
        id: UUID().uuidString,
        type: .pregnancyPanel,
        checkTime: Date(),
        metrics: [
            CheckMetric(key: "hcg", label: "HCG", valueText: "12000", unit: "mIU/ml", referenceLowText: "4000", referenceHighText: "100000"),
            CheckMetric(key: "progesterone", label: "孕酮 P", valueText: "18", unit: "ng/ml", referenceLowText: "15", referenceHighText: "60")
        ],
        note: "示例备注",
        source: .manual
    )

    return CheckDetailView(
        record: record,
        previous: store.previousCheckRecord(for: record),
        gestationalText: store.gestationalWeekText(for: record.checkTime)
    )
    .environmentObject(store)
}
