import Foundation

struct HabitWidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var habits: [HabitWidgetItem]

    static let empty = HabitWidgetSnapshot(generatedAt: .distantPast, habits: [])
}

struct HabitWidgetItem: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var completionCount: Int
    var timesToComplete: Int
    var streakDays: Int
    var frequencyRawValue: String?
    var customIntervalValue: Int?
    var customIntervalUnitRawValue: String?
    var startDate: Date?
    var completions: [HabitWidgetCompletion]

    var isCompleted: Bool {
        completionCount >= timesToComplete
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case completionCount
        case timesToComplete
        case streakDays
        case frequencyRawValue
        case customIntervalValue
        case customIntervalUnitRawValue
        case startDate
        case completions
    }

    init(
        id: UUID,
        name: String,
        completionCount: Int,
        timesToComplete: Int,
        streakDays: Int,
        frequencyRawValue: String? = nil,
        customIntervalValue: Int? = nil,
        customIntervalUnitRawValue: String? = nil,
        startDate: Date? = nil,
        completions: [HabitWidgetCompletion] = []
    ) {
        self.id = id
        self.name = name
        self.completionCount = completionCount
        self.timesToComplete = timesToComplete
        self.streakDays = streakDays
        self.frequencyRawValue = frequencyRawValue
        self.customIntervalValue = customIntervalValue
        self.customIntervalUnitRawValue = customIntervalUnitRawValue
        self.startDate = startDate
        self.completions = completions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        completionCount = try container.decode(Int.self, forKey: .completionCount)
        timesToComplete = try container.decode(Int.self, forKey: .timesToComplete)
        streakDays = try container.decode(Int.self, forKey: .streakDays)
        frequencyRawValue = try container.decodeIfPresent(String.self, forKey: .frequencyRawValue)
        customIntervalValue = try container.decodeIfPresent(Int.self, forKey: .customIntervalValue)
        customIntervalUnitRawValue = try container.decodeIfPresent(String.self, forKey: .customIntervalUnitRawValue)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        completions = try container.decodeIfPresent([HabitWidgetCompletion].self, forKey: .completions) ?? []
    }

    var hasScheduleData: Bool {
        frequencyRawValue != nil && startDate != nil
    }

    func completionCount(on date: Date) -> Int {
        guard hasScheduleData else { return completionCount }
        guard isScheduled(on: date) else { return 0 }

        let periodStart = HabitSchedule.periodStart(
            for: date,
            frequencyRawValue: frequencyRawValue,
            customValue: customIntervalValue,
            customUnitRawValue: customIntervalUnitRawValue,
            habitStart: startDate
        )
        let periodEnd = HabitSchedule.periodEnd(
            for: periodStart,
            frequencyRawValue: frequencyRawValue,
            customValue: customIntervalValue,
            customUnitRawValue: customIntervalUnitRawValue
        )

        return completions
            .filter { $0.date >= periodStart && $0.date < periodEnd }
            .reduce(0) { $0 + $1.count }
    }

    func isCompleted(on date: Date) -> Bool {
        guard isScheduled(on: date) else { return false }
        return completionCount(on: date) >= timesToComplete
    }

    func isScheduled(on date: Date) -> Bool {
        guard hasScheduleData, let startDate else { return true }

        return HabitSchedule.isScheduled(
            on: date,
            frequencyRawValue: frequencyRawValue,
            customValue: customIntervalValue,
            customUnitRawValue: customIntervalUnitRawValue,
            habitStart: startDate
        )
    }

    func streakDays(endingAt date: Date) -> Int {
        guard hasScheduleData, let startDate else { return streakDays }

        let calendar = Calendar.current
        let habitStart = calendar.startOfDay(for: startDate)
        var streak = 0
        var cursor = date

        while cursor >= habitStart && streak < 366 {
            if isScheduled(on: cursor) {
                guard completionCount(on: cursor) >= timesToComplete else { break }
                streak += 1
            }
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }
}

struct HabitWidgetCompletion: Codable, Equatable, Hashable {
    var date: Date
    var count: Int
}

enum HabitWidgetDataStore {
    static let appGroupIdentifier = "group.com.albertc.habits"

    private static let fileName = "habit-widget-snapshot.json"

    static func loadSnapshot() -> HabitWidgetSnapshot {
        guard let url = try? snapshotURL(), let data = try? Data(contentsOf: url) else {
            return .empty
        }

        return (try? JSONDecoder().decode(HabitWidgetSnapshot.self, from: data)) ?? .empty
    }

    static func saveSnapshot(_ snapshot: HabitWidgetSnapshot) throws {
        let url = try snapshotURL()
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    private static func snapshotURL() throws -> URL {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw HabitWidgetDataStoreError.appGroupUnavailable
        }

        try? fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        return containerURL.appendingPathComponent(fileName)
    }
}

enum HabitWidgetDataStoreError: Error {
    case appGroupUnavailable
}
