import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum BackupImportMode {
    case merge
    case replace
}

struct BackupSummary: Equatable {
    var habitCount: Int
    var completionCount: Int
    var thingCount: Int

    var isEmpty: Bool {
        habitCount == 0 && completionCount == 0 && thingCount == 0
    }
}

struct BackupImportResult: Equatable {
    var summary: BackupSummary
    var disabledReminderCount: Int
}

struct BackupImportPreview: Identifiable {
    let id = UUID()
    let backup: HabitsBackup

    var summary: BackupSummary {
        backup.summary
    }
}

enum BackupServiceError: LocalizedError, Equatable {
    case unreadableFile
    case invalidFormat
    case unsupportedVersion(Int)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "The selected file could not be read."
        case .invalidFormat:
            return "This is not a valid Habits backup file."
        case .unsupportedVersion(let version):
            return "This backup uses schema version \(version), which this app cannot import."
        case .validationFailed(let message):
            return message
        }
    }
}

struct HabitsBackup: Codable, Equatable {
    static let format = "com.albertc.habits.backup"
    static let supportedSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var exportedAt: Date
    var appVersion: String?
    var appBuild: String?
    var habits: [BackupHabit]
    var things: [BackupThing]

    var summary: BackupSummary {
        BackupSummary(
            habitCount: habits.count,
            completionCount: habits.reduce(0) { $0 + $1.completions.count },
            thingCount: things.count
        )
    }
}

struct BackupHabit: Codable, Equatable {
    var id: UUID
    var name: String
    var frequency: String
    var customIntervalValue: Int?
    var customIntervalUnit: String?
    var timesToComplete: Int
    var startDate: Date
    var notificationsEnabled: Bool
    var notificationHour: Int?
    var notificationMinute: Int?
    var createdAt: Date
    var completions: [BackupCompletion]
}

struct BackupCompletion: Codable, Equatable {
    var id: UUID
    var date: Date
    var count: Int
}

struct BackupThing: Codable, Equatable {
    var id: UUID
    var title: String
    var dueDate: Date
    var isCompleted: Bool
    var completedAt: Date?
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BackupServiceError.unreadableFile
        }

        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupService {
    static func makeExportFileName(date: Date = .now, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "Habits Backup %04d-%02d-%02d.json", year, month, day)
    }

    @MainActor
    static func makeExportData(context: ModelContext, exportedAt: Date = .now) throws -> Data {
        try encode(makeBackup(context: context, exportedAt: exportedAt))
    }

    @MainActor
    static func makeBackup(context: ModelContext, exportedAt: Date = .now) throws -> HabitsBackup {
        let habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.name)]))
            .filter { $0.syncDeletedAt == nil }
        let things = try context.fetch(
            FetchDescriptor<Thing>(
                sortBy: [
                    SortDescriptor(\.dueDate),
                    SortDescriptor(\.title)
                ]
            )
        )
        .filter { $0.syncDeletedAt == nil }

        return HabitsBackup(
            format: HabitsBackup.format,
            schemaVersion: HabitsBackup.supportedSchemaVersion,
            exportedAt: exportedAt,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            habits: habits.map(BackupHabit.init),
            things: things.map(BackupThing.init)
        )
    }

    @MainActor
    static func localDataSummary(context: ModelContext) throws -> BackupSummary {
        let habits = try context.fetch(FetchDescriptor<Habit>())
            .filter { $0.syncDeletedAt == nil }
        let completions = try context.fetch(FetchDescriptor<HabitCompletion>())
            .filter { $0.syncDeletedAt == nil && $0.habit?.syncDeletedAt == nil }
        let things = try context.fetch(FetchDescriptor<Thing>())
            .filter { $0.syncDeletedAt == nil }

        return BackupSummary(
            habitCount: habits.count,
            completionCount: completions.count,
            thingCount: things.count
        )
    }

    static func decodePreview(from data: Data) throws -> BackupImportPreview {
        let backup = try decode(data)
        try validate(backup)
        return BackupImportPreview(backup: backup)
    }

    static func readBackupFile(at url: URL) throws -> BackupImportPreview {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            throw BackupServiceError.unreadableFile
        }

        return try decodePreview(from: data)
    }

    @MainActor
    static func importBackup(
        _ backup: HabitsBackup,
        mode: BackupImportMode,
        context: ModelContext,
        schedulesNotifications: Bool = true
    ) async throws -> BackupImportResult {
        try validate(backup)

        let now = Date.now
        let existingHabits = try context.fetch(FetchDescriptor<Habit>())
        let existingThings = try context.fetch(FetchDescriptor<Thing>())

        if mode == .replace {
            for habit in existingHabits {
                NotificationService.removeNotification(for: habit)
                markDirty(habit, at: now, deletedAt: now)
                for completion in habit.completions where completion.syncDeletedAt == nil {
                    completion.count = 0
                    markDirty(completion, at: now, deletedAt: now)
                }
            }

            for thing in existingThings {
                markDirty(thing, at: now, deletedAt: now)
            }

            for habitRecord in backup.habits {
                if let habit = existingHabits.first(where: { $0.id == habitRecord.id }) {
                    apply(habitRecord, to: habit)
                    markDirty(habit, at: now, deletedAt: nil)
                    try mergeCompletions(habitRecord.completions, into: habit, context: context, updatedAt: now)
                } else {
                    let habit = makeHabit(from: habitRecord, syncUpdatedAt: now)
                    context.insert(habit)
                }
            }

            for thingRecord in backup.things {
                if let thing = existingThings.first(where: { $0.id == thingRecord.id }) {
                    apply(thingRecord, to: thing)
                    markDirty(thing, at: now, deletedAt: nil)
                } else {
                    context.insert(makeThing(from: thingRecord, syncUpdatedAt: now))
                }
            }
        } else {
            var habitsByID = Dictionary(uniqueKeysWithValues: existingHabits.map { ($0.id, $0) })
            var thingsByID = Dictionary(uniqueKeysWithValues: existingThings.map { ($0.id, $0) })

            for habitRecord in backup.habits {
                if let habit = habitsByID[habitRecord.id] {
                    apply(habitRecord, to: habit)
                    markDirty(habit, at: now, deletedAt: nil)
                    try mergeCompletions(habitRecord.completions, into: habit, context: context, updatedAt: now)
                } else {
                    let habit = makeHabit(from: habitRecord, syncUpdatedAt: now)
                    context.insert(habit)
                    habitsByID[habit.id] = habit
                }
            }

            for thingRecord in backup.things {
                if let thing = thingsByID[thingRecord.id] {
                    apply(thingRecord, to: thing)
                    markDirty(thing, at: now, deletedAt: nil)
                } else {
                    let thing = makeThing(from: thingRecord, syncUpdatedAt: now)
                    context.insert(thing)
                    thingsByID[thing.id] = thing
                }
            }
        }

        try context.save()

        let importedHabits = try context.fetch(FetchDescriptor<Habit>())
            .filter { backup.habits.map(\.id).contains($0.id) }
        let disabledReminderCount = await reconcileNotifications(
            for: importedHabits,
            schedulesNotifications: schedulesNotifications
        )

        if disabledReminderCount > 0 {
            try context.save()
        }

        HabitWidgetSyncService.sync(context: context)
        ThingWidgetSyncService.sync(context: context)

        return BackupImportResult(
            summary: backup.summary,
            disabledReminderCount: disabledReminderCount
        )
    }

    @MainActor
    static func deleteAllLocalData(context: ModelContext) throws {
        NotificationService.removeAllNotifications()

        let completions = try context.fetch(FetchDescriptor<HabitCompletion>())
        for completion in completions {
            context.delete(completion)
        }
        try context.save()

        try context.delete(model: Habit.self)
        try context.delete(model: Thing.self)
        try context.save()

        HabitWidgetSyncService.sync(context: context)
        ThingWidgetSyncService.sync(context: context)
    }

    private static func encode(_ backup: HabitsBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    private static func decode(_ data: Data) throws -> HabitsBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(HabitsBackup.self, from: data)
        } catch {
            throw BackupServiceError.invalidFormat
        }
    }

    private static func validate(_ backup: HabitsBackup) throws {
        guard backup.format == HabitsBackup.format else {
            throw BackupServiceError.invalidFormat
        }

        guard backup.schemaVersion == HabitsBackup.supportedSchemaVersion else {
            throw BackupServiceError.unsupportedVersion(backup.schemaVersion)
        }

        var habitIDs = Set<UUID>()
        var completionIDs = Set<UUID>()
        var thingIDs = Set<UUID>()

        for habit in backup.habits {
            guard habitIDs.insert(habit.id).inserted else {
                throw BackupServiceError.validationFailed("The backup contains duplicate habit IDs.")
            }

            guard !habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  habit.name.count <= Habit.maxNameLength else {
                throw BackupServiceError.validationFailed("The backup contains a habit with an invalid name.")
            }

            guard let frequency = HabitFrequency(rawValue: habit.frequency) else {
                throw BackupServiceError.validationFailed("The backup contains a habit with an unknown frequency.")
            }

            if frequency == .custom {
                guard let customValue = habit.customIntervalValue,
                      (1...Habit.maxCustomIntervalValue).contains(customValue),
                      let customUnitRawValue = habit.customIntervalUnit,
                      CustomIntervalUnit(rawValue: customUnitRawValue) != nil else {
                    throw BackupServiceError.validationFailed("The backup contains a habit with an invalid custom interval.")
                }
            }

            guard (1...Habit.maxTimesToComplete).contains(habit.timesToComplete) else {
                throw BackupServiceError.validationFailed("The backup contains a habit with an invalid goal.")
            }

            if let notificationHour = habit.notificationHour,
               !(0...23).contains(notificationHour) {
                throw BackupServiceError.validationFailed("The backup contains a habit with an invalid reminder hour.")
            }

            if let notificationMinute = habit.notificationMinute,
               !(0...59).contains(notificationMinute) {
                throw BackupServiceError.validationFailed("The backup contains a habit with an invalid reminder minute.")
            }

            var completionPeriodKeys = Set<String>()
            for completion in habit.completions {
                guard completion.count > 0 else {
                    throw BackupServiceError.validationFailed("The backup contains a completion with an invalid count.")
                }

                let periodStart = DateHelpers.periodStart(
                    for: completion.date,
                    frequency: frequency,
                    customValue: habit.customIntervalValue,
                    customUnit: habit.customIntervalUnit.flatMap(CustomIntervalUnit.init(rawValue:)),
                    habitStart: habit.startDate
                )
                let completionID = HabitCompletion.deterministicID(habitID: habit.id, periodStart: periodStart)
                guard completionIDs.insert(completionID).inserted,
                      completionPeriodKeys.insert(String(Int64(periodStart.timeIntervalSinceReferenceDate.rounded()))).inserted else {
                    throw BackupServiceError.validationFailed("The backup contains duplicate completion periods.")
                }
            }
        }

        for thing in backup.things {
            guard thingIDs.insert(thing.id).inserted else {
                throw BackupServiceError.validationFailed("The backup contains duplicate thing IDs.")
            }

            guard !thing.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  thing.title.count <= Thing.maxTitleLength else {
                throw BackupServiceError.validationFailed("The backup contains a thing with an invalid title.")
            }

            guard thing.isCompleted == (thing.completedAt != nil) else {
                throw BackupServiceError.validationFailed("The backup contains a thing with an invalid completion state.")
            }
        }
    }

    private static func makeHabit(from record: BackupHabit, syncUpdatedAt: Date = .now) -> Habit {
        let habit = Habit(
            id: record.id,
            name: record.name.trimmingCharacters(in: .whitespacesAndNewlines),
            frequency: HabitFrequency(rawValue: record.frequency) ?? .daily,
            customIntervalValue: record.customIntervalValue,
            customIntervalUnit: record.customIntervalUnit.flatMap(CustomIntervalUnit.init(rawValue:)),
            timesToComplete: record.timesToComplete,
            startDate: record.startDate,
            notificationsEnabled: record.notificationsEnabled,
            notificationHour: record.notificationHour,
            notificationMinute: record.notificationMinute,
            createdAt: record.createdAt,
            syncUpdatedAt: syncUpdatedAt,
            syncDeletedAt: nil,
            syncRemoteUpdatedAt: nil,
            syncNeedsPush: true
        )
        habit.completions = record.completions.map { makeCompletion(from: $0, habit: habit, syncUpdatedAt: syncUpdatedAt) }
        return habit
    }

    private static func makeCompletion(from record: BackupCompletion, habit: Habit, syncUpdatedAt: Date = .now) -> HabitCompletion {
        let periodStart = HabitCompletion.periodStart(for: record.date, habit: habit)
        return HabitCompletion(
            id: HabitCompletion.deterministicID(habitID: habit.id, periodStart: periodStart),
            date: record.date,
            periodStart: periodStart,
            count: record.count,
            habit: habit,
            syncUpdatedAt: syncUpdatedAt,
            syncDeletedAt: nil,
            syncRemoteUpdatedAt: nil,
            syncNeedsPush: true
        )
    }

    private static func makeThing(from record: BackupThing, syncUpdatedAt: Date = .now) -> Thing {
        Thing(
            id: record.id,
            title: record.title.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: record.dueDate,
            isCompleted: record.isCompleted,
            completedAt: record.completedAt,
            syncUpdatedAt: syncUpdatedAt,
            syncDeletedAt: nil,
            syncRemoteUpdatedAt: nil,
            syncNeedsPush: true
        )
    }

    private static func apply(_ record: BackupHabit, to habit: Habit) {
        habit.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.frequency = HabitFrequency(rawValue: record.frequency) ?? .daily
        habit.customIntervalValue = record.customIntervalValue
        habit.customIntervalUnit = record.customIntervalUnit.flatMap(CustomIntervalUnit.init(rawValue:))
        habit.timesToComplete = record.timesToComplete
        habit.startDate = record.startDate
        habit.notificationsEnabled = record.notificationsEnabled
        habit.notificationHour = record.notificationHour
        habit.notificationMinute = record.notificationMinute
        habit.createdAt = record.createdAt
        habit.syncDeletedAt = nil
    }

    private static func apply(_ record: BackupThing, to thing: Thing) {
        thing.title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        thing.dueDate = Calendar.current.startOfDay(for: record.dueDate)
        thing.isCompleted = record.isCompleted
        thing.completedAt = record.completedAt
        thing.syncDeletedAt = nil
    }

    private static func mergeCompletions(
        _ records: [BackupCompletion],
        into habit: Habit,
        context: ModelContext,
        updatedAt: Date = .now
    ) throws {
        let recordIDs = Set(records.map(\.id))
        let fetchedCompletions = try context.fetch(FetchDescriptor<HabitCompletion>())
            .filter { completion in
                if completion.habit?.id == habit.id { return true }
                if recordIDs.contains(completion.id) { return true }

                let periodStart = completion.periodStart ?? HabitCompletion.periodStart(for: completion.date, habit: habit)
                return completion.id == HabitCompletion.deterministicID(habitID: habit.id, periodStart: periodStart)
            }
        let knownCompletions = Array(Set(habit.completions.map(\.id) + fetchedCompletions.map(\.id))).compactMap { id in
            (habit.completions + fetchedCompletions).first { $0.id == id }
        }
        var completionsByID = Dictionary(uniqueKeysWithValues: knownCompletions.map { ($0.id, $0) })
        var completionsByPeriod: [String: HabitCompletion] = [:]
        for completion in knownCompletions {
            let periodStart = completion.periodStart ?? HabitCompletion.periodStart(for: completion.date, habit: habit)
            completionsByPeriod[periodKey(periodStart), default: completion] = completion
        }

        for record in records {
            let periodStart = HabitCompletion.periodStart(for: record.date, habit: habit)
            let key = periodKey(periodStart)
            if let completion = completionsByID[record.id] ?? completionsByPeriod[key] {
                completion.id = HabitCompletion.deterministicID(habitID: habit.id, periodStart: periodStart)
                completion.date = record.date
                completion.periodStart = periodStart
                completion.count = record.count
                completion.habit = habit
                markDirty(completion, at: updatedAt, deletedAt: nil)
            } else {
                let completion = makeCompletion(from: record, habit: habit, syncUpdatedAt: updatedAt)
                context.insert(completion)
                completionsByID[completion.id] = completion
                completionsByPeriod[key] = completion
            }
        }
    }

    private static func periodKey(_ periodStart: Date) -> String {
        String(Int64(periodStart.timeIntervalSinceReferenceDate.rounded()))
    }

    private static func markDirty(_ habit: Habit, at date: Date, deletedAt: Date?) {
        habit.syncUpdatedAt = date
        habit.syncDeletedAt = deletedAt
        habit.syncNeedsPush = true
    }

    private static func markDirty(_ completion: HabitCompletion, at date: Date, deletedAt: Date?) {
        completion.syncUpdatedAt = date
        completion.syncDeletedAt = deletedAt
        completion.syncNeedsPush = true
    }

    private static func markDirty(_ thing: Thing, at date: Date, deletedAt: Date?) {
        thing.syncUpdatedAt = date
        thing.syncDeletedAt = deletedAt
        thing.syncNeedsPush = true
    }

    @MainActor
    private static func reconcileNotifications(
        for habits: [Habit],
        schedulesNotifications: Bool
    ) async -> Int {
        var disabledReminderCount = 0

        for habit in habits {
            NotificationService.removeNotification(for: habit)

            guard habit.notificationsEnabled else { continue }
            guard schedulesNotifications else { continue }

            let didSchedule = await NotificationService.scheduleNotification(for: habit)
            if !didSchedule {
                habit.notificationsEnabled = false
                habit.syncUpdatedAt = .now
                habit.syncNeedsPush = true
                disabledReminderCount += 1
            }
        }

        return disabledReminderCount
    }
}

extension BackupHabit {
    init(habit: Habit) {
        id = habit.id
        name = habit.name
        frequency = habit.frequency.rawValue
        customIntervalValue = habit.customIntervalValue
        customIntervalUnit = habit.customIntervalUnit?.rawValue
        timesToComplete = habit.timesToComplete
        startDate = habit.startDate
        notificationsEnabled = habit.notificationsEnabled
        notificationHour = habit.notificationHour
        notificationMinute = habit.notificationMinute
        createdAt = habit.createdAt
        completions = habit.completions
            .filter { $0.syncDeletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date < rhs.date
                }

                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(BackupCompletion.init)
    }
}

extension BackupCompletion {
    init(completion: HabitCompletion) {
        id = completion.id
        date = completion.date
        count = completion.count
    }
}

extension BackupThing {
    init(thing: Thing) {
        id = thing.id
        title = thing.title
        dueDate = thing.dueDate
        isCompleted = thing.isCompleted
        completedAt = thing.completedAt
    }
}
