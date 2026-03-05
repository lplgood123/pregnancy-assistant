import SwiftUI
import UIKit
import PhotosUI

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
    @State private var pendingBatchRecords: [CheckRecord] = []
    @State private var showBatchImportConfirm = false
    @State private var didApplyEditingRecord = false

    private let chatService = AIBackendChatService()
    private let initialCheckType: CheckType?
    private let editingCheckRecord: CheckRecord?

    init(
        initialTab: RecordAddTab = .check,
        initialCheckType: CheckType? = nil,
        editingCheckRecord: CheckRecord? = nil
    ) {
        _tab = State(initialValue: editingCheckRecord == nil ? initialTab : .check)
        self.initialCheckType = initialCheckType
        self.editingCheckRecord = editingCheckRecord
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
            .navigationTitle(editingCheckRecord == nil ? "新增记录" : "编辑记录")
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
                applyEditingRecordIfNeeded()
            }
            .onChange(of: checkType) { newType in
                seedMetricDictionariesIfNeeded(for: newType)
                if pendingBatchRecords.count > 1 {
                    pendingBatchRecords = []
                }
            }
            .confirmationDialog("导入检查报告", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
                Button("拍照") {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        errorText = "当前设备暂不支持拍照，先用相册上传也可以。"
                        return
                    }
                    imageSource = .camera
                }
                Button("从相册选择（可多选）") {
                    imageSource = .library
                }
                Button("取消", role: .cancel) { }
            }
            .sheet(item: $imageSource) { source in
                switch source {
                case .camera:
                    AppImagePicker(sourceType: .camera) { image in
                        Task {
                            await processPickedImages([image])
                        }
                    }
                case .library:
                    AppMultiImagePicker(selectionLimit: 0) { images in
                        Task {
                            await processPickedImages(images)
                        }
                    }
                }
            }
            .confirmationDialog(
                "识别到 \(pendingBatchRecords.count) 次妊娠三项",
                isPresented: $showBatchImportConfirm,
                titleVisibility: .visible
            ) {
                Button("一键导入 \(pendingBatchRecords.count) 条记录") {
                    importPendingBatchRecords()
                }
                Button("取消", role: .cancel) {
                    pendingBatchRecords = []
                }
            } message: {
                Text("将按识别到的报告日期分别创建记录。你之后可在“记录 > 检查报告”里逐条编辑。")
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

    private func applyEditingRecordIfNeeded() {
        guard let editingCheckRecord, !didApplyEditingRecord else { return }
        didApplyEditingRecord = true

        tab = .check
        checkType = editingCheckRecord.type
        checkDate = editingCheckRecord.checkTime
        checkNote = editingCheckRecord.note

        if checkType == .custom, let first = editingCheckRecord.metrics.first {
            customMetricLabel = first.label
            customMetricUnit = first.unit
        }

        for metric in editingCheckRecord.metrics {
            metricValues[metric.key] = metric.valueText
            if let low = metric.referenceLowText, !low.isEmpty {
                referenceLows[metric.key] = low
            }
            if let high = metric.referenceHighText, !high.isEmpty {
                referenceHighs[metric.key] = high
            }
        }

        includeReferenceRange = editingCheckRecord.metrics.contains { metric in
            !(metric.referenceLowText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
            !(metric.referenceHighText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
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
        if pendingBatchRecords.count > 1 {
            showBatchImportConfirm = true
            return
        }

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
            id: editingCheckRecord?.id ?? UUID().uuidString,
            type: checkType,
            checkTime: checkDate,
            metrics: metrics,
            note: checkNote.trimmingCharacters(in: .whitespacesAndNewlines),
            source: editingCheckRecord?.source ?? .manual,
            isArchived: false
        )

        if editingCheckRecord == nil {
            store.addCheckRecord(record)
        } else {
            store.updateCheckRecord(record)
        }
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

    private struct PregnancyPanelValues {
        var checkDate: Date?
        var hcg: String?
        var progesterone: String?
        var estradiol: String?

        var isComplete: Bool {
            hcg != nil && progesterone != nil && estradiol != nil
        }
    }

    private struct OCRPanelCandidate {
        var sourceIndex: Int
        var values: PregnancyPanelValues
    }

    @MainActor
    private func processPickedImages(_ images: [UIImage]) async {
        guard checkType == .pregnancyPanel else { return }
        guard !images.isEmpty else { return }

        ocrProcessing = true
        defer { ocrProcessing = false }
        errorText = ""
        ocrHint = ""

        pendingBatchRecords = []
        showBatchImportConfirm = false

        var candidates: [OCRPanelCandidate] = []
        var recognizedTextsByImage: [String] = []

        for (index, image) in images.enumerated() {
            ocrHint = images.count > 1
            ? "正在识别第 \(index + 1)/\(images.count) 张图片..."
            : "识别中..."

            do {
                let recognizedText = try await ImageOCRService.recognizeText(from: image)
                recognizedTextsByImage.append(recognizedText)

                var partial = extractPregnancyPanelPartial(from: recognizedText)
                if !partial.isComplete || partial.checkDate == nil {
                    if let aiFilled = await fillPregnancyPanelFromAI(recognizedText) {
                        if partial.hcg == nil { partial.hcg = aiFilled.hcg }
                        if partial.progesterone == nil { partial.progesterone = aiFilled.progesterone }
                        if partial.estradiol == nil { partial.estradiol = aiFilled.estradiol }
                        if partial.checkDate == nil { partial.checkDate = aiFilled.checkDate }
                    }
                }

                candidates.append(OCRPanelCandidate(sourceIndex: index, values: partial))
            } catch {
                continue
            }
        }

        guard !recognizedTextsByImage.isEmpty else {
            errorText = "这张图片没识别成功，换一张更清晰的我们再试。"
            return
        }

        // 多图时优先让 AI 判断“1 次还是多次”，并返回每次的日期与指标。
        var resolvedPanels: [PregnancyPanelValues] = []
        if images.count > 1 {
            ocrHint = "正在判断是 1 次还是多次检查..."
            resolvedPanels = await inferPregnancyPanelsFromAI(recognizedTextsByImage)
        }

        if resolvedPanels.isEmpty {
            resolvedPanels = mergeCandidatesByDate(candidates)
        }
        resolvedPanels = resolvedPanels.filter { $0.isComplete }

        guard !resolvedPanels.isEmpty else {
            errorText = "暂时没识别出完整妊娠三项，你可以补传更清晰图片或手动填写。"
            ocrHint = images.count > 1 ? "已完成 \(images.count) 张图片识别。": ""
            return
        }

        if resolvedPanels.count == 1, let panel = resolvedPanels.first {
            applySinglePanelToForm(panel)
            return
        }

        let records = makeBatchRecords(from: resolvedPanels)
        if records.count > 1 {
            pendingBatchRecords = records
            ocrHint = "已识别到 \(records.count) 次妊娠三项。点击保存将批量导入。"
            showBatchImportConfirm = false
            return
        }

        if let only = records.first {
            applySinglePanelToForm(
                PregnancyPanelValues(
                    checkDate: only.checkTime,
                    hcg: only.metrics.first(where: { $0.key == "hcg" })?.valueText,
                    progesterone: only.metrics.first(where: { $0.key == "progesterone" })?.valueText,
                    estradiol: only.metrics.first(where: { $0.key == "estradiol" })?.valueText
                )
            )
        }
    }

    private func fillPregnancyPanelFromAI(_ recognizedText: String) async -> PregnancyPanelValues? {
        let config = store.currentAIConfig()
        guard !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let prompt = """
        这是检查报告 OCR 文本，请按妊娠三项提取：HCG、孕酮、E2、检查日期。
        只返回结构化意图 JSON，格式如下：
        {
          "intent": "extract_pregnancy_panel",
          "slots": {
            "hcg": "...",
            "progesterone": "...",
            "estradiol": "...",
            "check_date": "YYYY-MM-DD（找不到可留空）"
          }
        }
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
            let date = parseDateString(action.slots["check_date"])
            if hcg == nil, p == nil, e2 == nil, date == nil { return nil }
            return PregnancyPanelValues(checkDate: date, hcg: hcg, progesterone: p, estradiol: e2)
        } catch {
            return nil
        }
    }

    private func inferPregnancyPanelsFromAI(_ recognizedTextsByImage: [String]) async -> [PregnancyPanelValues] {
        let config = store.currentAIConfig()
        guard !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard !recognizedTextsByImage.isEmpty else { return [] }

        let combined = recognizedTextsByImage.enumerated().map { index, text in
            "[图片\(index + 1)]\n\(text)"
        }.joined(separator: "\n\n")

        let prompt = """
        以下是多张妊娠三项报告 OCR 文本。请判断这些内容对应 1 次还是多次检查，并按“每次检查”输出数组。
        只返回结构化意图 JSON，格式如下：
        {
          "intent": "extract_pregnancy_panel_batch",
          "slots": {
            "panels": [
              {"check_date":"YYYY-MM-DD（无则空）","hcg":"...","progesterone":"...","estradiol":"..."}
            ]
          }
        }
        OCR 文本：
        \(combined)
        """

        do {
            let jsonText = try await chatService.sendWithRecovery(
                config: config,
                context: store.aiContextSummary(),
                history: store.aiConversation(),
                userInput: prompt,
                onStage: nil
            )
            guard let action = AIParse.parse(jsonText) else { return [] }
            guard let panelsRaw = action.slots["panels"], !panelsRaw.isEmpty else { return [] }
            guard let data = panelsRaw.data(using: .utf8),
                  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }

            return items.compactMap { item in
                let hcg = firstNumericText(from: item["hcg"] as? String)
                let p = firstNumericText(from: item["progesterone"] as? String)
                let e2 = firstNumericText(from: item["estradiol"] as? String)
                let date = parseDateString(item["check_date"] as? String)
                if hcg == nil, p == nil, e2 == nil, date == nil { return nil }
                return PregnancyPanelValues(checkDate: date, hcg: hcg, progesterone: p, estradiol: e2)
            }
        } catch {
            return []
        }
    }

    private func extractPregnancyPanelPartial(from text: String) -> PregnancyPanelValues {
        let date = extractDateFromText(text)
        let hcg = normalizedText(firstCapture(in: text, patterns: [
            #"(?i)hcg[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)β-?hcg[^0-9]*([0-9]+(?:\.[0-9]+)?)"#
        ]))
        let progesterone = normalizedText(firstCapture(in: text, patterns: [
            #"孕酮[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)progesterone[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)\bP\b[^0-9]*([0-9]+(?:\.[0-9]+)?)"#
        ]))
        let estradiol = normalizedText(firstCapture(in: text, patterns: [
            #"雌二醇[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)\bE2\b[^0-9]*([0-9]+(?:\.[0-9]+)?)"#,
            #"(?i)estradiol[^0-9]*([0-9]+(?:\.[0-9]+)?)"#
        ]))

        return PregnancyPanelValues(checkDate: date, hcg: hcg, progesterone: progesterone, estradiol: estradiol)
    }

    private func mergeCandidatesByDate(_ candidates: [OCRPanelCandidate]) -> [PregnancyPanelValues] {
        guard !candidates.isEmpty else { return [] }

        var grouped: [String: PregnancyPanelValues] = [:]
        var unknownPanels: [PregnancyPanelValues] = []

        for candidate in candidates.sorted(by: { $0.sourceIndex < $1.sourceIndex }) {
            let value = candidate.values
            if let date = value.checkDate {
                let key = dateKey(date)
                var merged = grouped[key] ?? PregnancyPanelValues(checkDate: date, hcg: nil, progesterone: nil, estradiol: nil)
                if merged.hcg == nil { merged.hcg = value.hcg }
                if merged.progesterone == nil { merged.progesterone = value.progesterone }
                if merged.estradiol == nil { merged.estradiol = value.estradiol }
                if merged.checkDate == nil { merged.checkDate = date }
                grouped[key] = merged
            } else {
                unknownPanels.append(value)
            }
        }

        var result = Array(grouped.values)
        if !unknownPanels.isEmpty {
            if result.count == 1 {
                var only = result[0]
                for panel in unknownPanels {
                    if only.hcg == nil { only.hcg = panel.hcg }
                    if only.progesterone == nil { only.progesterone = panel.progesterone }
                    if only.estradiol == nil { only.estradiol = panel.estradiol }
                }
                result[0] = only
            } else if result.isEmpty {
                var mergedUnknown = PregnancyPanelValues(checkDate: nil, hcg: nil, progesterone: nil, estradiol: nil)
                for panel in unknownPanels {
                    if mergedUnknown.hcg == nil { mergedUnknown.hcg = panel.hcg }
                    if mergedUnknown.progesterone == nil { mergedUnknown.progesterone = panel.progesterone }
                    if mergedUnknown.estradiol == nil { mergedUnknown.estradiol = panel.estradiol }
                }
                result.append(mergedUnknown)
            }
        }

        return result.sorted { lhs, rhs in
            switch (lhs.checkDate, rhs.checkDate) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return false
            }
        }
    }

    private func applySinglePanelToForm(_ panel: PregnancyPanelValues) {
        if let hcg = panel.hcg { metricValues["hcg"] = hcg }
        if let p = panel.progesterone { metricValues["progesterone"] = p }
        if let e2 = panel.estradiol { metricValues["estradiol"] = e2 }
        if let date = panel.checkDate {
            checkDate = date
            ocrHint = "已识别 HCG/孕酮/E2 和报告日期，请核对后保存。"
        } else {
            ocrHint = "已识别 HCG/孕酮/E2，但报告日期没识别到，当前先按今天保存。"
        }
        checkType = .pregnancyPanel
        pendingBatchRecords = []
    }

    private func makeBatchRecords(from panels: [PregnancyPanelValues]) -> [CheckRecord] {
        panels.compactMap { panel in
            guard let hcg = panel.hcg, let p = panel.progesterone, let e2 = panel.estradiol else { return nil }
            return CheckRecord(
                id: UUID().uuidString,
                type: .pregnancyPanel,
                checkTime: panel.checkDate ?? checkDate,
                metrics: [
                    CheckMetric(key: "hcg", label: "HCG", valueText: hcg, unit: "mIU/ml", referenceLowText: nil, referenceHighText: nil),
                    CheckMetric(key: "progesterone", label: "孕酮 P", valueText: p, unit: "ng/ml", referenceLowText: nil, referenceHighText: nil),
                    CheckMetric(key: "estradiol", label: "E2", valueText: e2, unit: "pg/ml", referenceLowText: nil, referenceHighText: nil)
                ],
                note: checkNote.trimmingCharacters(in: .whitespacesAndNewlines),
                source: .manual
            )
        }
    }

    private func importPendingBatchRecords() {
        guard !pendingBatchRecords.isEmpty else { return }
        pendingBatchRecords.forEach { store.addCheckRecord($0) }
        dismiss()
    }

    private func extractDateFromText(_ text: String) -> Date? {
        let patterns = [
            #"(20\d{2})[年\./\-](\d{1,2})[月\./\-](\d{1,2})[日号]?"#,
            #"(20\d{2})(\d{2})(\d{2})"#,
            #"(\d{1,2})[月\./\-](\d{1,2})[日号]?"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else { continue }

            if pattern == patterns[0] || pattern == patterns[1] {
                guard match.numberOfRanges >= 4,
                      let yearRange = Range(match.range(at: 1), in: text),
                      let monthRange = Range(match.range(at: 2), in: text),
                      let dayRange = Range(match.range(at: 3), in: text),
                      let year = Int(text[yearRange]),
                      let month = Int(text[monthRange]),
                      let day = Int(text[dayRange]) else {
                    continue
                }
                if let date = makeDate(year: year, month: month, day: day) {
                    return date
                }
            } else {
                guard match.numberOfRanges >= 3,
                      let monthRange = Range(match.range(at: 1), in: text),
                      let dayRange = Range(match.range(at: 2), in: text),
                      let month = Int(text[monthRange]),
                      let day = Int(text[dayRange]) else {
                    continue
                }
                let year = Calendar.current.component(.year, from: Date())
                if let date = makeDate(year: year, month: month, day: day) {
                    return date
                }
            }
        }
        return nil
    }

    private func parseDateString(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let date = extractDateFromText(trimmed) {
            return date
        }

        let formats = ["yyyy-MM-dd", "yyyy/M/d", "yyyy.M.d", "yyyy年M月d日"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return Calendar.current.startOfDay(for: date)
            }
        }
        return nil
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), (2000...2100).contains(year) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

    private func normalizedText(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AppMultiImagePicker: UIViewControllerRepresentable {
    var selectionLimit: Int = 0
    let onPicked: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, dismiss: dismiss)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: ([UIImage]) -> Void
        private let dismiss: DismissAction
        private let lock = NSLock()

        init(onPicked: @escaping ([UIImage]) -> Void, dismiss: DismissAction) {
            self.onPicked = onPicked
            self.dismiss = dismiss
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                dismiss()
                return
            }

            var orderedImages: [UIImage?] = Array(repeating: nil, count: results.count)
            let group = DispatchGroup()

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    defer { group.leave() }
                    guard let self, let image = object as? UIImage else { return }
                    self.lock.lock()
                    orderedImages[index] = image
                    self.lock.unlock()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                self.onPicked(orderedImages.compactMap { $0 })
                self.dismiss()
            }
        }
    }
}

#Preview {
    RecordAddView()
        .environmentObject(PregnancyStore())
}
