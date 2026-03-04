import SwiftUI
import UIKit

enum RecordAddTab: String, CaseIterable, Identifiable {
    case check = "检查报告"
    case medication = "用药/补剂"

    var id: String { rawValue }
}

struct RecordAddView: View {
    private enum ImageSource: Identifiable {
        case camera
        case library

        var id: Int {
            switch self {
            case .camera: return 1
            case .library: return 2
            }
        }

        var sourceType: UIImagePickerController.SourceType {
            switch self {
            case .camera: return .camera
            case .library: return .photoLibrary
            }
        }
    }

    private struct MetricTemplate: Identifiable {
        var id: String { key }
        var key: String
        var label: String
        var unit: String
        var placeholder: String
    }

    @EnvironmentObject private var store: PregnancyStore
    @Environment(\.dismiss) private var dismiss

    @State private var tab: RecordAddTab

    @State private var checkType: CheckType = .pregnancyPanel
    @State private var checkDate = Date()
    @State private var checkNote = ""
    @State private var includeReferenceRange = false
    @State private var metricValues: [String: String] = [:]
    @State private var referenceLows: [String: String] = [:]
    @State private var referenceHighs: [String: String] = [:]
    @State private var customMetricLabel = ""
    @State private var customMetricUnit = ""

    @State private var medName = ""
    @State private var medDosage = ""
    @State private var medNote = ""
    @State private var medPeriod: TimePeriod = .afterDinner

    @State private var errorText = ""
    @State private var showImageSourceDialog = false
    @State private var imageSource: ImageSource?
    @State private var ocrProcessing = false
    @State private var ocrHint = ""

    private let chatService = AIBackendChatService()
    private let initialCheckType: CheckType?

    init(initialTab: RecordAddTab = .check, initialCheckType: CheckType? = nil) {
        _tab = State(initialValue: initialTab)
        self.initialCheckType = initialCheckType
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        pickerSection

                        if tab == .check {
                            checkFormSection
                            referenceToggleSection
                            if includeReferenceRange {
                                referenceFormSection
                            }
                            hintCard(
                                systemImage: "message",
                                text: "也可以在首页直接说“今天NT 1.2mm”或“妊娠三项 HCG 12000，孕酮18，E2 320”，我会帮你自动记录。"
                            )
                        } else {
                            medicationFormSection
                            hintCard(
                                systemImage: "clock",
                                text: "提醒会按你设置的时间准时触发，建议和日常作息一致。"
                            )
                        }

                        if !errorText.isEmpty {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.statusError)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("新增记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .font(AppTheme.bodyFont)
            .onAppear {
                if let initialCheckType {
                    checkType = initialCheckType
                }
                seedMetricDictionariesIfNeeded(for: checkType)
            }
            .onChange(of: checkType) { _, newType in
                seedMetricDictionariesIfNeeded(for: newType)
            }
            .confirmationDialog("导入检查报告", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
                Button("拍照") {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        errorText = "当前设备不支持拍照，请改用相册上传。"
                        return
                    }
                    imageSource = .camera
                }
                Button("从相册选择") {
                    imageSource = .library
                }
                Button("取消", role: .cancel) { }
            }
            .sheet(item: $imageSource) { source in
                AppImagePicker(sourceType: source.sourceType) { image in
                    Task {
                        await processPickedImage(image)
                    }
                }
            }
        }
    }

    private var pickerSection: some View {
        AppCard {
            Picker("类型", selection: $tab) {
                ForEach(RecordAddTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
    }

    private var checkFormSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("检查报告")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textHint)

                Picker("报告类型", selection: $checkType) {
                    ForEach(availableCheckTypes, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }

                AppDateField("报告日期", selection: $checkDate, titleWidth: 88, displayFormat: "yyyy年M月d日")

                if checkType == .pregnancyPanel {
                    HStack(spacing: 8) {
                        Button {
                            showImageSourceDialog = true
                        } label: {
                            Label("拍照/上传识别", systemImage: "camera.viewfinder")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.actionPrimary)
                                .frame(minHeight: 44)
                                .padding(.horizontal, 10)
                                .background(AppTheme.accentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(ocrProcessing)

                        if ocrProcessing {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("识别中...")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    if !ocrHint.isEmpty {
                        Text(ocrHint)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                if checkType == .custom {
                    TextField("指标名称（例如：甲功）", text: $customMetricLabel)
                }

                VStack(spacing: 0) {
                    valueHeaderRow
                    ForEach(currentTemplates) { template in
                        metricInputRow(template)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if checkType == .custom {
                    TextField("单位（可选）", text: $customMetricUnit)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                TextField("备注（可选）", text: $checkNote, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .padding(.horizontal)
    }

    private var referenceToggleSection: some View {
        Button {
            includeReferenceRange.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: includeReferenceRange ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(includeReferenceRange ? AppTheme.actionPrimary : AppTheme.textHint)
                Text("补充报告单参考范围（可选）")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var referenceFormSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("参考范围")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textHint)

                ForEach(currentTemplates) { template in
                    HStack(spacing: 8) {
                        Text(template.label)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: 70, alignment: .leading)

                        TextField("最小", text: binding(in: $referenceLows, key: template.key))
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        Text("-")
                            .foregroundStyle(AppTheme.textHint)
                        TextField("最大", text: binding(in: $referenceHighs, key: template.key))
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)

                        if !template.unit.isEmpty {
                            Text(template.unit)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textHint)
                                .frame(width: 52, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var medicationFormSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("用药/补剂")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textHint)

                TextField("名称", text: $medName)
                TextField("剂量（例如 0.4mg / 1片）", text: $medDosage)
                Picker("时间", selection: $medPeriod) {
                    ForEach(TimePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                TextField("备注（可选）", text: $medNote)
            }
        }
        .padding(.horizontal)
    }

    private var valueHeaderRow: some View {
        HStack {
            Text("指标")
                .font(.caption)
                .foregroundStyle(AppTheme.textHint)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Text("数值")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textHint)
                .frame(width: 110)
            Text("单位")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textHint)
                .frame(width: 70)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.surfaceMuted)
    }

    private func metricInputRow(_ template: MetricTemplate) -> some View {
        HStack {
            Text(template.label)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 90, alignment: .leading)

            TextField(template.placeholder, text: binding(in: $metricValues, key: template.key))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            Text(template.unit)
                .font(.caption)
                .foregroundStyle(AppTheme.textHint)
                .frame(width: 70)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.card)
        .overlay(
            Rectangle()
                .fill(AppTheme.borderLight)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func hintCard(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.actionPrimary)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(AppTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var availableCheckTypes: [CheckType] {
        store.supportedCheckTypes + [.custom]
    }

    private var currentTemplates: [MetricTemplate] {
        switch checkType {
        case .pregnancyPanel:
            return [
                MetricTemplate(key: "hcg", label: "HCG", unit: "mIU/ml", placeholder: "例如 12000"),
                MetricTemplate(key: "progesterone", label: "孕酮 P", unit: "ng/ml", placeholder: "例如 18"),
                MetricTemplate(key: "estradiol", label: "E2", unit: "pg/ml", placeholder: "例如 320")
            ]
        case .nt:
            return [
                MetricTemplate(key: "nt", label: "NT值", unit: "mm", placeholder: "例如 1.2")
            ]
        case .tang:
            return [
                MetricTemplate(key: "trisomy21", label: "21三体", unit: "", placeholder: "例如 1/8500"),
                MetricTemplate(key: "trisomy18", label: "18三体", unit: "", placeholder: "例如 1/12000")
            ]
        case .ultrasound:
            return [
                MetricTemplate(key: "bpd", label: "双顶径 BPD", unit: "mm", placeholder: "例如 45"),
                MetricTemplate(key: "fl", label: "股骨长 FL", unit: "mm", placeholder: "例如 30"),
                MetricTemplate(key: "fhr", label: "胎心率 FHR", unit: "bpm", placeholder: "例如 150")
            ]
        case .cbc:
            return [
                MetricTemplate(key: "hb", label: "血红蛋白", unit: "g/L", placeholder: "例如 115"),
                MetricTemplate(key: "wbc", label: "白细胞", unit: "10^9/L", placeholder: "例如 8.2"),
                MetricTemplate(key: "plt", label: "血小板", unit: "10^9/L", placeholder: "例如 210")
            ]
        case .custom:
            return [
                MetricTemplate(
                    key: "custom_metric",
                    label: customMetricLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "自定义指标" : customMetricLabel,
                    unit: customMetricUnit,
                    placeholder: "填写数值或结果"
                )
            ]
        }
    }

    private func seedMetricDictionariesIfNeeded(for type: CheckType) {
        for template in templates(for: type) {
            if metricValues[template.key] == nil {
                metricValues[template.key] = ""
            }
            if referenceLows[template.key] == nil {
                referenceLows[template.key] = ""
            }
            if referenceHighs[template.key] == nil {
                referenceHighs[template.key] = ""
            }
        }
    }

    private func templates(for type: CheckType) -> [MetricTemplate] {
        switch type {
        case .pregnancyPanel:
            return [
                MetricTemplate(key: "hcg", label: "HCG", unit: "mIU/ml", placeholder: ""),
                MetricTemplate(key: "progesterone", label: "孕酮 P", unit: "ng/ml", placeholder: ""),
                MetricTemplate(key: "estradiol", label: "E2", unit: "pg/ml", placeholder: "")
            ]
        case .nt:
            return [MetricTemplate(key: "nt", label: "NT值", unit: "mm", placeholder: "")]
        case .tang:
            return [
                MetricTemplate(key: "trisomy21", label: "21三体", unit: "", placeholder: ""),
                MetricTemplate(key: "trisomy18", label: "18三体", unit: "", placeholder: "")
            ]
        case .ultrasound:
            return [
                MetricTemplate(key: "bpd", label: "双顶径 BPD", unit: "mm", placeholder: ""),
                MetricTemplate(key: "fl", label: "股骨长 FL", unit: "mm", placeholder: ""),
                MetricTemplate(key: "fhr", label: "胎心率 FHR", unit: "bpm", placeholder: "")
            ]
        case .cbc:
            return [
                MetricTemplate(key: "hb", label: "血红蛋白", unit: "g/L", placeholder: ""),
                MetricTemplate(key: "wbc", label: "白细胞", unit: "10^9/L", placeholder: ""),
                MetricTemplate(key: "plt", label: "血小板", unit: "10^9/L", placeholder: "")
            ]
        case .custom:
            return [MetricTemplate(key: "custom_metric", label: "自定义指标", unit: "", placeholder: "")]
        }
    }

    private func binding(in dict: Binding<[String: String]>, key: String) -> Binding<String> {
        Binding(
            get: { dict.wrappedValue[key] ?? "" },
            set: { dict.wrappedValue[key] = $0 }
        )
    }

    private func save() {
        errorText = ""
        ocrHint = ""
        switch tab {
        case .check:
            saveCheckRecord()
        case .medication:
            saveMedication()
        }
    }

    private func saveCheckRecord() {
        let templates = currentTemplates

        var metrics: [CheckMetric] = []
        for template in templates {
            let value = (metricValues[template.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                errorText = "请填写\(template.label)的结果"
                return
            }

            let low = includeReferenceRange ? (referenceLows[template.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let high = includeReferenceRange ? (referenceHighs[template.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""

            metrics.append(
                CheckMetric(
                    key: template.key,
                    label: template.label,
                    valueText: value,
                    unit: template.unit,
                    referenceLowText: low.isEmpty ? nil : low,
                    referenceHighText: high.isEmpty ? nil : high
                )
            )
        }

        let record = CheckRecord(
            id: UUID().uuidString,
            type: checkType,
            checkTime: checkDate,
            metrics: metrics,
            note: checkNote.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .manual
        )

        store.addCheckRecord(record)
        dismiss()
    }

    private func saveMedication() {
        let name = medName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            errorText = "请填写用药名称"
            return
        }

        let med = MedicationItem(
            id: UUID().uuidString,
            period: medPeriod,
            name: name,
            dosage: medDosage.trimmingCharacters(in: .whitespacesAndNewlines),
            note: medNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        store.addMedication(med)
        dismiss()
    }

    private func processPickedImage(_ image: UIImage) async {
        guard checkType == .pregnancyPanel else { return }
        ocrProcessing = true
        defer { ocrProcessing = false }
        errorText = ""
        ocrHint = ""

        do {
            let recognizedText = try await ImageOCRService.recognizeText(from: image)
            if let filled = await fillPregnancyPanelFromAI(recognizedText) ?? fillPregnancyPanelFromRegex(recognizedText) {
                metricValues["hcg"] = filled.hcg
                metricValues["progesterone"] = filled.progesterone
                metricValues["estradiol"] = filled.estradiol
                checkType = .pregnancyPanel
                ocrHint = "已自动识别 HCG/孕酮/E2，请核对后保存。"
            } else {
                errorText = "未识别到完整的妊娠三项，请补充手动输入。"
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "图片识别失败，请稍后重试。"
            errorText = message
        }
    }

    private func fillPregnancyPanelFromAI(_ recognizedText: String) async -> (hcg: String, progesterone: String, estradiol: String)? {
        let config = store.currentAIConfig()
        guard !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let prompt = """
        这是检查报告 OCR 文本，请按妊娠三项提取：HCG、孕酮、E2。只返回结构化意图 JSON。
        OCR 文本：
        \(recognizedText)
        """

        do {
            let jsonText = try await chatService.sendWithRecovery(
                config: config,
                context: store.aiContextSummary(),
                history: store.aiConversation(),
                userInput: prompt,
                onStage: nil
            )
            guard let action = AIParse.parse(jsonText) else { return nil }
            let hcg = firstNumericText(from: action.slots["hcg"])
            let p = firstNumericText(from: action.slots["progesterone"])
            let e2 = firstNumericText(from: action.slots["estradiol"])
            guard let hcg, let p, let e2 else { return nil }
            return (hcg: hcg, progesterone: p, estradiol: e2)
        } catch {
            return nil
        }
    }

    private func fillPregnancyPanelFromRegex(_ text: String) -> (hcg: String, progesterone: String, estradiol: String)? {
        let hcg = firstCapture(in: text, patterns: [
            #"(?i)hcg[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)β-?hcg[^0-9]*([0-9]+(?:\.[0-9]+)?)"#
        ])
        let progesterone = firstCapture(in: text, patterns: [
            #"孕酮[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)progesterone[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)\bP\b[^0-9]*([0-9]+(?:\.[0-9]+)?)"#
        ])
        let estradiol = firstCapture(in: text, patterns: [
            #"雌二醇[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)\bE2\b[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)estradiol[^0-9]*([0-9]+(?:\.[0-9]+)?)"#
        ])

        guard let hcg, let progesterone, let estradiol else { return nil }
        return (hcg: hcg, progesterone: progesterone, estradiol: estradiol)
    }

    private func firstCapture(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func firstNumericText(from raw: String?) -> String? {
        guard let raw else { return nil }
        if let direct = firstCapture(in: raw, patterns: [#"([0-9]+(?:\.[0-9]+)?)"#]) {
            return direct
        }
        return nil
    }
}

#Preview {
    RecordAddView()
        .environmentObject(PregnancyStore())
}
