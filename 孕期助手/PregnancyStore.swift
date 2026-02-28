import Foundation
import Combine
import SwiftUI

enum TimePeriod: String, Codable, CaseIterable, Identifiable {
    case wakeUp = "起床后"
    case afterBreakfast = "早饭后"
    case afterLunch = "午饭后"
    case afterDinner = "晚饭后"
    case beforeSleep = "睡前"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .wakeUp: return 0
        case .afterBreakfast: return 1
        case .afterLunch: return 2
        case .afterDinner: return 3
        case .beforeSleep: return 4
        }
    }
}

struct Profile: Codable {
    var name: String
    var gender: String
    var birthDate: Date
    var lastPeriodDate: Date
    var ivfTransferDate: Date
    var firstPositiveDate: Date
    var stepsGoal: Int
    var waterGoalML: Int
    var heightCM: String? = nil
    var weightKG: String? = nil
    var allergyHistory: String? = nil
    var doctorContact: String? = nil
}

struct MedicationItem: Identifiable, Codable {
    var id: String
    var period: TimePeriod
    var name: String
    var dosage: String
    var note: String
    var isArchived: Bool

    init(id: String, period: TimePeriod, name: String, dosage: String, note: String, isArchived: Bool = false) {
        self.id = id
        self.period = period
        self.name = name
        self.dosage = dosage
        self.note = note
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        period = try container.decode(TimePeriod.self, forKey: .period)
        name = try container.decode(String.self, forKey: .name)
        dosage = try container.decode(String.self, forKey: .dosage)
        note = try container.decode(String.self, forKey: .note)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

struct DailyHabitItem: Identifiable, Codable {
    var id: String
    var title: String
}

struct ExtraDailyItem: Identifiable, Codable {
    var id: String
    var period: TimePeriod
    var title: String
    var detail: String
}

struct TodayNoteItem: Identifiable, Codable {
    var id: String
    var dateKey: String
    var title: String
    var detail: String
    var createdAt: Date
}

struct AppointmentItem: Identifiable, Codable {
    var id: String
    var title: String
    var dueDate: Date
    var detail: String
    var isDone: Bool
    var isArchived: Bool

    init(id: String, title: String, dueDate: Date, detail: String, isDone: Bool, isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.detail = detail
        self.isDone = isDone
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        detail = try container.decode(String.self, forKey: .detail)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

struct InjectionPlan: Codable {
    var title: String
    var startDate: Date
    var endDate: Date
    var intervalDays: Int
    var detail: String
}

struct LabRecord: Identifiable, Codable {
    var id: String
    var checkTime: Date
    var progesterone: Double
    var estradiol: Double
    var hcg: Double
}

enum CheckType: String, Codable, CaseIterable, Identifiable {
    case pregnancyPanel = "pregnancy_panel"
    case nt = "nt"
    case tang = "tang"
    case ultrasound = "ultrasound"
    case cbc = "cbc"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pregnancyPanel: return "妊娠三项"
        case .nt: return "NT"
        case .tang: return "唐筛"
        case .ultrasound: return "B超"
        case .cbc: return "血常规"
        case .custom: return "其他"
        }
    }

    static func fromDisplay(_ text: String) -> CheckType {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("妊娠") { return .pregnancyPanel }
        if normalized.contains("nt") { return .nt }
        if normalized.contains("唐筛") { return .tang }
        if normalized.contains("b超") || normalized.contains("超声") { return .ultrasound }
        if normalized.contains("血常规") { return .cbc }
        if normalized == "pregnancy_panel" { return .pregnancyPanel }
        if normalized == "tang" { return .tang }
        if normalized == "ultrasound" { return .ultrasound }
        if normalized == "cbc" { return .cbc }
        if normalized == "custom" { return .custom }
        return .custom
    }
}

struct CheckMetric: Identifiable, Codable {
    var id: String { key }
    var key: String
    var label: String
    var valueText: String
    var unit: String
    var referenceLowText: String?
    var referenceHighText: String?
}

struct CheckRecord: Identifiable, Codable {
    enum Source: String, Codable {
        case manual
        case ai
    }

    var id: String
    var type: CheckType
    var checkTime: Date
    var metrics: [CheckMetric]
    var note: String
    var source: Source
    var isArchived: Bool

    init(
        id: String,
        type: CheckType,
        checkTime: Date,
        metrics: [CheckMetric],
        note: String,
        source: Source,
        isArchived: Bool = false
    ) {
        self.id = id
        self.type = type
        self.checkTime = checkTime
        self.metrics = metrics
        self.note = note
        self.source = source
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(CheckType.self, forKey: .type)
        checkTime = try container.decode(Date.self, forKey: .checkTime)
        metrics = try container.decode([CheckMetric].self, forKey: .metrics)
        note = try container.decode(String.self, forKey: .note)
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .manual
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

struct DailyHealthCheckin: Codable {
    var dateKey: String
    var abnormalSymptomIDs: [String]
    var weightKG: String
    var systolicBP: String
    var diastolicBP: String
    var heartRate: String
}

struct SymptomOption: Identifiable {
    var id: String
    var title: String
    var detail: String
}

struct PrepChecklistItem: Identifiable {
    var id: String
    var title: String
}

struct AIConfig: Codable {
    var baseURL: String
    var apiKey: String
    var model: String
}

enum MultimodalInputType: String, Codable {
    case text
    case image
    case audio
}

struct MultimodalInput: Codable {
    var type: MultimodalInputType
    var payloadRef: String
    var sourceMeta: String
}

struct ParseResult: Codable {
    var intent: String
    var slots: [String: String]
    var confidence: Double
    var needsHumanConfirm: Bool
}

struct PersonaProfile: Codable {
    var stylePreset: String
    var toneRules: [String]
    var forbiddenPhrases: [String]
    var safetyFallbacks: [String]
}

struct AIPendingAction: Codable, Identifiable {
    var id: String
    var intent: String
    var slots: [String: String]
    var createdAt: Date
}

struct ReminderConfig: Codable {
    var wakeUpTime: String
    var breakfastTime: String
    var lunchTime: String
    var dinnerTime: String
    var sleepTime: String
    var minutesBefore: Int

    init(
        wakeUpTime: String,
        breakfastTime: String,
        lunchTime: String,
        dinnerTime: String,
        sleepTime: String,
        minutesBefore: Int
    ) {
        self.wakeUpTime = wakeUpTime
        self.breakfastTime = breakfastTime
        self.lunchTime = lunchTime
        self.dinnerTime = dinnerTime
        self.sleepTime = sleepTime
        self.minutesBefore = minutesBefore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wakeUpTime = try container.decodeIfPresent(String.self, forKey: .wakeUpTime) ?? "07:00"
        breakfastTime = try container.decodeIfPresent(String.self, forKey: .breakfastTime) ?? "08:30"
        lunchTime = try container.decodeIfPresent(String.self, forKey: .lunchTime) ?? "12:30"
        dinnerTime = try container.decodeIfPresent(String.self, forKey: .dinnerTime) ?? "18:30"
        sleepTime = try container.decodeIfPresent(String.self, forKey: .sleepTime) ?? "22:30"
        minutesBefore = try container.decodeIfPresent(Int.self, forKey: .minutesBefore) ?? 0
    }
}

struct StoredAIMessage: Codable, Identifiable {
    var id: String
    var role: String
    var content: String
    var time: Date
}

struct FamilyBindingDraft: Codable {
    var relationName: String
    var relationPhone: String
    var inviteCodePlaceholder: String
    var updatedAt: Date
}

struct HomeSummaryCache: Codable {
    var dateKey: String
    var text: String
    var fingerprint: String
    var updatedAt: Date
}

struct AppState: Codable {
    var profile: Profile
    var medications: [MedicationItem]
    var dailyHabits: [DailyHabitItem]
    var extraDailyItems: [ExtraDailyItem]
    var todayNotes: [TodayNoteItem]
    var appointments: [AppointmentItem]
    var injectionPlan: InjectionPlan
    var labRecords: [LabRecord]
    var checkRecords: [CheckRecord]?
    var completionDateKey: String
    var completedDailyTaskIDs: [String]
    var dailyCheckin: DailyHealthCheckin?
    var appointmentPrepCheckedIDs: [String]?
    var aiConfig: AIConfig?
    var reminderConfig: ReminderConfig?
    var aiConversation: [StoredAIMessage]?
    var aiLongTermMemory: String?
    var aiPendingActions: [AIPendingAction]?
    var homeChatMessages: [HomeChatMessage]?
    var onboardingVersion: Int
    var onboardingCompleted: Bool
    var onboardingStep: Int
    var onboardingRequiredAtLeastOnce: Bool
    var profileOptionalFieldsSkipped: [String]
    var familyBindingDraft: FamilyBindingDraft?
    var homeSummaryCache: HomeSummaryCache?

    init(
        profile: Profile,
        medications: [MedicationItem],
        dailyHabits: [DailyHabitItem],
        extraDailyItems: [ExtraDailyItem],
        todayNotes: [TodayNoteItem],
        appointments: [AppointmentItem],
        injectionPlan: InjectionPlan,
        labRecords: [LabRecord],
        checkRecords: [CheckRecord]?,
        completionDateKey: String,
        completedDailyTaskIDs: [String],
        dailyCheckin: DailyHealthCheckin?,
        appointmentPrepCheckedIDs: [String]?,
        aiConfig: AIConfig?,
        reminderConfig: ReminderConfig?,
        aiConversation: [StoredAIMessage]?,
        aiLongTermMemory: String?,
        aiPendingActions: [AIPendingAction]?,
        homeChatMessages: [HomeChatMessage]?,
        onboardingVersion: Int,
        onboardingCompleted: Bool,
        onboardingStep: Int,
        onboardingRequiredAtLeastOnce: Bool,
        profileOptionalFieldsSkipped: [String],
        familyBindingDraft: FamilyBindingDraft?,
        homeSummaryCache: HomeSummaryCache?
    ) {
        self.profile = profile
        self.medications = medications
        self.dailyHabits = dailyHabits
        self.extraDailyItems = extraDailyItems
        self.todayNotes = todayNotes
        self.appointments = appointments
        self.injectionPlan = injectionPlan
        self.labRecords = labRecords
        self.checkRecords = checkRecords
        self.completionDateKey = completionDateKey
        self.completedDailyTaskIDs = completedDailyTaskIDs
        self.dailyCheckin = dailyCheckin
        self.appointmentPrepCheckedIDs = appointmentPrepCheckedIDs
        self.aiConfig = aiConfig
        self.reminderConfig = reminderConfig
        self.aiConversation = aiConversation
        self.aiLongTermMemory = aiLongTermMemory
        self.aiPendingActions = aiPendingActions
        self.homeChatMessages = homeChatMessages
        self.onboardingVersion = onboardingVersion
        self.onboardingCompleted = onboardingCompleted
        self.onboardingStep = onboardingStep
        self.onboardingRequiredAtLeastOnce = onboardingRequiredAtLeastOnce
        self.profileOptionalFieldsSkipped = profileOptionalFieldsSkipped
        self.familyBindingDraft = familyBindingDraft
        self.homeSummaryCache = homeSummaryCache
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case medications
        case dailyHabits
        case extraDailyItems
        case todayNotes
        case appointments
        case injectionPlan
        case labRecords
        case checkRecords
        case completionDateKey
        case completedDailyTaskIDs
        case dailyCheckin
        case appointmentPrepCheckedIDs
        case aiConfig
        case reminderConfig
        case aiConversation
        case aiLongTermMemory
        case aiPendingActions
        case homeChatMessages
        case onboardingVersion
        case onboardingCompleted
        case onboardingStep
        case onboardingRequiredAtLeastOnce
        case profileOptionalFieldsSkipped
        case familyBindingDraft
        case homeSummaryCache
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decode(Profile.self, forKey: .profile)
        medications = try container.decodeIfPresent([MedicationItem].self, forKey: .medications) ?? []
        dailyHabits = try container.decodeIfPresent([DailyHabitItem].self, forKey: .dailyHabits) ?? []
        extraDailyItems = try container.decodeIfPresent([ExtraDailyItem].self, forKey: .extraDailyItems) ?? []
        todayNotes = try container.decodeIfPresent([TodayNoteItem].self, forKey: .todayNotes) ?? []
        appointments = try container.decodeIfPresent([AppointmentItem].self, forKey: .appointments) ?? []
        injectionPlan = try container.decode(InjectionPlan.self, forKey: .injectionPlan)
        labRecords = try container.decodeIfPresent([LabRecord].self, forKey: .labRecords) ?? []
        checkRecords = try container.decodeIfPresent([CheckRecord].self, forKey: .checkRecords)
        completionDateKey = try container.decodeIfPresent(String.self, forKey: .completionDateKey) ?? ""
        completedDailyTaskIDs = try container.decodeIfPresent([String].self, forKey: .completedDailyTaskIDs) ?? []
        dailyCheckin = try container.decodeIfPresent(DailyHealthCheckin.self, forKey: .dailyCheckin)
        appointmentPrepCheckedIDs = try container.decodeIfPresent([String].self, forKey: .appointmentPrepCheckedIDs)
        aiConfig = try container.decodeIfPresent(AIConfig.self, forKey: .aiConfig)
        reminderConfig = try container.decodeIfPresent(ReminderConfig.self, forKey: .reminderConfig)
        aiConversation = try container.decodeIfPresent([StoredAIMessage].self, forKey: .aiConversation)
        aiLongTermMemory = try container.decodeIfPresent(String.self, forKey: .aiLongTermMemory)
        aiPendingActions = try container.decodeIfPresent([AIPendingAction].self, forKey: .aiPendingActions)
        homeChatMessages = try container.decodeIfPresent([HomeChatMessage].self, forKey: .homeChatMessages)
        onboardingVersion = try container.decodeIfPresent(Int.self, forKey: .onboardingVersion) ?? 0
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        onboardingStep = try container.decodeIfPresent(Int.self, forKey: .onboardingStep) ?? 1
        onboardingRequiredAtLeastOnce = try container.decodeIfPresent(Bool.self, forKey: .onboardingRequiredAtLeastOnce) ?? true
        profileOptionalFieldsSkipped = try container.decodeIfPresent([String].self, forKey: .profileOptionalFieldsSkipped) ?? []
        familyBindingDraft = try container.decodeIfPresent(FamilyBindingDraft.self, forKey: .familyBindingDraft)
        homeSummaryCache = try container.decodeIfPresent(HomeSummaryCache.self, forKey: .homeSummaryCache)
    }
}

struct DailyTaskRow: Identifiable {
    enum Kind {
        case daily
        case appointment
    }

    var id: String
    var title: String
    var subtitle: String
    var kind: Kind
    var isCompleted: Bool
}

struct DailyTaskSection: Identifiable {
    var id: String
    var title: String
    var rows: [DailyTaskRow]
}

struct MedicationTaskSection: Identifiable {
    var id: String
    var title: String
    var rows: [DailyTaskRow]
}

enum PregnancyStage {
    case early
    case middle
    case late
}

struct NextMedication {
    var id: String
    var period: TimePeriod
    var title: String
    var subtitle: String
    var timeText: String
}

struct QuickCommand: Identifiable, Hashable {
    var id: String { "\(title)-\(prompt)" }
    var title: String
    var prompt: String
    var icon: String
}

enum TimelineBucket: String, CaseIterable, Identifiable {
    case dawn
    case morning
    case noon
    case afternoon
    case evening
    case bedtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dawn: return "清晨"
        case .morning: return "上午"
        case .noon: return "中午"
        case .afternoon: return "下午"
        case .evening: return "晚上"
        case .bedtime: return "睡前"
        }
    }

    static func bucket(for minutes: Int) -> TimelineBucket {
        switch minutes {
        case 0..<360:
            return .dawn
        case 360..<660:
            return .morning
        case 660..<840:
            return .noon
        case 840..<1080:
            return .afternoon
        case 1080..<1290:
            return .evening
        default:
            return .bedtime
        }
    }
}

struct TimelineSection: Identifiable {
    var id: String { bucket.id }
    var bucket: TimelineBucket
    var pendingItems: [TimelineItem]
    var completedItems: [TimelineItem]
}

struct HomeSummary {
    var dateText: String
    var gestationalText: String
    var dueDateText: String
    var total: Int
    var done: Int
    var left: Int
    var tomorrowHint: String
    var warmLine: String
}

struct TimelineItem: Identifiable {
    enum Kind {
        case medication
        case habit
        case check
        case appointment

        var label: String {
            switch self {
            case .medication: return "用药"
            case .habit: return "习惯"
            case .check: return "检查"
            case .appointment: return "预约"
            }
        }

        var color: Color {
            switch self {
            case .medication: return AppTheme.actionPrimary
            case .habit: return Color(hex: "6BAB8A")
            case .check: return AppTheme.statusInfo
            case .appointment: return Color(hex: "A48BBF")
            }
        }

        var colorSoft: Color {
            switch self {
            case .medication: return AppTheme.accentSoft
            case .habit: return Color(hex: "EDF7F1")
            case .check: return AppTheme.statusInfoSoft
            case .appointment: return Color(hex: "F3EFF8")
            }
        }
    }

    var id: String
    var timeText: String
    var title: String
    var subtitle: String
    var kind: Kind
    var isCompleted: Bool
    var isActive: Bool
    var sourceID: String
    var isActionable: Bool

    var dotColor: Color {
        if isCompleted { return Color(hex: "6BAB8A") }
        if isActive { return AppTheme.accentSoft }
        return AppTheme.cardAlt
    }
}

enum GlobalBannerLevel {
    case success
    case info
    case error
}

struct GlobalBanner: Identifiable {
    var id: String
    var message: String
    var level: GlobalBannerLevel
}

final class PregnancyStore: ObservableObject {
    @Published var state: AppState {
        didSet {
            saveState()
        }
    }
    @Published private(set) var reminderSyncRevision = 0
    @Published var globalBanner: GlobalBanner?

    private let calendar = Calendar.current
    private let stateKey = "pregnancy_assistant_app_state_v2"
    private let onboardingSchemaVersion = 13
    private var bannerNonce = UUID()
    private let symptomOptionsCatalog: [SymptomOption] = [
        SymptomOption(id: "spotting", title: "阴道流血/褐色分泌物", detail: "出现时建议及时联系医生"),
        SymptomOption(id: "pain", title: "腹痛加重", detail: "持续或明显加重需就医"),
        SymptomOption(id: "vomit", title: "呕吐明显加重", detail: "无法进食饮水时需处理"),
        SymptomOption(id: "fever", title: "发热（>=37.8°C）", detail: "持续发热应尽快就诊")
    ]
    private let prepChecklistCatalog: [PrepChecklistItem] = [
        PrepChecklistItem(id: "prepare_reports", title: "带上前两次妊娠三项报告"),
        PrepChecklistItem(id: "prepare_questions", title: "记录近期异常症状与用药变化"),
        PrepChecklistItem(id: "prepare_medications", title: "确认当天/次日药物安排")
    ]

    init() {
        if let loaded = Self.loadState(forKey: stateKey) {
            state = loaded
        } else {
            state = Self.seedState()
        }
        migrateLegacyCheckRecordsIfNeeded()
        migrateOnboardingStateIfNeeded()
        normalizeArchiveFlagsIfNeeded()
        normalizeDailyState()
    }

    var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: Date())
    }

    func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    var shouldShowOnboarding: Bool {
        !state.onboardingCompleted || state.onboardingRequiredAtLeastOnce
    }

    var gestationalWeekNumber: Int {
        let days = max(calendar.dateComponents([.day], from: state.profile.lastPeriodDate, to: Date()).day ?? 0, 0)
        return min(days / 7, 42)
    }

    var pregnancyStage: PregnancyStage {
        if gestationalWeekNumber < 14 {
            return .early
        }
        if gestationalWeekNumber < 28 {
            return .middle
        }
        return .late
    }

    var activeMedications: [MedicationItem] {
        state.medications.filter { !$0.isArchived }
    }

    var activeAppointments: [AppointmentItem] {
        state.appointments.filter { !$0.isArchived }
    }

    var activeCheckRecords: [CheckRecord] {
        (state.checkRecords ?? []).filter { !$0.isArchived }
    }

    func updateOnboardingStep(_ step: Int) {
        state.onboardingStep = max(1, min(step, 3))
    }

    func completeOnboarding(profile: Profile, reminder: ReminderConfig, skippedFields: [String]) {
        state.profile = profile
        state.reminderConfig = reminder
        state.profileOptionalFieldsSkipped = skippedFields
        state.onboardingVersion = onboardingSchemaVersion
        state.onboardingStep = 3
        state.onboardingCompleted = true
        state.onboardingRequiredAtLeastOnce = false
        markReminderRulesDirty()
    }

    func saveFamilyBindingDraft(relationName: String, relationPhone: String, inviteCodePlaceholder: String) {
        state.familyBindingDraft = FamilyBindingDraft(
            relationName: relationName.trimmingCharacters(in: .whitespacesAndNewlines),
            relationPhone: relationPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            inviteCodePlaceholder: inviteCodePlaceholder,
            updatedAt: Date()
        )
    }

    func markReminderRulesDirty() {
        reminderSyncRevision += 1
    }

    func showGlobalBanner(message: String, level: GlobalBannerLevel) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let nonce = UUID()
        bannerNonce = nonce
        globalBanner = GlobalBanner(id: nonce.uuidString, message: trimmed, level: level)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.bannerNonce == nonce else { return }
            self.globalBanner = nil
        }
    }

    func addAppointment(title: String, dueDate: Date, detail: String) {
        let item = AppointmentItem(
            id: UUID().uuidString,
            title: title,
            dueDate: dueDate,
            detail: detail,
            isDone: false,
            isArchived: false
        )
        state.appointments.append(item)
        markReminderRulesDirty()
    }

    func saveAppointment(_ appointment: AppointmentItem) {
        if let index = state.appointments.firstIndex(where: { $0.id == appointment.id }) {
            state.appointments[index] = appointment
        } else {
            state.appointments.append(appointment)
        }
        markReminderRulesDirty()
    }

    func addMedication(_ medication: MedicationItem) {
        state.medications.append(medication)
        markReminderRulesDirty()
    }

    func addExtraDailyReminder(title: String, detail: String, period: TimePeriod) {
        state.extraDailyItems.append(
            ExtraDailyItem(
                id: UUID().uuidString,
                period: period,
                title: title,
                detail: detail
            )
        )
        markReminderRulesDirty()
    }

    func archiveMedication(id: String) {
        guard let index = state.medications.firstIndex(where: { $0.id == id }) else { return }
        state.medications[index].isArchived = true
        state.completedDailyTaskIDs.removeAll { $0 == "med-\(id)" }
        markReminderRulesDirty()
    }

    func archiveMedicationGroup(named name: String) {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return }
        var changed = false
        for index in state.medications.indices where state.medications[index].name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target {
            state.medications[index].isArchived = true
            state.completedDailyTaskIDs.removeAll { $0 == "med-\(state.medications[index].id)" }
            changed = true
        }
        if changed {
            markReminderRulesDirty()
        }
    }

    func archiveAppointment(id: String) {
        guard let index = state.appointments.firstIndex(where: { $0.id == id }) else { return }
        state.appointments[index].isArchived = true
        state.appointments[index].isDone = true
        markReminderRulesDirty()
    }

    func archiveCheckRecord(id: String) {
        guard var list = state.checkRecords, let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].isArchived = true
        state.checkRecords = list
    }

    var todayNotes: [TodayNoteItem] {
        return state.todayNotes
            .filter { $0.dateKey == todayKey }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var sortedLabRecords: [LabRecord] {
        sortedCheckRecords()
            .filter { $0.type == .pregnancyPanel }
            .compactMap { asLabRecord($0) }
    }

    func sortedCheckRecords() -> [CheckRecord] {
        let source = activeCheckRecords
        return source.sorted { $0.checkTime > $1.checkTime }
    }

    func checkRecords(of type: CheckType?) -> [CheckRecord] {
        let all = sortedCheckRecords()
        guard let type else { return all }
        return all.filter { $0.type == type }
    }

    func checkRecordCountText() -> String {
        "\(sortedCheckRecords().count)"
    }

    func addCheckRecord(_ record: CheckRecord) {
        var list = state.checkRecords ?? []
        var normalized = record
        normalized.isArchived = false
        list.append(normalized)
        state.checkRecords = list
    }

    func previousCheckRecord(for record: CheckRecord) -> CheckRecord? {
        let sameType = checkRecords(of: record.type)
        guard let idx = sameType.firstIndex(where: { $0.id == record.id }), idx + 1 < sameType.count else {
            return nil
        }
        return sameType[idx + 1]
    }

    func trendSymbol(current: String, previous: String?) -> String {
        guard let previous, let c = Double(current), let p = Double(previous) else { return "-" }
        if c > p { return "↑" }
        if c < p { return "↓" }
        return "→"
    }

    func hcgDoublingDays(current: String, previous: String, hoursBetween: Double) -> String? {
        guard
            let c = Double(current),
            let p = Double(previous),
            c > 0,
            p > 0,
            hoursBetween > 0,
            c > p
        else { return nil }
        let days = (hoursBetween * log(2) / log(c / p)) / 24.0
        guard days.isFinite else { return nil }
        return String(format: "%.1f", days)
    }

    var symptomOptions: [SymptomOption] {
        symptomOptionsCatalog
    }

    var prepChecklist: [PrepChecklistItem] {
        prepChecklistCatalog
    }

    var supportedCheckTypes: [CheckType] {
        [.pregnancyPanel, .nt, .tang, .ultrasound, .cbc]
    }

    var age: Int {
        max(calendar.dateComponents([.year], from: state.profile.birthDate, to: Date()).year ?? 0, 0)
    }

    var dueDate: Date {
        calendar.date(byAdding: .day, value: 280, to: state.profile.lastPeriodDate) ?? Date()
    }

    var gestationalWeekText: String {
        let pregnancyDays = max(calendar.dateComponents([.day], from: state.profile.lastPeriodDate, to: Date()).day ?? 0, 0)
        let week = min(pregnancyDays / 7, 42)
        let day = pregnancyDays % 7
        return "\(week)周+\(day)天"
    }

    func gestationalWeekText(for date: Date) -> String {
        let pregnancyDays = max(calendar.dateComponents([.day], from: state.profile.lastPeriodDate, to: date).day ?? 0, 0)
        let week = min(pregnancyDays / 7, 42)
        let day = pregnancyDays % 7
        return "\(week)周+\(day)天"
    }

    var daysToDueText: String {
        let days = calendar.dateComponents([.day], from: Date(), to: dueDate).day ?? 0
        if days >= 0 {
            return "距离预产期还有 \(days) 天"
        }
        return "已超过预产期 \(-days) 天"
    }

    var abnormalSummaryText: String {
        let selected = (state.dailyCheckin?.dateKey == todayKey) ? (state.dailyCheckin?.abnormalSymptomIDs ?? []) : []
        if selected.isEmpty {
            return "今日暂无异常记录"
        }
        let names = symptomOptionsCatalog
            .filter { selected.contains($0.id) }
            .map(\.title)
            .joined(separator: "、")
        return "已记录：\(names)"
    }

    func updateProfile(_ profile: Profile) {
        state.profile = profile
    }

    func currentAIConfig() -> AIConfig {
        let stored = state.aiConfig ?? AIConfigProvider.defaultConfig()
        let overrides = AIConfigProvider.environmentOverrides()

        let mergedBase = overrides.baseURL ?? stored.baseURL
        let mergedKey = overrides.apiKey ?? stored.apiKey
        let mergedModel = overrides.model ?? stored.model

        let baseURL = mergedBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = mergedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelTrimmed = mergedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = modelTrimmed.isEmpty ? AIConfigProvider.defaultModel : modelTrimmed

        return AIConfig(baseURL: baseURL, apiKey: apiKey, model: model)
    }

    func saveAIConfig(_ config: AIConfig) {
        state.aiConfig = AIConfig(
            baseURL: config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            model: config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func aiLongTermMemory() -> String {
        state.aiLongTermMemory ?? ""
    }

    func saveAILongTermMemory(_ text: String) {
        state.aiLongTermMemory = text
    }

    func aiConversation() -> [StoredAIMessage] {
        state.aiConversation ?? []
    }

    func appendAIMessage(role: String, content: String) {
        var list = state.aiConversation ?? []
        list.append(
            StoredAIMessage(
                id: UUID().uuidString,
                role: role,
                content: content,
                time: Date()
            )
        )
        // 防止历史无限增长
        if list.count > 200 {
            list = Array(list.suffix(200))
        }
        state.aiConversation = list
    }

    func clearAIConversation() {
        state.aiConversation = []
    }

    func aiPendingActions() -> [AIPendingAction] {
        state.aiPendingActions ?? []
    }

    func homeChatMessages() -> [HomeChatMessage] {
        state.homeChatMessages ?? []
    }

    func saveHomeChatMessages(_ messages: [HomeChatMessage]) {
        if messages.count <= 200 {
            state.homeChatMessages = messages
        } else {
            state.homeChatMessages = Array(messages.suffix(200))
        }
    }

    func appendPendingAction(_ action: AIPendingAction) {
        var list = state.aiPendingActions ?? []
        list.append(action)
        if list.count > 50 {
            list = Array(list.suffix(50))
        }
        state.aiPendingActions = list
    }

    func removePendingAction(id: String) {
        var list = state.aiPendingActions ?? []
        list.removeAll { $0.id == id }
        state.aiPendingActions = list
    }

    func applyAIAction(_ action: AIPendingAction) -> String {
        switch action.intent {
        case "create_medication":
            let name = action.slots["item_name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty { return "缺少用药名称" }
            let dosage = action.slots["dosage"] ?? ""
            let note = action.slots["note"] ?? ""
            let period = TimePeriod.fromSemantic(action.slots["time_semantic"] ?? "")
            let med = MedicationItem(
                id: UUID().uuidString,
                period: period ?? .afterDinner,
                name: name,
                dosage: dosage,
                note: note
            )
            addMedication(med)
            let summary = "已创建用药：\(name)\(dosage.isEmpty ? "" : " · \(dosage)")\(note.isEmpty ? "" : " · \(note)")"
            return summary
        case "create_check_record":
            let rawCheckType = action.slots["check_type"] ?? ""
            let typeInput = rawCheckType.isEmpty ? "妊娠三项" : rawCheckType
            let type = CheckType.fromDisplay(typeInput)
            let note = action.slots["note"] ?? ""
            let checkDate = parseFlexibleDate(action.slots["check_date"])
            if type == .pregnancyPanel {
                guard let hcg = Double(action.slots["hcg"] ?? ""),
                      let p = Double(action.slots["progesterone"] ?? ""),
                      let e2 = Double(action.slots["estradiol"] ?? "") else {
                    return "检查数值不完整"
                }
                let metrics = [
                    CheckMetric(key: "hcg", label: "HCG", valueText: formatValue(hcg), unit: "mIU/ml", referenceLowText: nil, referenceHighText: nil),
                    CheckMetric(key: "progesterone", label: "孕酮 P", valueText: formatValue(p), unit: "ng/ml", referenceLowText: nil, referenceHighText: nil),
                    CheckMetric(key: "estradiol", label: "E2", valueText: formatValue(e2), unit: "pg/ml", referenceLowText: nil, referenceHighText: nil)
                ]
                addCheckRecord(
                    CheckRecord(
                        id: UUID().uuidString,
                        type: .pregnancyPanel,
                        checkTime: checkDate,
                        metrics: metrics,
                        note: note,
                        source: .ai
                    )
                )
                return "已保存检查记录：HCG \(formatValue(hcg)) / P \(formatValue(p)) / E2 \(formatValue(e2))"
            }

            var mergedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if type == .custom {
                let raw = rawCheckType.trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty {
                    let extra = "原始类型：\(raw)"
                    mergedNote = mergedNote.isEmpty ? extra : "\(mergedNote)；\(extra)"
                }
            }

            let metricLabel: String
            if type == .custom {
                let raw = rawCheckType.trimmingCharacters(in: .whitespacesAndNewlines)
                metricLabel = raw.isEmpty ? type.title : raw
            } else {
                metricLabel = type.title
            }
            let fallbackMetric = CheckMetric(
                key: "note",
                label: metricLabel,
                valueText: mergedNote.isEmpty ? "AI已记录" : mergedNote,
                unit: "",
                referenceLowText: nil,
                referenceHighText: nil
            )
            addCheckRecord(
                CheckRecord(
                    id: UUID().uuidString,
                    type: type,
                    checkTime: checkDate,
                    metrics: [fallbackMetric],
                    note: mergedNote,
                    source: .ai
                )
            )
            return "已保存\(type.title)记录"
        case "create_reminder":
            let title = action.slots["item_name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "提醒"
            let note = action.slots["note"] ?? ""
            let period = TimePeriod.fromSemantic(action.slots["time_semantic"] ?? "") ?? .afterDinner
            addExtraDailyReminder(
                title: title,
                detail: note.isEmpty ? "提醒事项" : note,
                period: period
            )
            let detail = note.isEmpty ? "" : " · \(note)"
            return "已创建提醒：\(title)\(detail)"
        case "update_reminder_time":
            let semantic = action.slots["time_semantic"] ?? ""
            let minutesText = action.slots["minutes_before"] ?? ""
            var updatedParts: [String] = []
            var config = currentReminderConfig()
            var changed = false

            if let period = TimePeriod.fromSemantic(semantic) {
                let timeText = action.slots["time_exact"] ?? ""
                if let normalized = normalizeTimeText(timeText) {
                    switch period {
                    case .wakeUp:
                        config.wakeUpTime = normalized
                    case .afterBreakfast:
                        config.breakfastTime = normalized
                    case .afterLunch:
                        config.lunchTime = normalized
                    case .afterDinner:
                        config.dinnerTime = normalized
                    case .beforeSleep:
                        config.sleepTime = normalized
                    }
                    updatedParts.append("\(period.rawValue)时间 \(normalized)")
                    changed = true
                }
            }

            if let minutes = Int(minutesText), minutes >= 0 {
                config.minutesBefore = minutes
                updatedParts.append("提前提醒 \(minutes) 分钟")
                changed = true
            }

            if updatedParts.isEmpty {
                return "没识别到要修改的时间或提前分钟数"
            }
            if changed {
                saveReminderConfig(config)
            }
            return "已更新：" + updatedParts.joined(separator: "；")
        default:
            return "暂不支持该操作"
        }
    }

    private func formatValue(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    func updateReminderTime(period: TimePeriod, timeText: String) {
        var config = currentReminderConfig()
        switch period {
        case .wakeUp:
            config.wakeUpTime = timeText
        case .afterBreakfast:
            config.breakfastTime = timeText
        case .afterLunch:
            config.lunchTime = timeText
        case .afterDinner:
            config.dinnerTime = timeText
        case .beforeSleep:
            config.sleepTime = timeText
        }
        saveReminderConfig(config)
    }

    func normalizeTimeText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let direct = parseHHmm(trimmed) { return direct }

        // 支持 “7点”、“7点半”、“19点30”
        if trimmed.contains("点") {
            let parts = trimmed.replacingOccurrences(of: "点", with: ":")
            if parts.contains("半") {
                let hourText = parts.replacingOccurrences(of: ":半", with: "")
                if let hour = Int(hourText) {
                    return String(format: "%02d:30", hour)
                }
            }
            let cleaned = parts.replacingOccurrences(of: "分", with: "")
            if let normalized = parseHHmm(cleaned) { return normalized }
        }
        return nil
    }

    private func parseHHmm(_ text: String) -> String? {
        let comps = text.split(separator: ":")
        guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]) else { return nil }
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    func currentReminderConfig() -> ReminderConfig {
        state.reminderConfig ?? ReminderConfig(
            wakeUpTime: "07:00",
            breakfastTime: "08:30",
            lunchTime: "12:30",
            dinnerTime: "18:30",
            sleepTime: "22:30",
            minutesBefore: 15
        )
    }

    func saveReminderConfig(_ config: ReminderConfig) {
        state.reminderConfig = ReminderConfig(
            wakeUpTime: config.wakeUpTime.trimmingCharacters(in: .whitespacesAndNewlines),
            breakfastTime: config.breakfastTime.trimmingCharacters(in: .whitespacesAndNewlines),
            lunchTime: config.lunchTime.trimmingCharacters(in: .whitespacesAndNewlines),
            dinnerTime: config.dinnerTime.trimmingCharacters(in: .whitespacesAndNewlines),
            sleepTime: config.sleepTime.trimmingCharacters(in: .whitespacesAndNewlines),
            minutesBefore: max(config.minutesBefore, 0)
        )
        markReminderRulesDirty()
    }

    func reminderTime(for period: TimePeriod) -> String {
        let config = currentReminderConfig()
        switch period {
        case .wakeUp: return config.wakeUpTime
        case .afterBreakfast: return config.breakfastTime
        case .afterLunch: return config.lunchTime
        case .afterDinner: return config.dinnerTime
        case .beforeSleep: return config.sleepTime
        }
    }

    func aiContextSummary() -> String {
        let profile = state.profile
        let todayText = formatDate(Date())
        let nowText = formatDateTime(Date())
        let medsText = TimePeriod.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { period in
                let items = activeMedications.filter { $0.period == period }
                let names = items.map { "\($0.name)\($0.dosage.isEmpty ? "" : "（\($0.dosage)）")" }.joined(separator: "、")
                return "\(period.rawValue)：\(names.isEmpty ? "无" : names)"
            }
            .joined(separator: "\n")

        let nextAppt = nextPendingAppointment()
        let appointmentText: String
        if let nextAppt {
            appointmentText = "\(nextAppt.title)，日期\(formatDate(nextAppt.dueDate))，\(nextAppt.detail)"
        } else {
            appointmentText = "暂无待回诊事项"
        }

        let labs = sortedLabRecords.prefix(2).map {
            "\(formatDateTime($0.checkTime))：孕酮\($0.progesterone)、雌二醇\($0.estradiol)、β-hCG\($0.hcg)"
        }.joined(separator: "\n")

        return """
        当前日期：\(todayText)，当前时间：\(nowText)
        姓名：\(profile.name)，性别：\(profile.gender)，年龄：\(age)岁
        当前孕周：\(gestationalWeekText)，\(daysToDueText)
        试管植入：\(formatDate(profile.ivfTransferDate))，首次验孕阳性：\(formatDate(profile.firstPositiveDate))
        每日目标：步数\(profile.stepsGoal)，饮水\(profile.waterGoalML)ml
        每日用药：
        \(medsText)
        注射计划：\(state.injectionPlan.detail)
        回诊计划：\(appointmentText)
        最近妊娠三项：
        \(labs)
        长期记忆（用户补充）：
        \(aiLongTermMemory())
        """
    }

    func addTodayItem(title: String, detail: String, period: TimePeriod, alsoAddToDaily: Bool) {
        normalizeDailyState()
        let note = TodayNoteItem(
            id: UUID().uuidString,
            dateKey: todayKey,
            title: title,
            detail: detail,
            createdAt: Date()
        )
        state.todayNotes.append(note)

        if alsoAddToDaily {
            state.extraDailyItems.append(
                ExtraDailyItem(
                    id: UUID().uuidString,
                    period: period,
                    title: title,
                    detail: detail
                )
            )
            markReminderRulesDirty()
        }
    }

    func toggleDailyTask(_ id: String) {
        normalizeDailyState()
        if let idx = state.completedDailyTaskIDs.firstIndex(of: id) {
            state.completedDailyTaskIDs.remove(at: idx)
        } else {
            state.completedDailyTaskIDs.append(id)
        }
    }

    func toggleAppointment(_ id: String) {
        guard let index = state.appointments.firstIndex(where: { $0.id == id && !$0.isArchived }) else { return }
        state.appointments[index].isDone.toggle()
        markReminderRulesDirty()
    }

    func toggleSymptom(_ symptomID: String) {
        ensureDailyCheckinForToday()
        guard var checkin = state.dailyCheckin else { return }
        if let idx = checkin.abnormalSymptomIDs.firstIndex(of: symptomID) {
            checkin.abnormalSymptomIDs.remove(at: idx)
        } else {
            checkin.abnormalSymptomIDs.append(symptomID)
        }
        state.dailyCheckin = checkin
    }

    func isSymptomSelected(_ symptomID: String) -> Bool {
        guard let checkin = state.dailyCheckin, checkin.dateKey == todayKey else { return false }
        return checkin.abnormalSymptomIDs.contains(symptomID)
    }

    func setDailyWeightKG(_ value: String) {
        ensureDailyCheckinForToday()
        state.dailyCheckin?.weightKG = value
    }

    func setDailySystolicBP(_ value: String) {
        ensureDailyCheckinForToday()
        state.dailyCheckin?.systolicBP = value
    }

    func setDailyDiastolicBP(_ value: String) {
        ensureDailyCheckinForToday()
        state.dailyCheckin?.diastolicBP = value
    }

    func setDailyHeartRate(_ value: String) {
        ensureDailyCheckinForToday()
        state.dailyCheckin?.heartRate = value
    }

    func dailyWeightKG() -> String {
        guard let checkin = state.dailyCheckin, checkin.dateKey == todayKey else { return "" }
        return checkin.weightKG
    }

    func dailySystolicBP() -> String {
        guard let checkin = state.dailyCheckin, checkin.dateKey == todayKey else { return "" }
        return checkin.systolicBP
    }

    func dailyDiastolicBP() -> String {
        guard let checkin = state.dailyCheckin, checkin.dateKey == todayKey else { return "" }
        return checkin.diastolicBP
    }

    func dailyHeartRate() -> String {
        guard let checkin = state.dailyCheckin, checkin.dateKey == todayKey else { return "" }
        return checkin.heartRate
    }

    func medicationSectionsForToday() -> [MedicationTaskSection] {
        medicationSections(for: Date())
    }

    func medicationSections(for date: Date) -> [MedicationTaskSection] {
        struct Entry {
            var period: TimePeriod
            var row: DailyTaskRow
        }

        let isToday = dateKey(for: date) == todayKey
        let meds = activeMedications.map { med -> Entry in
            let id = "med-\(med.id)"
            let subtitle = "\(med.dosage)\(med.note.isEmpty ? "" : " · \(med.note)")"
            return Entry(
                period: med.period,
                row: DailyTaskRow(
                    id: id,
                    title: med.name,
                    subtitle: subtitle,
                    kind: .daily,
                    isCompleted: isToday && state.completedDailyTaskIDs.contains(id)
                )
            )
        }

        let extra = state.extraDailyItems.map { item -> Entry in
            let id = "extra-\(item.id)"
            return Entry(
                period: item.period,
                row: DailyTaskRow(
                    id: id,
                    title: item.title,
                    subtitle: item.detail,
                    kind: .daily,
                    isCompleted: isToday && state.completedDailyTaskIDs.contains(id)
                )
            )
        }

        let grouped = Dictionary(grouping: meds + extra, by: \.period)
        return TimePeriod.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { period in
                guard let entries = grouped[period], !entries.isEmpty else { return nil }
                return MedicationTaskSection(
                    id: period.id,
                    title: period.rawValue,
                    rows: entries.map(\.row)
                )
            }
    }

    func dailyGoalRows() -> [DailyTaskRow] {
        state.dailyHabits.map { habit in
            let id = "habit-\(habit.id)"
            return DailyTaskRow(
                id: id,
                title: habit.title,
                subtitle: "",
                kind: .daily,
                isCompleted: state.completedDailyTaskIDs.contains(id)
            )
        }
    }

    func todayTaskSummary() -> (total: Int, done: Int, left: Int) {
        let rows = dailyTaskSections().flatMap { $0.rows }
        let done = rows.filter { $0.isCompleted }.count
        let total = rows.count
        return (total, done, max(total - done, 0))
    }

    func homeSummary() -> HomeSummary {
        let summary = todayTaskSummary()
        let tomorrowHint = tomorrowReminderText() ?? "明天暂无特殊安排"
        let warmLine: String
        if summary.left == 0 {
            warmLine = "今天已经都搞定了，\(tomorrowHint)"
        } else if summary.left <= 2 {
            warmLine = "今天还剩 \(summary.left) 件事，慢慢来就很好。"
        } else {
            warmLine = "今天安排稍微有点满，我会陪你一项项完成。"
        }

        return HomeSummary(
            dateText: homeDateText(for: Date()),
            gestationalText: "孕 \(gestationalWeekText)",
            dueDateText: "预产期 \(formatDate(dueDate))",
            total: summary.total,
            done: summary.done,
            left: summary.left,
            tomorrowHint: tomorrowHint,
            warmLine: warmLine
        )
    }

    func homeOpeningLine() -> String {
        let summary = homeSummary()
        let tomorrow = normalizedTomorrowHint(from: summary.tomorrowHint)

        if let next = nextUpcomingMedication() {
            let templates = [
                "\(next.period.rawValue)会提醒你服药哦，要我告诉你都有哪些药吗？",
                "\(next.period.rawValue)我会准时提醒你吃药，要不要我先把药单和剂量说给你听？"
            ]
            let index = calendar.component(.day, from: Date()) % templates.count
            return templates[index] + tomorrow
        }

        let templates = [
            "今天你的用药提醒都完成啦，真棒。",
            "今天该提醒的用药都完成啦，辛苦你啦。"
        ]
        let index = calendar.component(.day, from: Date()) % templates.count
        return templates[index] + tomorrow
    }

    func homeSummarySnapshotText() -> String {
        let summary = homeSummary()
        let todayItems = timelineItems(for: Date())
        let pendingItems = todayItems
            .filter { !$0.isCompleted }
            .sorted { (timeToMinutes($0.timeText) ?? 0) < (timeToMinutes($1.timeText) ?? 0) }
            .prefix(4)
            .map { "\($0.timeText) \($0.title)" }
        let pendingText = pendingItems.isEmpty ? "今天待办已清空" : pendingItems.joined(separator: "；")

        let reviewText: String
        if let upcoming = nearestPendingAppointmentWithin14Days() {
            reviewText = "\(formatDate(upcoming.dueDate)) \(appointmentTimeText(upcoming.dueDate)) \(upcoming.title)"
        } else {
            reviewText = "近期暂无复查安排"
        }

        let reminderText = state.extraDailyItems.isEmpty
            ? "无额外提醒"
            : state.extraDailyItems.prefix(3).map { "\($0.period.rawValue)\($0.title)" }.joined(separator: "；")
        let nextText: String
        if let next = nextUpcomingMedication() {
            nextText = "\(next.period.rawValue) \(next.title)（\(next.timeText)）"
        } else {
            nextText = "今日用药提醒已完成"
        }

        return """
        当前孕周：\(gestationalWeekText)
        预产期：\(formatDate(dueDate))
        今日进度：总\(summary.total)项，已完成\(summary.done)项，剩余\(summary.left)项
        今天待办：\(pendingText)
        下一个提醒：\(nextText)
        近期复查：\(reviewText)
        用户提醒：\(reminderText)
        """
    }

    func homeSummaryFingerprint() -> String {
        let summary = todayTaskSummary()
        let nextToken: String
        if let next = nextUpcomingMedication() {
            nextToken = "\(next.id)|\(next.timeText)"
        } else {
            nextToken = "none"
        }

        let reviewToken: String
        if let appointment = nearestPendingAppointmentWithin14Days() {
            reviewToken = "\(appointment.id)|\(formatDate(appointment.dueDate))|\(appointmentTimeText(appointment.dueDate))"
        } else {
            reviewToken = "none"
        }

        let reminderToken = state.extraDailyItems
            .sorted { lhs, rhs in
                if lhs.period.sortOrder == rhs.period.sortOrder {
                    return lhs.id < rhs.id
                }
                return lhs.period.sortOrder < rhs.period.sortOrder
            }
            .map { "\($0.id):\($0.period.rawValue):\($0.title)" }
            .joined(separator: "|")

        return [
            "date=\(todayKey)",
            "total=\(summary.total)",
            "done=\(summary.done)",
            "left=\(summary.left)",
            "next=\(nextToken)",
            "review=\(reviewToken)",
            "reminder=\(reminderToken)"
        ].joined(separator: ";")
    }

    func cachedHomeSummaryLine() -> String? {
        clearExpiredHomeSummaryCacheIfNeeded()
        guard let cache = state.homeSummaryCache else { return nil }
        let text = cache.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return nil
        }
        let lower = text.lowercased()
        if lower.contains("<think") || lower.contains("</think>") {
            state.homeSummaryCache = nil
            return nil
        }
        return text
    }

    func shouldRefreshHomeSummary() -> Bool {
        guard let cache = state.homeSummaryCache else { return true }
        if cache.dateKey != todayKey {
            return true
        }
        let trimmed = cache.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        let lower = trimmed.lowercased()
        if lower.contains("<think") || lower.contains("</think>") {
            return true
        }
        return cache.fingerprint != homeSummaryFingerprint()
    }

    func saveHomeSummaryCache(text: String, fingerprint: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.homeSummaryCache = HomeSummaryCache(
            dateKey: todayKey,
            text: trimmed,
            fingerprint: fingerprint,
            updatedAt: Date()
        )
    }

    func clearExpiredHomeSummaryCacheIfNeeded() {
        guard let cache = state.homeSummaryCache else { return }
        if cache.dateKey != todayKey {
            state.homeSummaryCache = nil
        }
    }

    func quickCommandPrompts() -> [QuickCommand] {
        switch pregnancyStage {
        case .early:
            return [
                QuickCommand(title: "记录妊娠三项", prompt: "我今天做了妊娠三项，帮我记录", icon: "testtube.2"),
                QuickCommand(title: "新增补剂", prompt: "晚饭后我要吃钙片，帮我记录", icon: "pills"),
                QuickCommand(title: "加复查预约", prompt: "帮我加一个复查预约，时间是明天上午9点", icon: "calendar"),
                QuickCommand(title: "明天吃什么药", prompt: "明天吃什么药", icon: "list.bullet.clipboard"),
                QuickCommand(title: "调整提醒时间", prompt: "把晚饭后提醒改成晚上7点", icon: "alarm"),
                QuickCommand(title: "记录身体感受", prompt: "我今天有点恶心，帮我记录一下", icon: "square.and.pencil")
            ]
        case .middle:
            return [
                QuickCommand(title: "记录NT/唐筛", prompt: "我今天做了NT或唐筛，帮我记录", icon: "chart.bar"),
                QuickCommand(title: "加产检预约", prompt: "帮我新增一次产检预约，下周三上午9点", icon: "cross.case"),
                QuickCommand(title: "新增补剂", prompt: "帮我新增一个孕期补剂提醒", icon: "pills"),
                QuickCommand(title: "明天吃什么药", prompt: "明天吃什么药", icon: "list.bullet.clipboard"),
                QuickCommand(title: "调整提醒时间", prompt: "把睡前提醒改成22点", icon: "alarm"),
                QuickCommand(title: "记录睡眠", prompt: "我昨晚睡得不太好，帮我记录", icon: "moon.stars")
            ]
        case .late:
            return [
                QuickCommand(title: "记录胎动", prompt: "我想记录今天胎动情况", icon: "figure.and.child.holdinghands"),
                QuickCommand(title: "加产检预约", prompt: "帮我新增一次产检预约", icon: "cross.case"),
                QuickCommand(title: "新增补剂", prompt: "帮我新增一个睡前补剂提醒", icon: "pills"),
                QuickCommand(title: "明天吃什么药", prompt: "明天吃什么药", icon: "list.bullet.clipboard"),
                QuickCommand(title: "调整提醒时间", prompt: "把晚饭后提醒改成晚上7点20", icon: "alarm"),
                QuickCommand(title: "记录不适", prompt: "我今天有点宫缩感，帮我记录一下", icon: "square.and.pencil")
            ]
        }
    }

    func nextUpcomingMedication() -> NextMedication? {
        let sections = medicationSectionsForToday()
        var candidates: [(item: NextMedication, minutes: Int)] = []
        for section in sections {
            guard let period = TimePeriod.allCases.first(where: { $0.rawValue == section.title }) else { continue }
            let base = reminderTime(for: period)
            let timeText = ReminderScheduler.semanticAdjustedTimeText(for: period, baseTime: base)
            let minutes = timeToMinutes(timeText) ?? 9999
            for row in section.rows where !row.isCompleted {
                let item = NextMedication(
                    id: row.id,
                    period: period,
                    title: row.title,
                    subtitle: row.subtitle,
                    timeText: timeText
                )
                candidates.append((item, minutes))
            }
        }
        if candidates.isEmpty { return nil }
        let nowMinutes = timeToMinutes(currentTimeText()) ?? 0
        let upcoming = candidates.filter { $0.minutes >= nowMinutes }.sorted { $0.minutes < $1.minutes }
        if let first = upcoming.first?.item { return first }
        return candidates.sorted { $0.minutes < $1.minutes }.first?.item
    }

    func timelineSections(for date: Date) -> [TimelineSection] {
        let items = timelineItems(for: date).sorted {
            (timeToMinutes($0.timeText) ?? 0) < (timeToMinutes($1.timeText) ?? 0)
        }
        var grouped: [TimelineBucket: [TimelineItem]] = [:]
        for item in items {
            let minutes = timeToMinutes(item.timeText) ?? 540
            let bucket = TimelineBucket.bucket(for: minutes)
            grouped[bucket, default: []].append(item)
        }

        return TimelineBucket.allCases.compactMap { bucket in
            guard let rows = grouped[bucket], !rows.isEmpty else { return nil }
            let pending = rows.filter { !$0.isCompleted }
            let completed = rows.filter(\.isCompleted)
            return TimelineSection(
                bucket: bucket,
                pendingItems: pending,
                completedItems: completed
            )
        }
    }

    func timelineItems(for date: Date) -> [TimelineItem] {
        var items: [TimelineItem] = []
        let isToday = dateKey(for: date) == todayKey

        for med in activeMedications {
            let id = "med-\(med.id)"
            let timeText = ReminderScheduler.semanticAdjustedTimeText(for: med.period, baseTime: reminderTime(for: med.period))
            let subtitle = [periodDescription(for: med.period), med.dosage].filter { !$0.isEmpty }.joined(separator: " · ")
            let isCompleted = isToday && state.completedDailyTaskIDs.contains(id)
            items.append(
                TimelineItem(
                    id: id,
                    timeText: timeText,
                    title: med.name,
                    subtitle: subtitle,
                    kind: .medication,
                    isCompleted: isCompleted,
                    isActive: false,
                    sourceID: id,
                    isActionable: isToday
                )
            )
        }

        for item in state.extraDailyItems {
            let id = "extra-\(item.id)"
            let timeText = ReminderScheduler.semanticAdjustedTimeText(for: item.period, baseTime: reminderTime(for: item.period))
            let subtitle = [periodDescription(for: item.period), item.detail].filter { !$0.isEmpty }.joined(separator: " · ")
            let isCompleted = isToday && state.completedDailyTaskIDs.contains(id)
            items.append(
                TimelineItem(
                    id: id,
                    timeText: timeText,
                    title: item.title,
                    subtitle: subtitle,
                    kind: .medication,
                    isCompleted: isCompleted,
                    isActive: false,
                    sourceID: id,
                    isActionable: isToday
                )
            )
        }

        let habitTimes = ["09:00", "15:00", "20:00"]
        for (index, habit) in state.dailyHabits.enumerated() {
            let id = "habit-\(habit.id)"
            let timeText = habitTimes[min(index, habitTimes.count - 1)]
            let isCompleted = isToday && state.completedDailyTaskIDs.contains(id)
            items.append(
                TimelineItem(
                    id: id,
                    timeText: timeText,
                    title: habit.title,
                    subtitle: "保持良好习惯",
                    kind: .habit,
                    isCompleted: isCompleted,
                    isActive: false,
                    sourceID: id,
                    isActionable: isToday
                )
            )
        }

        let appointmentItems = activeAppointments.filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
        for appt in appointmentItems {
            let timeText = appointmentTimeText(appt.dueDate)
            items.append(
                TimelineItem(
                    id: appt.id,
                    timeText: timeText,
                    title: appt.title,
                    subtitle: appt.detail,
                    kind: .appointment,
                    isCompleted: appt.isDone,
                    isActive: false,
                    sourceID: appt.id,
                    isActionable: isToday
                )
            )
        }

        if isInjectionDue(on: date) {
            let id = "injection-\(dateKey(for: date))"
            let isCompleted = isToday && state.completedDailyTaskIDs.contains(id)
            items.append(
                TimelineItem(
                    id: id,
                    timeText: "10:00",
                    title: state.injectionPlan.title,
                    subtitle: state.injectionPlan.detail,
                    kind: .check,
                    isCompleted: isCompleted,
                    isActive: false,
                    sourceID: id,
                    isActionable: isToday
                )
            )
        }

        items.sort { (timeToMinutes($0.timeText) ?? 0) < (timeToMinutes($1.timeText) ?? 0) }
        if isToday {
            if let activeIndex = items.firstIndex(where: { !$0.isCompleted && (timeToMinutes($0.timeText) ?? 0) >= (timeToMinutes(currentTimeText()) ?? 0) }) {
                items[activeIndex].isActive = true
            }
        }
        return items
    }

    func nextPendingAppointment() -> AppointmentItem? {
        activeAppointments
            .filter { !$0.isDone }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    func countdownText(to date: Date) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if days > 0 { return "\(days)天后" }
        if days == 0 { return "今天" }
        return "已过期\(-days)天"
    }

    func isInjectionDueToday() -> Bool {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: state.injectionPlan.startDate)
        let end = calendar.startOfDay(for: state.injectionPlan.endDate)
        guard today >= start && today <= end else { return false }
        let diff = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return diff % max(state.injectionPlan.intervalDays, 1) == 0
    }

    func isInjectionDue(on date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: state.injectionPlan.startDate)
        let end = calendar.startOfDay(for: state.injectionPlan.endDate)
        guard day >= start && day <= end else { return false }
        let diff = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        return diff % max(state.injectionPlan.intervalDays, 1) == 0
    }

    func nextInjectionDate() -> Date? {
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: state.injectionPlan.startDate)
        let end = calendar.startOfDay(for: state.injectionPlan.endDate)
        let first = max(today, start)
        guard first <= end else { return nil }

        let step = max(state.injectionPlan.intervalDays, 1)
        var current = first
        while current <= end {
            let diff = calendar.dateComponents([.day], from: start, to: current).day ?? 0
            if diff % step == 0 {
                return current
            }
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return nil
    }

    func togglePrepChecklistItem(_ id: String) {
        var checked = state.appointmentPrepCheckedIDs ?? []
        if let idx = checked.firstIndex(of: id) {
            checked.remove(at: idx)
        } else {
            checked.append(id)
        }
        state.appointmentPrepCheckedIDs = checked
    }

    func isPrepChecklistChecked(_ id: String) -> Bool {
        (state.appointmentPrepCheckedIDs ?? []).contains(id)
    }

    func dailyTaskSections() -> [DailyTaskSection] {
        var sections: [DailyTaskSection] = []

        let medicineRows = dailyMedicationRows()
        if !medicineRows.isEmpty {
            sections.append(DailyTaskSection(id: "medications", title: "每日用药", rows: medicineRows))
        }

        let habitRows = state.dailyHabits.map { habit in
            let id = "habit-\(habit.id)"
            return DailyTaskRow(
                id: id,
                title: habit.title,
                subtitle: "",
                kind: .daily,
                isCompleted: state.completedDailyTaskIDs.contains(id)
            )
        }
        sections.append(DailyTaskSection(id: "habits", title: "每日目标", rows: habitRows))

        let specialRows = specialRowsForToday()
        if !specialRows.isEmpty {
            sections.append(DailyTaskSection(id: "special", title: "今日特殊事项", rows: specialRows))
        }

        let appointmentRows = pendingAppointmentRows()
        if !appointmentRows.isEmpty {
            sections.append(DailyTaskSection(id: "appointments", title: "近期回诊", rows: appointmentRows))
        }

        return sections
    }

    func refreshForTodayIfNeeded() {
        normalizeDailyState()
    }

    private func dailyMedicationRows() -> [DailyTaskRow] {
        let medRows = activeMedications.map { med -> DailyTaskRow in
            let id = "med-\(med.id)"
            let subtitle = "\(med.period.rawValue) · \(med.dosage)\(med.note.isEmpty ? "" : " · \(med.note)")"
            return DailyTaskRow(
                id: id,
                title: med.name,
                subtitle: subtitle,
                kind: .daily,
                isCompleted: state.completedDailyTaskIDs.contains(id)
            )
        }

        let extraRows = state.extraDailyItems.map { item -> DailyTaskRow in
            let id = "extra-\(item.id)"
            let subtitle = "\(item.period.rawValue) · \(item.detail)"
            return DailyTaskRow(
                id: id,
                title: item.title,
                subtitle: subtitle,
                kind: .daily,
                isCompleted: state.completedDailyTaskIDs.contains(id)
            )
        }

        return (medRows + extraRows).sorted { lhs, rhs in
            periodSortOrder(for: lhs.subtitle) < periodSortOrder(for: rhs.subtitle)
        }
    }

    private func periodSortOrder(for subtitle: String) -> Int {
        guard let period = periodFromSubtitle(subtitle) else { return 99 }
        return period.sortOrder
    }

    func periodFromSubtitle(_ subtitle: String) -> TimePeriod? {
        if subtitle.hasPrefix(TimePeriod.wakeUp.rawValue) { return .wakeUp }
        if subtitle.hasPrefix(TimePeriod.afterBreakfast.rawValue) { return .afterBreakfast }
        if subtitle.hasPrefix(TimePeriod.afterLunch.rawValue) { return .afterLunch }
        if subtitle.hasPrefix(TimePeriod.afterDinner.rawValue) { return .afterDinner }
        if subtitle.hasPrefix(TimePeriod.beforeSleep.rawValue) { return .beforeSleep }
        return nil
    }

    private func specialRowsForToday() -> [DailyTaskRow] {
        guard isInjectionDueToday() else { return [] }
        let id = "injection-\(todayKey)"
        return [
            DailyTaskRow(
                id: id,
                title: state.injectionPlan.title,
                subtitle: state.injectionPlan.detail,
                kind: .daily,
                isCompleted: state.completedDailyTaskIDs.contains(id)
            )
        ]
    }

    private func pendingAppointmentRows() -> [DailyTaskRow] {
        let pending = activeAppointments
            .filter { !$0.isDone }
            .sorted { $0.dueDate < $1.dueDate }

        return pending.map { appt in
            let days = calendar.dateComponents([.day], from: Date(), to: appt.dueDate).day ?? 0
            let dueText: String
            if days > 0 {
                dueText = "\(days)天后"
            } else if days == 0 {
                dueText = "今天"
            } else {
                dueText = "已过期\(-days)天"
            }
            return DailyTaskRow(
                id: appt.id,
                title: appt.title,
                subtitle: "\(formatDate(appt.dueDate)) · \(dueText) · \(appt.detail)",
                kind: .appointment,
                isCompleted: appt.isDone
            )
        }
    }

    private func ensureDailyCheckinForToday() {
        if let checkin = state.dailyCheckin, checkin.dateKey == todayKey {
            return
        }
        state.dailyCheckin = DailyHealthCheckin(
            dateKey: todayKey,
            abnormalSymptomIDs: [],
            weightKG: "",
            systolicBP: "",
            diastolicBP: "",
            heartRate: ""
        )
    }

    private func normalizeDailyState() {
        let key = todayKey
        if state.completionDateKey != key {
            state.completionDateKey = key
            state.completedDailyTaskIDs = []
            state.todayNotes.removeAll { $0.dateKey != key }
        }
        ensureDailyCheckinForToday()
    }

    private func migrateOnboardingStateIfNeeded() {
        if state.onboardingVersion < onboardingSchemaVersion {
            state.onboardingVersion = onboardingSchemaVersion
            state.onboardingCompleted = false
            state.onboardingRequiredAtLeastOnce = true
            state.onboardingStep = 1
        }

        state.onboardingStep = max(1, min(state.onboardingStep, 3))

        if state.onboardingCompleted {
            state.onboardingRequiredAtLeastOnce = false
        }
    }

    private func normalizeArchiveFlagsIfNeeded() {
        state.completedDailyTaskIDs = state.completedDailyTaskIDs.filter { id in
            if id.hasPrefix("med-") {
                let key = String(id.dropFirst(4))
                return state.medications.contains { $0.id == key && !$0.isArchived }
            }
            return true
        }
    }

    private func migrateLegacyCheckRecordsIfNeeded() {
        guard state.checkRecords == nil || state.checkRecords?.isEmpty == true else { return }
        guard !state.labRecords.isEmpty else {
            state.checkRecords = []
            return
        }
        state.checkRecords = state.labRecords.map { asCheckRecord($0) }
    }

    private func asCheckRecord(_ legacy: LabRecord) -> CheckRecord {
        CheckRecord(
            id: legacy.id,
            type: .pregnancyPanel,
            checkTime: legacy.checkTime,
            metrics: [
                CheckMetric(key: "hcg", label: "HCG", valueText: formatValue(legacy.hcg), unit: "mIU/ml", referenceLowText: nil, referenceHighText: nil),
                CheckMetric(key: "progesterone", label: "孕酮 P", valueText: formatValue(legacy.progesterone), unit: "ng/ml", referenceLowText: nil, referenceHighText: nil),
                CheckMetric(key: "estradiol", label: "E2", valueText: formatValue(legacy.estradiol), unit: "pg/ml", referenceLowText: nil, referenceHighText: nil)
            ],
            note: "",
            source: .manual
        )
    }

    private func asLabRecord(_ record: CheckRecord) -> LabRecord? {
        guard record.type == .pregnancyPanel else { return nil }
        let hcg = Double(record.metrics.first(where: { $0.key == "hcg" })?.valueText ?? "")
        let p = Double(record.metrics.first(where: { $0.key == "progesterone" })?.valueText ?? "")
        let e2 = Double(record.metrics.first(where: { $0.key == "estradiol" })?.valueText ?? "")
        guard let hcg, let p, let e2 else { return nil }
        return LabRecord(
            id: record.id,
            checkTime: record.checkTime,
            progesterone: p,
            estradiol: e2,
            hcg: hcg
        )
    }

    private func parseFlexibleDate(_ text: String?) -> Date {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return Date() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fmts = ["yyyy-MM-dd", "yyyy/MM/dd", "MM-dd", "M月d日"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        for format in fmts {
            formatter.dateFormat = format
            if let d = formatter.date(from: trimmed) { return d }
        }
        return Date()
    }

    private func saveState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var snapshot = state
        // 兼容旧结构：继续写入妊娠三项投影，主数据以 checkRecords 为准。
        snapshot.labRecords = sortedLabRecords
        if let data = try? encoder.encode(snapshot) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    private static func loadState(forKey key: String) -> AppState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppState.self, from: data)
    }

    private static func seedState() -> AppState {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        func date(_ text: String) -> Date {
            formatter.date(from: text) ?? Date()
        }

        let profile = Profile(
            name: "余丽佳",
            gender: "女",
            birthDate: date("1989-08-19"),
            lastPeriodDate: date("2026-01-16"),
            ivfTransferDate: date("2026-01-30"),
            firstPositiveDate: date("2026-02-09"),
            stepsGoal: 10_000,
            waterGoalML: 1_000
        )

        let medications: [MedicationItem] = [
            MedicationItem(id: "med1", period: .wakeUp, name: "优甲乐", dosage: "1片", note: "每日一片"),
            MedicationItem(id: "med2", period: .wakeUp, name: "安琪坦", dosage: "塞1粒", note: ""),

            MedicationItem(id: "med3", period: .afterBreakfast, name: "爱乐维", dosage: "1粒", note: ""),
            MedicationItem(id: "med4", period: .afterBreakfast, name: "维生素D", dosage: "5粒", note: ""),
            MedicationItem(id: "med5", period: .afterBreakfast, name: "鱼油", dosage: "2粒", note: ""),
            MedicationItem(id: "med6", period: .afterBreakfast, name: "免疫球蛋白", dosage: "2粒", note: ""),
            MedicationItem(id: "med7", period: .afterBreakfast, name: "地屈孕酮", dosage: "2粒", note: ""),
            MedicationItem(id: "med8", period: .afterBreakfast, name: "小红片", dosage: "1片", note: ""),

            MedicationItem(id: "med9", period: .afterDinner, name: "DHA", dosage: "1粒", note: ""),
            MedicationItem(id: "med10", period: .afterDinner, name: "地屈孕酮", dosage: "2片", note: ""),
            MedicationItem(id: "med11", period: .afterDinner, name: "补佳乐", dosage: "1片", note: ""),
            MedicationItem(id: "med12", period: .afterDinner, name: "小红片", dosage: "1片", note: ""),
            MedicationItem(id: "med13", period: .afterDinner, name: "肝素", dosage: "打一针", note: ""),

            MedicationItem(id: "med14", period: .beforeSleep, name: "安琪坦", dosage: "塞2粒", note: "")
        ]

        let habits = [
            DailyHabitItem(id: "steps", title: "每日走够 10000 步"),
            DailyHabitItem(id: "water", title: "每日喝够 1L 水")
        ]

        let appointments = [
            AppointmentItem(
                id: "appt-2026-02-21",
                title: "回诊（妊娠三项第三次）",
                dueDate: date("2026-02-21"),
                detail: "检查孕酮、雌二醇、β-hCG",
                isDone: false
            )
        ]

        let injectionPlan = InjectionPlan(
            title: "促绒毛激素注射",
            startDate: date("2026-02-17"),
            endDate: date("2026-02-21"),
            intervalDays: 2,
            detail: "隔一天打一针（2026-02-17 / 19 / 21）"
        )

        let records = [
            LabRecord(
                id: "lab-2026-02-13",
                checkTime: calendar.date(bySettingHour: 9, minute: 41, second: 22, of: date("2026-02-13")) ?? date("2026-02-13"),
                progesterone: 99.70,
                estradiol: 2194.64,
                hcg: 1762.75
            ),
            LabRecord(
                id: "lab-2026-02-16",
                checkTime: calendar.date(bySettingHour: 12, minute: 29, second: 24, of: date("2026-02-16")) ?? date("2026-02-16"),
                progesterone: 97.70,
                estradiol: 1602.16,
                hcg: 7622.60
            )
        ]

        let formatter2 = DateFormatter()
        formatter2.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter2.string(from: Date())

        return AppState(
            profile: profile,
            medications: medications,
            dailyHabits: habits,
            extraDailyItems: [],
            todayNotes: [],
            appointments: appointments,
            injectionPlan: injectionPlan,
            labRecords: records,
            checkRecords: records.map {
                CheckRecord(
                    id: $0.id,
                    type: .pregnancyPanel,
                    checkTime: $0.checkTime,
                    metrics: [
                        CheckMetric(key: "hcg", label: "HCG", valueText: String(format: "%.2f", $0.hcg), unit: "mIU/ml", referenceLowText: nil, referenceHighText: nil),
                        CheckMetric(key: "progesterone", label: "孕酮 P", valueText: String(format: "%.2f", $0.progesterone), unit: "ng/ml", referenceLowText: nil, referenceHighText: nil),
                        CheckMetric(key: "estradiol", label: "E2", valueText: String(format: "%.2f", $0.estradiol), unit: "pg/ml", referenceLowText: nil, referenceHighText: nil)
                    ],
                    note: "",
                    source: .manual
                )
            },
            completionDateKey: todayKey,
            completedDailyTaskIDs: [],
            dailyCheckin: DailyHealthCheckin(
                dateKey: todayKey,
                abnormalSymptomIDs: [],
                weightKG: "",
                systolicBP: "",
                diastolicBP: "",
                heartRate: ""
            ),
            appointmentPrepCheckedIDs: [],
            aiConfig: AIConfig(
                baseURL: "",
                apiKey: "",
                model: AIConfigProvider.defaultModel
            ),
            reminderConfig: ReminderConfig(
                wakeUpTime: "07:00",
                breakfastTime: "08:30",
                lunchTime: "12:30",
                dinnerTime: "18:30",
                sleepTime: "22:30",
                minutesBefore: 15
            ),
            aiConversation: [],
            aiLongTermMemory: "",
            aiPendingActions: [],
            homeChatMessages: [],
            onboardingVersion: 13,
            onboardingCompleted: false,
            onboardingStep: 1,
            onboardingRequiredAtLeastOnce: true,
            profileOptionalFieldsSkipped: [],
            familyBindingDraft: nil,
            homeSummaryCache: nil
        )
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    func periodDescription(for period: TimePeriod) -> String {
        switch period {
        case .wakeUp:
            return "起床后"
        case .afterBreakfast:
            return "早饭后 20 分钟"
        case .afterLunch:
            return "午饭后 20 分钟"
        case .afterDinner:
            return "晚饭后 20 分钟"
        case .beforeSleep:
            return "睡前 30 分钟"
        }
    }

    func currentTimeText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    func timeToMinutes(_ text: String) -> Int? {
        let comps = text.split(separator: ":")
        guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]) else { return nil }
        return h * 60 + m
    }

    func appointmentTimeText(_ date: Date) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        if hour == 0 && minute == 0 {
            return "09:00"
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    private func homeDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        let dateText = formatter.string(from: date)
        let weekday = calendar.component(.weekday, from: date)
        let weekText = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][max(weekday - 1, 0)]
        return "\(dateText) · \(weekText)"
    }

    private func tomorrowReminderText() -> String? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) else { return nil }
        let target = calendar.startOfDay(for: tomorrow)

        let pendingAppointments = activeAppointments
            .filter { !$0.isDone }
            .sorted { $0.dueDate < $1.dueDate }
        if let appointment = pendingAppointments.first(where: { calendar.startOfDay(for: $0.dueDate) == target }) {
            let timeText = appointmentTimeText(appointment.dueDate)
            return "记得明天 \(timeText) \(appointment.title)"
        }

        if isInjectionDue(on: tomorrow) {
            return "记得明天 10:00 \(state.injectionPlan.title)"
        }
        return nil
    }

    private func nearestPendingAppointmentWithin14Days() -> AppointmentItem? {
        let startDay = calendar.startOfDay(for: Date())
        let endDay = calendar.date(byAdding: .day, value: 14, to: startDay) ?? startDay

        return activeAppointments
            .filter { !$0.isDone }
            .filter { item in
                let day = calendar.startOfDay(for: item.dueDate)
                return day >= startDay && day <= endDay
            }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    private func normalizedTomorrowHint(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "明天暂无特殊安排" {
            return "明天目前没有特殊安排，我会继续盯着你今天的节奏。"
        }
        if trimmed.hasSuffix("。") || trimmed.hasSuffix("！") || trimmed.hasSuffix("？") {
            return trimmed
        }
        return trimmed + "。"
    }
}

extension TimePeriod {
    static func fromSemantic(_ text: String) -> TimePeriod? {
        if text.contains("起床") { return .wakeUp }
        if text.contains("早饭") || text.contains("早餐") || text.contains("早") { return .afterBreakfast }
        if text.contains("午饭") || text.contains("午餐") || text.contains("中午") || text.contains("午") { return .afterLunch }
        if text.contains("晚饭") || text.contains("晚餐") { return .afterDinner }
        if text.contains("睡前") || text.contains("睡觉前") { return .beforeSleep }
        return nil
    }
}
