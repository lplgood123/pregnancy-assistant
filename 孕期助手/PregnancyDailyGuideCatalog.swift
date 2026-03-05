import Foundation

struct DailyWarmCopyEntry: Codable {
    let dayIndex: Int
    let weekText: String
    let babyChange: String
    let momChange: String

    enum CodingKeys: String, CodingKey {
        case dayIndex = "d"
        case weekText = "w"
        case babyChange = "b"
        case momChange = "m"
    }
}

struct WeeklyWarmGuideEntry: Codable {
    let week: Int
    let babyWeekSummary: String
    let growthLengthCM: String
    let growthWeightG: String
    let growthAnalogy: String
    let momWeekSummary: String

    enum CodingKeys: String, CodingKey {
        case week
        case babyWeekSummary = "baby_week_summary"
        case growthLengthCM = "growth_length_cm"
        case growthWeightG = "growth_weight_g"
        case growthAnalogy = "growth_analogy"
        case momWeekSummary = "mom_week_summary"
    }
}

final class PregnancyDailyGuideCatalog {
    static let shared = PregnancyDailyGuideCatalog()

    private let queue = DispatchQueue(label: "PregnancyDailyGuideCatalog.queue", qos: .utility)
    private var cachedDailyEntries: [Int: DailyWarmCopyEntry]?
    private var cachedWeeklyEntries: [Int: WeeklyWarmGuideEntry]?

    private init() {}

    func preloadIfNeeded() {
        queue.async {
            if self.cachedDailyEntries == nil {
                self.cachedDailyEntries = self.loadDailyEntriesFromBundle()
            }
            if self.cachedWeeklyEntries == nil {
                self.cachedWeeklyEntries = self.loadWeeklyEntriesFromBundle()
            }
        }
    }

    func dailyEntry(for dayIndex: Int) -> DailyWarmCopyEntry {
        let safeDay = max(1, min(280, dayIndex))
        let entries = queue.sync {
            if let cachedDailyEntries {
                return cachedDailyEntries
            }
            let loaded = loadDailyEntriesFromBundle()
            cachedDailyEntries = loaded
            return loaded
        }
        return entries[safeDay] ?? fallbackDailyEntry(for: safeDay)
    }

    func weeklyEntry(for week: Int) -> WeeklyWarmGuideEntry {
        let safeWeek = max(0, min(40, week))
        let entries = queue.sync {
            if let cachedWeeklyEntries {
                return cachedWeeklyEntries
            }
            let loaded = loadWeeklyEntriesFromBundle()
            cachedWeeklyEntries = loaded
            return loaded
        }
        return entries[safeWeek] ?? fallbackWeeklyEntry(for: safeWeek)
    }

    private func loadDailyEntriesFromBundle() -> [Int: DailyWarmCopyEntry] {
        let resourceNames = ["pregnancy_daily_warm_zh", "pregnancy_daily_guide_zh"]
        for resourceName in resourceNames {
            guard
                let fileURL = resourceURL(forResource: resourceName),
                let data = try? Data(contentsOf: fileURL),
                let list = try? JSONDecoder().decode([DailyWarmCopyEntry].self, from: data)
            else {
                continue
            }

            var map: [Int: DailyWarmCopyEntry] = [:]
            map.reserveCapacity(list.count)
            for item in list {
                let clamped = max(1, min(280, item.dayIndex))
                map[clamped] = DailyWarmCopyEntry(
                    dayIndex: clamped,
                    weekText: item.weekText,
                    babyChange: item.babyChange,
                    momChange: item.momChange
                )
            }

            if !map.isEmpty {
                return fillDailyGaps(map)
            }
        }
        return fallbackDailyCatalog()
    }

    private func loadWeeklyEntriesFromBundle() -> [Int: WeeklyWarmGuideEntry] {
        guard
            let fileURL = resourceURL(forResource: "pregnancy_weekly_warm_zh"),
            let data = try? Data(contentsOf: fileURL),
            let list = try? JSONDecoder().decode([WeeklyWarmGuideEntry].self, from: data)
        else {
            return fallbackWeeklyCatalog()
        }

        var map: [Int: WeeklyWarmGuideEntry] = [:]
        map.reserveCapacity(list.count)
        for item in list {
            let clamped = max(0, min(40, item.week))
            map[clamped] = WeeklyWarmGuideEntry(
                week: clamped,
                babyWeekSummary: item.babyWeekSummary,
                growthLengthCM: item.growthLengthCM,
                growthWeightG: item.growthWeightG,
                growthAnalogy: item.growthAnalogy,
                momWeekSummary: item.momWeekSummary
            )
        }

        if map.isEmpty {
            return fallbackWeeklyCatalog()
        }

        var finalMap: [Int: WeeklyWarmGuideEntry] = [:]
        finalMap.reserveCapacity(41)
        var previous = fallbackWeeklyEntry(for: 0)
        for week in 0...40 {
            if let current = map[week] {
                previous = current
                finalMap[week] = current
            } else {
                finalMap[week] = WeeklyWarmGuideEntry(
                    week: week,
                    babyWeekSummary: previous.babyWeekSummary,
                    growthLengthCM: previous.growthLengthCM,
                    growthWeightG: previous.growthWeightG,
                    growthAnalogy: previous.growthAnalogy,
                    momWeekSummary: previous.momWeekSummary
                )
            }
        }
        return finalMap
    }

    private func fillDailyGaps(_ entries: [Int: DailyWarmCopyEntry]) -> [Int: DailyWarmCopyEntry] {
        var finalMap: [Int: DailyWarmCopyEntry] = [:]
        finalMap.reserveCapacity(280)
        var previous = fallbackDailyEntry(for: 1)
        for day in 1...280 {
            if let current = entries[day] {
                previous = current
                finalMap[day] = current
            } else {
                finalMap[day] = DailyWarmCopyEntry(
                    dayIndex: day,
                    weekText: previous.weekText,
                    babyChange: previous.babyChange,
                    momChange: previous.momChange
                )
            }
        }
        return finalMap
    }

    private func resourceURL(forResource name: String) -> URL? {
        if let direct = Bundle.main.url(forResource: name, withExtension: "json") {
            return direct
        }
        return Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources")
    }

    private func fallbackDailyCatalog() -> [Int: DailyWarmCopyEntry] {
        var result: [Int: DailyWarmCopyEntry] = [:]
        result.reserveCapacity(280)
        for day in 1...280 {
            result[day] = fallbackDailyEntry(for: day)
        }
        return result
    }

    private func fallbackWeeklyCatalog() -> [Int: WeeklyWarmGuideEntry] {
        var result: [Int: WeeklyWarmGuideEntry] = [:]
        result.reserveCapacity(41)
        for week in 0...40 {
            result[week] = fallbackWeeklyEntry(for: week)
        }
        return result
    }

    private func fallbackDailyEntry(for day: Int) -> DailyWarmCopyEntry {
        DailyWarmCopyEntry(
            dayIndex: day,
            weekText: "孕\(day / 7)周+\(day % 7)天",
            babyChange: "今天宝宝还在稳稳发育，你按节奏吃好睡好，就是最有力的支持。",
            momChange: "今天也请对自己温柔一点，按时休息、按时补水，不舒服时及时联系医生。"
        )
    }

    private func fallbackWeeklyEntry(for week: Int) -> WeeklyWarmGuideEntry {
        WeeklyWarmGuideEntry(
            week: week,
            babyWeekSummary: "这周宝宝还在按自己的节奏慢慢长大，每一天都在朝着更成熟迈进。",
            growthLengthCM: "约值会因个体差异而变化",
            growthWeightG: "约值会因个体差异而变化",
            growthAnalogy: "发育速度各有不同",
            momWeekSummary: "你已经很努力了，这周继续规律作息、稳定饮食，有持续不适就及时联系医生。"
        )
    }
}
