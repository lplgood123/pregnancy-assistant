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
    var period: TimePeriod

    init(
        title: String,
        startDate: Date,
        endDate: Date,
        intervalDays: Int,
        detail: String,
        period: TimePeriod = .afterDinner
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.intervalDays = intervalDays
        self.detail = detail
        self.period = period
    }

    enum CodingKeys: String, CodingKey {
        case title
        case startDate
        case endDate
        case intervalDays
        case detail
        case period
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        intervalDays = try container.decodeIfPresent(Int.self, forKey: .intervalDays) ?? 1
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
        if let decodedPeriod = try container.decodeIfPresent(TimePeriod.self, forKey: .period) {
            period = decodedPeriod
        } else {
            period = Self.inferPeriod(from: detail) ?? .afterDinner
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(intervalDays, forKey: .intervalDays)
        try container.encode(detail, forKey: .detail)
        try container.encode(period, forKey: .period)
    }

    private static func inferPeriod(from detail: String) -> TimePeriod? {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let explicit = explicitTimeLabel(from: trimmed) {
            return TimePeriod.fromSemantic(explicit) ?? TimePeriod.allCases.first(where: { $0.rawValue == explicit })
        }

        if let matchedRawValue = TimePeriod.allCases.first(where: { trimmed.contains($0.rawValue) }) {
            return matchedRawValue
        }

        return TimePeriod.fromSemantic(trimmed)
    }

    private static func explicitTimeLabel(from detail: String) -> String? {
        guard let markerRange = detail.range(of: "时间：") else { return nil }
        let tail = detail[markerRange.upperBound...]
        let separators = CharacterSet(charactersIn: "；;\n")
        let raw = String(tail).components(separatedBy: separators).first ?? String(tail)
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
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
    var enableSystemReminders: Bool

    init(
        wakeUpTime: String,
        breakfastTime: String,
        lunchTime: String,
        dinnerTime: String,
        sleepTime: String,
        minutesBefore: Int,
        enableSystemReminders: Bool = false
    ) {
        self.wakeUpTime = wakeUpTime
        self.breakfastTime = breakfastTime
        self.lunchTime = lunchTime
        self.dinnerTime = dinnerTime
        self.sleepTime = sleepTime
        self.minutesBefore = minutesBefore
        self.enableSystemReminders = enableSystemReminders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wakeUpTime = try container.decodeIfPresent(String.self, forKey: .wakeUpTime) ?? "07:00"
        breakfastTime = try container.decodeIfPresent(String.self, forKey: .breakfastTime) ?? "08:30"
        lunchTime = try container.decodeIfPresent(String.self, forKey: .lunchTime) ?? "12:30"
        dinnerTime = try container.decodeIfPresent(String.self, forKey: .dinnerTime) ?? "18:30"
        sleepTime = try container.decodeIfPresent(String.self, forKey: .sleepTime) ?? "22:30"
        minutesBefore = try container.decodeIfPresent(Int.self, forKey: .minutesBefore) ?? 0
        enableSystemReminders = try container.decodeIfPresent(Bool.self, forKey: .enableSystemReminders) ?? false
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
    var lastHomeGreetingBusinessDateKey: String?
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
        lastHomeGreetingBusinessDateKey: String?,
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
        self.lastHomeGreetingBusinessDateKey = lastHomeGreetingBusinessDateKey
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
        case lastHomeGreetingBusinessDateKey
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
        lastHomeGreetingBusinessDateKey = try container.decodeIfPresent(String.self, forKey: .lastHomeGreetingBusinessDateKey)
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
            case .check: return "检查报告"
            case .appointment: return "预约"
            }
        }

        var color: Color {
            switch self {
            case .medication: return AppTheme.actionPrimary
            case .habit: return AppTheme.statusSuccess
            case .check: return AppTheme.statusInfo
            case .appointment: return Color(hex: "A48BBF")
            }
        }

        var colorSoft: Color {
            switch self {
            case .medication: return AppTheme.accentSoft
            case .habit: return AppTheme.statusSuccessSoft
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
        if isCompleted { return AppTheme.statusSuccess }
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

enum ResetMode {
    case appOnly
    case includeSystemReminders
}

enum ResetResult {
    case appOnly
    case appAndSystemCleared
    case appClearedSystemPermissionDenied
    case appClearedSystemFailed(String)
}

private struct WeightSnapshot {
    var value: Double
    var checkTime: Date
}

final class PregnancyStore: ObservableObject {
    @Published var state: AppState {
        didSet {
            saveState()
        }
    }
    @Published private(set) var reminderSyncRevision = 0
    @Published private(set) var resetEpoch = 0
    @Published var globalBanner: GlobalBanner?

    private let calendar = Calendar.current
    private let stateKey = "pregnancy_assistant_app_state_v2"
    private let onboardingSchemaVersion = 13
    private var bannerNonce: UUID?
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
        clearSeededSampleDataIfNeeded()
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
        state.homeChatMessages = []
        state.lastHomeGreetingBusinessDateKey = nil
        state.homeSummaryCache = nil
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

    func dismissGlobalBanner() {
        globalBanner = nil
        bannerNonce = nil
    }

    @MainActor
    @discardableResult
    func resetAllDataToFreshInstall(mode: ResetMode) async -> ResetResult {
        bannerNonce = nil
        globalBanner = nil
        state = Self.seedState()
        resetEpoch += 1
        markReminderRulesDirty()

        guard mode == .includeSystemReminders else {
            return .appOnly
        }

        await ReminderScheduler.clearAllPendingNotifications()
        let systemStatus = await SystemReminderSyncService.clearAppManagedReminders()
        switch systemStatus {
        case .success, .skippedDisabled:
            return .appAndSystemCleared
        case .permissionDenied:
            return .appClearedSystemPermissionDenied
        case .failed(let reason):
            return .appClearedSystemFailed(reason)
        }
    }

    func homeBusinessDateKey(now: Date = Date()) -> String {
        let todayStart = calendar.startOfDay(for: now)
        let boundary = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: todayStart) ?? todayStart
        let businessDay = now < boundary
            ? (calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart)
            : todayStart
        return dateKey(for: businessDay)
    }

    func dailyGreetingText(now: Date = Date()) -> String {
        let dateLine = homeDateText(for: now)
        let baseInfo = "当前孕周：孕\(gestationalWeekText)，预产期 \(formatDate(dueDate))。"

        let pendingItems = timelineItems(for: now)
            .filter { !$0.isCompleted }
            .sorted { (timeToMinutes($0.timeText) ?? 0) < (timeToMinutes($1.timeText) ?? 0) }
            .prefix(4)
            .map { item in
                "\(item.timeText) \(item.title)"
            }

        let todoLine: String
        if pendingItems.isEmpty {
            todoLine = "今天自然日待办：目前没有未完成安排。"
        } else {
            todoLine = "今天自然日待办：\(pendingItems.joined(separator: "；"))。"
        }

        let name = state.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hello = name.isEmpty ? "早上好，今天是\(dateLine)。" : "\(name)早上好，今天是\(dateLine)。"
        return [hello, baseInfo, todoLine].joined(separator: "\n")
    }

    func takeDailyGreetingIfNeeded(now: Date = Date()) -> HomeChatMessage? {
        let businessKey = homeBusinessDateKey(now: now)
        if state.lastHomeGreetingBusinessDateKey == businessKey {
            return nil
        }

        state.lastHomeGreetingBusinessDateKey = businessKey
        return HomeChatMessage(
            role: .assistant,
            kind: .text,
            text: dailyGreetingText(now: now),
            createdAt: now
        )
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

    func deleteMedication(id: String) {
        guard let index = state.medications.firstIndex(where: { $0.id == id }) else { return }
        state.medications.remove(at: index)
        state.completedDailyTaskIDs.removeAll { $0 == "med-\(id)" }
        markReminderRulesDirty()
    }

    func deleteMedicationGroup(named name: String) {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return }
        let removedIDs = state.medications
            .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target }
            .map(\.id)
        guard !removedIDs.isEmpty else { return }

        state.medications.removeAll { med in
            med.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target
        }
        for id in removedIDs {
            state.completedDailyTaskIDs.removeAll { $0 == "med-\(id)" }
        }
        markReminderRulesDirty()
    }

    func deleteAppointment(id: String) {
        guard let index = state.appointments.firstIndex(where: { $0.id == id }) else { return }
        state.appointments.remove(at: index)
        markReminderRulesDirty()
    }

    func deleteCheckRecord(id: String) {
        guard var list = state.checkRecords else { return }
        let originalCount = list.count
        list.removeAll { $0.id == id }
        guard list.count != originalCount else { return }
        state.checkRecords = list
        state.labRecords.removeAll { $0.id == id }
    }

    @available(*, deprecated, message: "Use deleteMedication(id:) instead.")
    func archiveMedication(id: String) {
        deleteMedication(id: id)
    }

    @available(*, deprecated, message: "Use deleteMedicationGroup(named:) instead.")
    func archiveMedicationGroup(named name: String) {
        deleteMedicationGroup(named: name)
    }

    @available(*, deprecated, message: "Use deleteAppointment(id:) instead.")
    func archiveAppointment(id: String) {
        deleteAppointment(id: id)
    }

    @available(*, deprecated, message: "Use deleteCheckRecord(id:) instead.")
    func archiveCheckRecord(id: String) {
        deleteCheckRecord(id: id)
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

    func latestWeightComparisonInfo() -> (latestText: String, deltaText: String?)? {
        let snapshots = weightSnapshots()
        guard let latest = snapshots.first else { return nil }
        let latestValue = formattedBodyMetric(latest.value, maxFractionDigits: 1)
        let latestText = "最新（\(formatDate(latest.checkTime))）：\(latestValue) kg"

        guard snapshots.count > 1, let previous = snapshots.dropFirst().first else {
            return (latestText: latestText, deltaText: "这是第一条体重记录")
        }
        let delta = latest.value - previous.value
        let deltaSign = delta >= 0 ? "+" : "-"
        let deltaText = "较上次（\(formatDate(previous.checkTime))）：\(deltaSign)\(formattedBodyMetric(abs(delta), maxFractionDigits: 1)) kg"
        return (latestText: latestText, deltaText: deltaText)
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
        let defaults = AIConfigProvider.defaultConfig()
        let stored = state.aiConfig
        let overrides = AIConfigProvider.environmentOverrides()

        let storedBase = stored?.baseURL.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedKey = stored?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedModel = stored?.model.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let defaultBase = defaults.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultKey = defaults.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultModel = defaults.model.trimmingCharacters(in: .whitespacesAndNewlines)

        // Prefer app-level defaults so all devices converge on the cloud backend.
        // Stored values are treated as fallback only when defaults are missing.
        var baseURL = defaultBase.isEmpty ? storedBase : defaultBase
        var apiKey = defaultKey.isEmpty ? storedKey : defaultKey
        var model = defaultModel.isEmpty ? storedModel : defaultModel

        if let overrideBase = overrides.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !overrideBase.isEmpty {
            baseURL = overrideBase
        }
        if let overrideKey = overrides.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !overrideKey.isEmpty {
            apiKey = overrideKey
        }
        if let overrideModel = overrides.model?.trimmingCharacters(in: .whitespacesAndNewlines), !overrideModel.isEmpty {
            model = overrideModel
        }

        if model.isEmpty {
            model = AIConfigProvider.fallbackModel
        }

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
            let meds = medicationItemsFromAISlots(action.slots)
            if meds.isEmpty { return "缺少用药名称" }
            meds.forEach(addMedication)

            if meds.count == 1, let med = meds.first {
                return "已创建用药：\(med.name)\(med.dosage.isEmpty ? "" : " · \(med.dosage)")\(med.note.isEmpty ? "" : " · \(med.note)")"
            }

            let previewNames = meds.prefix(5).map(\.name).joined(separator: "、")
            let suffix = meds.count > 5 ? " 等" : ""
            return "已创建用药 \(meds.count) 项：\(previewNames)\(suffix)"
        case "create_appointment":
            let titleRaw = firstNonEmptyText(
                action.slots["item_name"],
                action.slots["appointment_title"],
                action.slots["title"],
                action.slots["check_type"]
            ) ?? ""
            let title = titleRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "医院复诊"
                : titleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            let dueDate = appointmentDueDate(from: action.slots)
            let detail = action.slots["note"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            addAppointment(
                title: title,
                dueDate: dueDate,
                detail: detail.isEmpty ? "复诊安排" : detail
            )
            return "已创建预约：\(title)（\(formatDate(dueDate)) \(appointmentTimeText(dueDate))）"
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
                    return "检查报告数值不完整"
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
                return "已保存检查报告：HCG \(formatValue(hcg)) / P \(formatValue(p)) / E2 \(formatValue(e2))"
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
            return "已保存\(type.title)报告"
        case "create_reminder":
            let rawTitle = action.slots["item_name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = rawTitle.isEmpty ? "提醒" : rawTitle
            let note = action.slots["note"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let frequency = action.slots["frequency"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let period = TimePeriod.fromSemantic(action.slots["time_semantic"] ?? "") ?? .afterDinner

            if isInjectionReminder(title: title, note: note, frequency: frequency) {
                let intervalDays = parseReminderIntervalDays(
                    from: [
                        frequency,
                        action.slots["date_semantic"] ?? "",
                        note
                    ]
                ) ?? 2
                let startDate = reminderStartDate(from: action.slots)
                let startDay = calendar.startOfDay(for: startDate)
                let endDay = max(calendar.startOfDay(for: dueDate), startDay)
                let planTitle = normalizedInjectionTitle(from: title, note: note)
                var detailParts: [String] = []
                if !note.isEmpty {
                    detailParts.append(note)
                }
                detailParts.append("频率：每\(intervalDays)天一次")
                detailParts.append("时间：\(period.rawValue)")
                detailParts.append("开始：\(formatDate(startDay))")

                state.injectionPlan = InjectionPlan(
                    title: planTitle,
                    startDate: startDay,
                    endDate: endDay,
                    intervalDays: max(intervalDays, 1),
                    detail: detailParts.joined(separator: "；"),
                    period: period
                )
                markReminderRulesDirty()
                return "已更新打针计划：\(planTitle)（每\(intervalDays)天一次，\(period.rawValue)）"
            }

            addExtraDailyReminder(
                title: title,
                detail: note.isEmpty ? "提醒事项" : note,
                period: period
            )
            let detail = note.isEmpty ? "" : " · \(note)"
            return "已创建提醒：\(title)\(detail)"
        case "update_profile":
            let parsed = parseProfileMetrics(from: action.slots)
            guard parsed.heightCM != nil || parsed.weightKG != nil else {
                return "没识别到可记录的身高或体重，请说“身高165厘米、体重52.3公斤”。"
            }

            var profile = state.profile
            var updatedFields: [String] = []

            if let height = parsed.heightCM {
                let heightText = formattedBodyMetric(height, maxFractionDigits: 1)
                profile.heightCM = heightText
                updatedFields.append("身高 \(heightText) cm")
            }

            var weightAnalysis = ""
            if let weight = parsed.weightKG {
                let checkDate = parseFlexibleDate(action.slots["check_date"])
                let previousWeight = latestWeightSnapshot()
                let weightText = formattedBodyMetric(weight, maxFractionDigits: 1)
                profile.weightKG = weightText

                if calendar.isDateInToday(checkDate) {
                    ensureDailyCheckinForToday()
                    state.dailyCheckin?.weightKG = weightText
                }

                upsertWeightCheckRecord(weight: weight, checkTime: checkDate)
                updatedFields.append("体重 \(weightText) kg")
                weightAnalysis = weightAssessmentText(newWeight: weight, previous: previousWeight, on: checkDate)
            }

            state.profile = profile
            var reply = "已记录：\(updatedFields.joined(separator: "，"))。"
            if !weightAnalysis.isEmpty {
                reply += "\n\(weightAnalysis)"
            }
            return reply
        case "update_reminder_time":
            let semantic = action.slots["time_semantic"] ?? ""
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
                } else if timeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let linked = reminderTime(for: period)
                    updatedParts.append("\(period.rawValue)提醒（沿用 \(linked)）")
                }
            }

            if updatedParts.isEmpty {
                return "没识别到要修改的提醒时段或时间"
            }
            if changed {
                saveReminderConfig(config)
            }
            return "已更新：" + updatedParts.joined(separator: "；")
        default:
            return "暂不支持该操作"
        }
    }

    private struct AIMedicationPayload {
        let name: String
        let dosage: String
        let note: String
        let timeSemantic: String
    }

    private func medicationItemsFromAISlots(_ slots: [String: String]) -> [MedicationItem] {
        let defaultSemantic = slots["time_semantic"] ?? ""
        let defaultPeriod = TimePeriod.fromSemantic(defaultSemantic) ?? .afterDinner

        var payloads = parseBatchMedicationPayloads(from: slots, defaultSemantic: defaultSemantic)
        if payloads.isEmpty {
            let singleName = slots["item_name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if singleName.isEmpty { return [] }
            payloads = [
                AIMedicationPayload(
                    name: singleName,
                    dosage: slots["dosage"] ?? "",
                    note: slots["note"] ?? "",
                    timeSemantic: defaultSemantic
                )
            ]
        }

        return payloads.compactMap { payload in
            let trimmedName = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty { return nil }
            return MedicationItem(
                id: UUID().uuidString,
                period: TimePeriod.fromSemantic(payload.timeSemantic) ?? defaultPeriod,
                name: trimmedName,
                dosage: payload.dosage.trimmingCharacters(in: .whitespacesAndNewlines),
                note: payload.note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func parseBatchMedicationPayloads(from slots: [String: String], defaultSemantic: String) -> [AIMedicationPayload] {
        let fallbackNote = slots["note"] ?? ""
        let slotKeys = ["medications", "medication_items", "items"]

        for key in slotKeys {
            guard let raw = slots[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                continue
            }
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            let arrayValue: [[String: Any]]
            if let list = json as? [[String: Any]] {
                arrayValue = list
            } else if let dict = json as? [String: Any],
                      let nested = dict["medications"] as? [[String: Any]] {
                arrayValue = nested
            } else {
                continue
            }

            let parsed = arrayValue.compactMap { item in
                parseMedicationPayload(from: item, defaultSemantic: defaultSemantic, fallbackNote: fallbackNote)
            }
            if !parsed.isEmpty {
                return parsed
            }
        }

        return []
    }

    private func isInjectionReminder(title: String, note: String, frequency: String) -> Bool {
        let text = [title, note, frequency]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !text.isEmpty else { return false }

        let keywords = [
            "打针", "注射", "针剂", "肝素", "肌注", "皮下"
        ]
        return keywords.contains { text.contains($0) }
    }

    private func normalizedInjectionTitle(from title: String, note: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != "提醒" {
            return trimmed
        }
        if note.contains("肝素") {
            return "肝素注射"
        }
        let existing = state.injectionPlan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return existing.isEmpty ? "打针提醒" : existing
    }

    private func parseReminderIntervalDays(from texts: [String]) -> Int? {
        let text = texts
            .joined(separator: " ")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        guard !text.isEmpty else { return nil }

        if ["隔一天", "隔天", "隔日", "每隔一天", "每两天", "每2天", "隔1天", "qod"].contains(where: text.contains) {
            return 2
        }
        if ["每天", "每日", "一天一次", "每1天", "qd"].contains(where: text.contains) {
            return 1
        }
        if text.contains("每周") {
            return 7
        }
        if let dayValue = firstIntCapture(in: text, pattern: #"每(\d+)天"#) {
            return max(dayValue, 1)
        }
        return nil
    }

    private func reminderStartDate(from slots: [String: String]) -> Date {
        let candidates = [
            slots["start_date"],
            slots["startDate"],
            slots["date_semantic"],
            slots["check_date"],
            slots["note"]
        ]
        for candidate in candidates {
            guard let candidate else { continue }
            if let parsed = parseReminderDate(candidate) {
                return calendar.startOfDay(for: parsed)
            }
        }
        return calendar.startOfDay(for: Date())
    }

    private func appointmentDueDate(from slots: [String: String]) -> Date {
        let baseDate = firstNonEmptyText(
            slots["check_date"],
            slots["due_date"],
            slots["appointment_date"],
            slots["date_semantic"],
            slots["note"]
        ).flatMap { parseReminderDate($0) } ?? Date()

        let timeText = firstNonEmptyText(
            slots["time_exact"],
            slots["appointment_time"]
        ) ?? ""
        let normalizedTime = normalizeTimeText(timeText) ?? "09:00"
        let timeParts = normalizedTime.split(separator: ":")
        let hour = timeParts.count == 2 ? (Int(timeParts[0]) ?? 9) : 9
        let minute = timeParts.count == 2 ? (Int(timeParts[1]) ?? 0) : 0

        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? baseDate
    }

    private func parseReminderDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("后天") {
            return calendar.date(byAdding: .day, value: 2, to: Date())
        }
        if trimmed.contains("明天") || trimmed.contains("明日") {
            return calendar.date(byAdding: .day, value: 1, to: Date())
        }
        if trimmed.contains("今天") || trimmed.contains("今日") {
            return Date()
        }

        if let weekdayDate = parseWeekdayDate(from: trimmed) {
            return weekdayDate
        }

        let pattern = #"(?:(\d{4})\s*[年/\-\.])?\s*(\d{1,2})\s*[月/\-\.]\s*(\d{1,2})\s*日?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else { return nil }

        let year = intCapture(match: match, group: 1, source: trimmed) ?? calendar.component(.year, from: Date())
        guard
            let month = intCapture(match: match, group: 2, source: trimmed),
            let day = intCapture(match: match, group: 3, source: trimmed)
        else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    private func parseWeekdayDate(from text: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"(下周|本周)?\s*(周|星期|礼拜)\s*([一二三四五六日天])"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        var isNextWeek = false
        if let prefixRange = Range(match.range(at: 1), in: text) {
            let prefix = String(text[prefixRange])
            isNextWeek = prefix.contains("下周")
        }

        guard let weekdayTextRange = Range(match.range(at: 3), in: text) else {
            return nil
        }
        let weekdayText = String(text[weekdayTextRange])
        let targetWeekday: Int
        switch weekdayText {
        case "日", "天":
            targetWeekday = 1
        case "一":
            targetWeekday = 2
        case "二":
            targetWeekday = 3
        case "三":
            targetWeekday = 4
        case "四":
            targetWeekday = 5
        case "五":
            targetWeekday = 6
        case "六":
            targetWeekday = 7
        default:
            return nil
        }

        let today = calendar.startOfDay(for: Date())
        let currentWeekday = calendar.component(.weekday, from: today)
        var diff = (targetWeekday - currentWeekday + 7) % 7
        if isNextWeek {
            diff += 7
        }
        return calendar.date(byAdding: .day, value: diff, to: today)
    }

    private func firstIntCapture(in source: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range) else { return nil }
        return intCapture(match: match, group: 1, source: source)
    }

    private func intCapture(match: NSTextCheckingResult, group: Int, source: String) -> Int? {
        guard group < match.numberOfRanges else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: source) else { return nil }
        return Int(source[swiftRange])
    }

    private func parseMedicationPayload(
        from item: [String: Any],
        defaultSemantic: String,
        fallbackNote: String
    ) -> AIMedicationPayload? {
        guard let name = firstNonEmptyText(
            item["item_name"],
            item["name"],
            item["title"]
        ) else {
            return nil
        }

        let dosage = firstNonEmptyText(
            item["dosage"],
            item["dose"],
            item["amount"],
            item["quantity"]
        ) ?? ""
        let note = firstNonEmptyText(
            item["note"],
            item["remark"],
            item["memo"]
        ) ?? fallbackNote
        let timeSemantic = firstNonEmptyText(
            item["time_semantic"],
            item["period"],
            item["time"],
            item["time_label"]
        ) ?? defaultSemantic

        return AIMedicationPayload(
            name: name,
            dosage: dosage,
            note: note,
            timeSemantic: timeSemantic
        )
    }

    private func firstNonEmptyText(_ values: Any?...) -> String? {
        for value in values {
            let text: String
            if let stringValue = value as? String {
                text = stringValue
            } else if let numberValue = value as? NSNumber {
                text = numberValue.stringValue
            } else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func parseProfileMetrics(from slots: [String: String]) -> (heightCM: Double?, weightKG: Double?) {
        let heightRaw = firstNonEmptyText(
            slots["height_cm"],
            slots["heightCM"],
            slots["height"],
            slots["stature"]
        )
        let weightRaw = firstNonEmptyText(
            slots["weight_kg"],
            slots["weightKG"],
            slots["weight"],
            slots["body_weight"]
        )
        return (
            heightCM: parseBodyMetric(heightRaw),
            weightKG: parseWeightMetric(weightRaw)
        )
    }

    private func parseBodyMetric(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = Double(trimmed) {
            return direct
        }
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)"#) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }
        return Double(trimmed[swiftRange])
    }

    private func parseWeightMetric(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        guard let value = parseBodyMetric(raw) else { return nil }
        let normalizedRaw = raw.lowercased()
        if normalizedRaw.contains("斤") {
            return value / 2.0
        }
        return value
    }

    private func formattedBodyMetric(_ value: Double, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxFractionDigits)f", value)
    }

    private func weightSnapshots() -> [WeightSnapshot] {
        sortedCheckRecords().compactMap { record in
            guard let weightValue = weightValue(from: record) else { return nil }
            return WeightSnapshot(value: weightValue, checkTime: record.checkTime)
        }
    }

    private func latestWeightSnapshot() -> WeightSnapshot? {
        weightSnapshots().first
    }

    private func weightValue(from record: CheckRecord) -> Double? {
        for metric in record.metrics {
            if metric.key == "weight_kg" || metric.label.contains("体重") {
                let rawValue = [metric.valueText, metric.unit]
                    .joined(separator: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = parseWeightMetric(rawValue) {
                    return value
                }
            }
        }
        return nil
    }

    private func upsertWeightCheckRecord(weight: Double, checkTime: Date) {
        let metric = CheckMetric(
            key: "weight_kg",
            label: "体重",
            valueText: formattedBodyMetric(weight, maxFractionDigits: 1),
            unit: "kg",
            referenceLowText: nil,
            referenceHighText: nil
        )
        var list = state.checkRecords ?? []
        if let index = list.firstIndex(where: { record in
            record.type == .custom &&
            record.source == .ai &&
            calendar.isDate(record.checkTime, inSameDayAs: checkTime) &&
            record.metrics.contains(where: { $0.key == "weight_kg" || $0.label.contains("体重") })
        }) {
            list[index].checkTime = checkTime
            list[index].metrics = [metric]
            list[index].note = "体重记录"
            list[index].isArchived = false
            state.checkRecords = list
            return
        }

        addCheckRecord(
            CheckRecord(
                id: UUID().uuidString,
                type: .custom,
                checkTime: checkTime,
                metrics: [metric],
                note: "体重记录",
                source: .ai
            )
        )
    }

    private func weightAssessmentText(newWeight: Double, previous: WeightSnapshot?, on checkDate: Date) -> String {
        var parts: [String] = []
        if let previous {
            let delta = newWeight - previous.value
            let sign = delta >= 0 ? "+" : "-"
            parts.append("较上次\(formatDate(previous.checkTime)) \(sign)\(formattedBodyMetric(abs(delta), maxFractionDigits: 1))kg。")

            let days = max(calendar.dateComponents([.day], from: previous.checkTime, to: checkDate).day ?? 0, 0)
            if days >= 3 {
                let weeklyRate = delta * 7.0 / Double(days)
                if weeklyRate > 1.0 {
                    parts.append("近期增重偏快。")
                } else if weeklyRate < -0.6 {
                    parts.append("近期体重下降偏明显。")
                } else {
                    parts.append("近期体重变化在常见范围。")
                }
            } else if abs(delta) <= 0.5 {
                parts.append("近期波动不大。")
            }
        } else {
            parts.append("这是第一条体重记录。")
        }

        let week = gestationalWeekText(for: checkDate)
        if gestationalWeekNumber < 14 {
            parts.append("当前约孕\(week)，孕早期体重小幅波动常见，通常总增重 0-2kg。")
        } else {
            parts.append("当前约孕\(week)，中晚孕每周增加约 0.3-0.5kg 较常见。")
        }
        parts.append("若一周内骤增>1kg、持续下降，或伴明显水肿/头痛，请尽快联系医生。")
        return parts.joined(separator: "")
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
        if let config = state.reminderConfig {
            return ReminderConfig(
                wakeUpTime: config.wakeUpTime,
                breakfastTime: config.breakfastTime,
                lunchTime: config.lunchTime,
                dinnerTime: config.dinnerTime,
                sleepTime: config.sleepTime,
                minutesBefore: 0,
                enableSystemReminders: config.enableSystemReminders
            )
        }
        return ReminderConfig(
            wakeUpTime: "07:00",
            breakfastTime: "08:30",
            lunchTime: "12:30",
            dinnerTime: "18:30",
            sleepTime: "22:30",
            minutesBefore: 0,
            enableSystemReminders: false
        )
    }

    func saveReminderConfig(_ config: ReminderConfig) {
        state.reminderConfig = ReminderConfig(
            wakeUpTime: config.wakeUpTime.trimmingCharacters(in: .whitespacesAndNewlines),
            breakfastTime: config.breakfastTime.trimmingCharacters(in: .whitespacesAndNewlines),
            lunchTime: config.lunchTime.trimmingCharacters(in: .whitespacesAndNewlines),
            dinnerTime: config.dinnerTime.trimmingCharacters(in: .whitespacesAndNewlines),
            sleepTime: config.sleepTime.trimmingCharacters(in: .whitespacesAndNewlines),
            minutesBefore: 0,
            enableSystemReminders: config.enableSystemReminders
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
        身高：\(profile.heightCM ?? "未记录")cm，体重：\(profile.weightKG ?? "未记录")kg
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
        let templates = [
            "我会提醒你按时吃药、按计划打针，也会盯着就诊和你设置的提醒。",
            "今天我会帮你盯住用药、打针、就诊和其他提醒安排。"
        ]
        let index = calendar.component(.day, from: Date()) % templates.count
        let progressText: String
        if summary.left == 0 {
            progressText = "今天当前待办已完成。"
        } else {
            progressText = "今天还有 \(summary.left) 项待办，我会继续提醒。"
        }
        return "\(templates[index])\(progressText)\(tomorrow)"
    }

    func homeSummarySnapshotText() -> String {
        let summary = homeSummary()
        let todayItems = timelineItems(for: Date())
        let pendingItems = todayItems
            .filter { !$0.isCompleted }
            .sorted { (timeToMinutes($0.timeText) ?? 0) < (timeToMinutes($1.timeText) ?? 0) }
            .prefix(5)

        var pendingGroups: [String] = []
        let hasMedication = pendingItems.contains { $0.kind == .medication }
        let hasCheck = pendingItems.contains { $0.kind == .check }
        let hasAppointment = pendingItems.contains { $0.kind == .appointment }
        if hasMedication {
            pendingGroups.append("按时吃药")
        }
        if hasCheck || isInjectionDueToday() {
            pendingGroups.append("打针/检查报告")
        }
        if hasAppointment {
            pendingGroups.append("就诊安排")
        }
        if !state.extraDailyItems.isEmpty {
            pendingGroups.append("其他提醒")
        }
        let pendingText = pendingGroups.isEmpty ? "今天待办已清空" : pendingGroups.joined(separator: "、")

        let reviewText: String
        if let upcoming = nearestPendingAppointmentWithin14Days() {
            reviewText = "\(formatDate(upcoming.dueDate)) \(appointmentTimeText(upcoming.dueDate)) \(upcoming.title)"
        } else {
            reviewText = "近期暂无复查安排"
        }

        let reminderText = state.extraDailyItems.isEmpty ? "无额外提醒" : "有\(state.extraDailyItems.count)条自定义提醒"
        let nextText: String
        if let next = nextUpcomingMedication() {
            nextText = "\(next.period.rawValue)（\(next.timeText)）"
        } else {
            nextText = "今日用药提醒已完成"
        }

        return """
        当前孕周：\(gestationalWeekText)
        预产期：\(formatDate(dueDate))
        今日进度：总\(summary.total)项，已完成\(summary.done)项，剩余\(summary.left)项
        今日重点：\(pendingText)
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
                QuickCommand(title: "今日安排", prompt: "请汇总我今天需要注意的安排：用药、打针、回诊和其他提醒。", icon: "calendar.badge.clock"),
                QuickCommand(title: "记录妊娠三项", prompt: "我今天做了妊娠三项，帮我记录", icon: "testtube.2"),
                QuickCommand(title: "用药调整", prompt: "我有用药要调整，帮我记录。请先问我具体要调整哪些药、时间和剂量。", icon: "pills"),
                QuickCommand(title: "加复查预约", prompt: "我想新增一个复查预约，先问我日期和时间后再帮我记录。", icon: "calendar"),
                QuickCommand(title: "明天吃什么药", prompt: "帮我按时段列出明天要吃的药。", icon: "list.bullet.clipboard"),
                QuickCommand(title: "调整提醒时间", prompt: "我想调整提醒时间，先问我想改哪个时段和改到几点。", icon: "alarm")
            ]
        case .middle:
            return [
                QuickCommand(title: "今日安排", prompt: "请汇总我今天需要注意的安排：用药、打针、回诊和其他提醒。", icon: "calendar.badge.clock"),
                QuickCommand(title: "记录NT/唐筛", prompt: "我今天做了NT或唐筛，帮我记录", icon: "chart.bar"),
                QuickCommand(title: "加复查预约", prompt: "我想新增一个复查预约，先问我日期和时间后再帮我记录。", icon: "cross.case"),
                QuickCommand(title: "用药调整", prompt: "我有用药要调整，帮我记录。请先问我具体要调整哪些药、时间和剂量。", icon: "pills"),
                QuickCommand(title: "明天吃什么药", prompt: "帮我按时段列出明天要吃的药。", icon: "list.bullet.clipboard"),
                QuickCommand(title: "调整提醒时间", prompt: "我想调整提醒时间，先问我想改哪个时段和改到几点。", icon: "alarm")
            ]
        case .late:
            return [
                QuickCommand(title: "今日安排", prompt: "请汇总我今天需要注意的安排：用药、打针、回诊和其他提醒。", icon: "calendar.badge.clock"),
                QuickCommand(title: "记录胎动", prompt: "我想记录今天胎动情况", icon: "figure.and.child.holdinghands"),
                QuickCommand(title: "加复查预约", prompt: "我想新增一个复查预约，先问我日期和时间后再帮我记录。", icon: "cross.case"),
                QuickCommand(title: "用药调整", prompt: "我有用药要调整，帮我记录。请先问我具体要调整哪些药、时间和剂量。", icon: "pills"),
                QuickCommand(title: "明天吃什么药", prompt: "帮我按时段列出明天要吃的药。", icon: "list.bullet.clipboard"),
                QuickCommand(title: "调整提醒时间", prompt: "我想调整提醒时间，先问我想改哪个时段和改到几点。", icon: "alarm")
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

    private func clearSeededSampleDataIfNeeded() {
        guard state.onboardingRequiredAtLeastOnce else { return }
        let hasLegacySeedName = state.profile.name.trimmingCharacters(in: .whitespacesAndNewlines) == "余丽佳"
        let hasLegacyMedicationIDs = state.medications.contains { $0.id.hasPrefix("med") }
        let hasLegacyAppointmentID = state.appointments.contains { $0.id.hasPrefix("appt-2026") }
        guard hasLegacySeedName || hasLegacyMedicationIDs || hasLegacyAppointmentID else { return }

        let today = Date()
        state.profile = Profile(
            name: "",
            gender: "女",
            birthDate: Calendar.current.date(byAdding: .year, value: -28, to: today) ?? today,
            lastPeriodDate: Calendar.current.date(byAdding: .day, value: -42, to: today) ?? today,
            ivfTransferDate: today,
            firstPositiveDate: today,
            stepsGoal: 8000,
            waterGoalML: 1200,
            heightCM: nil,
            weightKG: nil,
            allergyHistory: nil,
            doctorContact: nil
        )
        state.medications = []
        state.appointments = []
        state.labRecords = []
        state.checkRecords = []
        state.aiConversation = []
        state.aiPendingActions = []
        state.homeChatMessages = []
        state.lastHomeGreetingBusinessDateKey = nil
        state.homeSummaryCache = nil
        state.completedDailyTaskIDs = []
        state.todayNotes = []
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
        parseFlexibleDateOptional(text) ?? Date()
    }

    private func parseFlexibleDateOptional(_ text: String?) -> Date? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let semanticDate = parseReminderDate(trimmed) {
            return semanticDate
        }

        let fmts = ["yyyy-MM-dd", "yyyy/MM/dd", "MM-dd", "M月d日"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        for format in fmts {
            formatter.dateFormat = format
            if let d = formatter.date(from: trimmed) { return d }
        }
        return nil
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
        let today = Date()
        let profile = Profile(
            name: "",
            gender: "女",
            birthDate: Calendar.current.date(byAdding: .year, value: -28, to: today) ?? today,
            lastPeriodDate: Calendar.current.date(byAdding: .day, value: -42, to: today) ?? today,
            ivfTransferDate: today,
            firstPositiveDate: today,
            stepsGoal: 8000,
            waterGoalML: 1200
        )

        let habits: [DailyHabitItem] = [
            DailyHabitItem(id: "steps", title: "每日走够 10000 步"),
            DailyHabitItem(id: "water", title: "每日喝够 1L 水")
        ]

        let injectionPlan = InjectionPlan(
            title: "暂无注射计划",
            startDate: today,
            endDate: Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today,
            intervalDays: 2,
            detail: "暂无注射安排",
            period: .afterDinner
        )

        let formatter2 = DateFormatter()
        formatter2.dateFormat = "yyyy-MM-dd"
        let todayKey = formatter2.string(from: Date())

        return AppState(
            profile: profile,
            medications: [],
            dailyHabits: habits,
            extraDailyItems: [],
            todayNotes: [],
            appointments: [],
            injectionPlan: injectionPlan,
            labRecords: [],
            checkRecords: [],
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
                model: AIConfigProvider.fallbackModel
            ),
            reminderConfig: ReminderConfig(
                wakeUpTime: "07:00",
                breakfastTime: "08:30",
                lunchTime: "12:30",
                dinnerTime: "18:30",
                sleepTime: "22:30",
                minutesBefore: 0,
                enableSystemReminders: false
            ),
            aiConversation: [],
            aiLongTermMemory: "",
            aiPendingActions: [],
            homeChatMessages: [],
            lastHomeGreetingBusinessDateKey: nil,
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
