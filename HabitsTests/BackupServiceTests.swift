import Foundation
import SwiftData
import Testing
@testable import Habits

@Suite("BackupService")
struct BackupServiceTests {
    @Test("Export includes habits, completions, things, and reminder fields")
    @MainActor
    func exportIncludesAllLocalData() throws {
        let context = try makeContext()
        let habit = Habit(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Read",
            frequency: .custom,
            customIntervalValue: 2,
            customIntervalUnit: .days,
            timesToComplete: 3,
            startDate: makeDate(2026, 4, 1),
            notificationsEnabled: true,
            notificationHour: 20,
            notificationMinute: 15,
            createdAt: makeDate(2026, 3, 1)
        )
        context.insert(habit)
        context.insert(
            HabitCompletion(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                date: makeDate(2026, 4, 28, hour: 9),
                count: 2,
                habit: habit
            )
        )
        context.insert(
            Thing(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                title: "Buy milk",
                dueDate: makeDate(2026, 4, 29),
                isCompleted: true,
                completedAt: makeDate(2026, 4, 29, hour: 11)
            )
        )
        try context.save()

        let data = try BackupService.makeExportData(context: context, exportedAt: makeDate(2026, 4, 30))
        let preview = try BackupService.decodePreview(from: data)

        #expect(preview.summary == BackupSummary(habitCount: 1, completionCount: 1, thingCount: 1))
        let exportedHabit = try #require(preview.backup.habits.first)
        #expect(exportedHabit.id == habit.id)
        #expect(exportedHabit.frequency == HabitFrequency.custom.rawValue)
        #expect(exportedHabit.customIntervalValue == 2)
        #expect(exportedHabit.customIntervalUnit == CustomIntervalUnit.days.rawValue)
        #expect(exportedHabit.notificationsEnabled)
        #expect(exportedHabit.notificationHour == 20)
        #expect(exportedHabit.notificationMinute == 15)
        #expect(exportedHabit.completions.first?.count == 2)
        #expect(preview.backup.things.first?.title == "Buy milk")
    }

    @Test("Merge upserts matching records and keeps unrelated local records")
    @MainActor
    func mergeUpsertsByID() async throws {
        let context = try makeContext()
        let habitID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let completionID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let thingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let localHabit = Habit(id: habitID, name: "Old", timesToComplete: 1)
        let localThing = Thing(id: thingID, title: "Old thing")
        context.insert(localHabit)
        context.insert(HabitCompletion(id: completionID, date: makeDate(2026, 4, 28), count: 1, habit: localHabit))
        context.insert(Habit(name: "Local only"))
        context.insert(localThing)
        try context.save()

        let backup = HabitsBackup(
            format: HabitsBackup.format,
            schemaVersion: HabitsBackup.supportedSchemaVersion,
            exportedAt: makeDate(2026, 4, 30),
            appVersion: nil,
            appBuild: nil,
            habits: [
                BackupHabit(
                    id: habitID,
                    name: "Updated",
                    frequency: HabitFrequency.weekly.rawValue,
                    customIntervalValue: nil,
                    customIntervalUnit: nil,
                    timesToComplete: 4,
                    startDate: makeDate(2026, 4, 1),
                    notificationsEnabled: false,
                    notificationHour: nil,
                    notificationMinute: nil,
                    createdAt: makeDate(2026, 3, 1),
                    completions: [
                        BackupCompletion(id: completionID, date: makeDate(2026, 4, 28, hour: 12), count: 3)
                    ]
                )
            ],
            things: [
                BackupThing(
                    id: thingID,
                    title: "Updated thing",
                    dueDate: makeDate(2026, 5, 1),
                    isCompleted: false,
                    completedAt: nil
                )
            ]
        )

        let result = try await BackupService.importBackup(
            backup,
            mode: .merge,
            context: context,
            schedulesNotifications: false
        )

        let habits = try context.fetch(FetchDescriptor<Habit>())
        let updatedHabit = try #require(habits.first { $0.id == habitID })
        #expect(result.summary == BackupSummary(habitCount: 1, completionCount: 1, thingCount: 1))
        #expect(habits.count == 2)
        #expect(updatedHabit.name == "Updated")
        #expect(updatedHabit.frequency == .weekly)
        #expect(updatedHabit.timesToComplete == 4)
        #expect(updatedHabit.completions.count == 1)
        #expect(updatedHabit.completions.first?.date == makeDate(2026, 4, 28, hour: 12))
        #expect(updatedHabit.completions.first?.count == 3)

        let updatedThing = try #require(try context.fetch(FetchDescriptor<Thing>()).first { $0.id == thingID })
        #expect(updatedThing.title == "Updated thing")
        #expect(updatedThing.dueDate == makeDate(2026, 5, 1))
    }

    @Test("Replace removes local-only data before restoring backup")
    @MainActor
    func replaceRestoresOnlyBackupData() async throws {
        let context = try makeContext()
        context.insert(Habit(name: "Local only"))
        context.insert(Thing(title: "Local thing"))
        try context.save()

        let habitID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let thingID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let backup = HabitsBackup(
            format: HabitsBackup.format,
            schemaVersion: HabitsBackup.supportedSchemaVersion,
            exportedAt: makeDate(2026, 4, 30),
            appVersion: nil,
            appBuild: nil,
            habits: [
                BackupHabit(
                    id: habitID,
                    name: "Imported",
                    frequency: HabitFrequency.daily.rawValue,
                    customIntervalValue: nil,
                    customIntervalUnit: nil,
                    timesToComplete: 1,
                    startDate: makeDate(2026, 4, 1),
                    notificationsEnabled: false,
                    notificationHour: nil,
                    notificationMinute: nil,
                    createdAt: makeDate(2026, 4, 1),
                    completions: []
                )
            ],
            things: [
                BackupThing(
                    id: thingID,
                    title: "Imported thing",
                    dueDate: makeDate(2026, 5, 2),
                    isCompleted: false,
                    completedAt: nil
                )
            ]
        )

        _ = try await BackupService.importBackup(
            backup,
            mode: .replace,
            context: context,
            schedulesNotifications: false
        )

        let habits = try context.fetch(FetchDescriptor<Habit>()).filter { $0.syncDeletedAt == nil }
        let things = try context.fetch(FetchDescriptor<Thing>()).filter { $0.syncDeletedAt == nil }
        #expect(habits.map(\.id) == [habitID])
        #expect(habits.map(\.name) == ["Imported"])
        #expect(things.map(\.id) == [thingID])
        #expect(things.map(\.title) == ["Imported thing"])
        #expect(try context.fetch(FetchDescriptor<Habit>()).contains { $0.name == "Local only" && $0.syncDeletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<Thing>()).contains { $0.title == "Local thing" && $0.syncDeletedAt != nil })
    }

    @Test("Invalid backup fails before mutating existing data")
    @MainActor
    func invalidBackupDoesNotMutate() async throws {
        let context = try makeContext()
        let original = Habit(name: "Original")
        context.insert(original)
        try context.save()

        let invalidBackup = HabitsBackup(
            format: HabitsBackup.format,
            schemaVersion: HabitsBackup.supportedSchemaVersion,
            exportedAt: makeDate(2026, 4, 30),
            appVersion: nil,
            appBuild: nil,
            habits: [
                BackupHabit(
                    id: original.id,
                    name: "",
                    frequency: HabitFrequency.daily.rawValue,
                    customIntervalValue: nil,
                    customIntervalUnit: nil,
                    timesToComplete: 1,
                    startDate: makeDate(2026, 4, 1),
                    notificationsEnabled: false,
                    notificationHour: nil,
                    notificationMinute: nil,
                    createdAt: makeDate(2026, 4, 1),
                    completions: []
                )
            ],
            things: []
        )

        do {
            _ = try await BackupService.importBackup(
                invalidBackup,
                mode: .merge,
                context: context,
                schedulesNotifications: false
            )
            Issue.record("Invalid backup import unexpectedly succeeded.")
        } catch let error as BackupServiceError {
            #expect(error == .validationFailed("The backup contains a habit with an invalid name."))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let habits = try context.fetch(FetchDescriptor<Habit>())
        #expect(habits.count == 1)
        #expect(habits.first?.name == "Original")
    }

    @Test("Delete all local data physically removes habits completions and things")
    @MainActor
    func deleteAllLocalDataRemovesRecords() throws {
        let context = try makeContext()
        let habit = Habit(name: "Read", notificationsEnabled: true)
        context.insert(habit)
        context.insert(HabitCompletion(date: makeDate(2026, 4, 28), count: 1, habit: habit))
        context.insert(Thing(title: "Buy milk"))
        try context.save()

        try BackupService.deleteAllLocalData(context: context)

        #expect(try context.fetch(FetchDescriptor<Habit>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<HabitCompletion>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Thing>()).isEmpty)
    }

    @Test("Local data summary counts only visible records")
    @MainActor
    func localDataSummaryCountsOnlyVisibleRecords() throws {
        let context = try makeContext()
        let visibleHabit = Habit(name: "Read")
        let deletedHabit = Habit(name: "Deleted", syncDeletedAt: makeDate(2026, 4, 28))
        context.insert(visibleHabit)
        context.insert(deletedHabit)
        context.insert(HabitCompletion(date: makeDate(2026, 4, 28), count: 1, habit: visibleHabit))
        context.insert(HabitCompletion(date: makeDate(2026, 4, 29), count: 1, habit: deletedHabit))
        context.insert(Thing(title: "Buy milk"))
        context.insert(Thing(title: "Deleted thing", syncDeletedAt: makeDate(2026, 4, 28)))
        try context.save()

        let summary = try BackupService.localDataSummary(context: context)

        #expect(summary == BackupSummary(habitCount: 1, completionCount: 1, thingCount: 1))
    }

    @Test("Duplicate completion periods are rejected")
    func duplicateCompletionPeriodsAreRejected() throws {
        let completionID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let duplicateCompletionID = UUID(uuidString: "66666666-6666-6666-6666-666666666667")!
        let backup = HabitsBackup(
            format: HabitsBackup.format,
            schemaVersion: HabitsBackup.supportedSchemaVersion,
            exportedAt: makeDate(2026, 4, 30),
            appVersion: nil,
            appBuild: nil,
            habits: [
                BackupHabit(
                    id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    name: "Habit",
                    frequency: HabitFrequency.daily.rawValue,
                    customIntervalValue: nil,
                    customIntervalUnit: nil,
                    timesToComplete: 1,
                    startDate: makeDate(2026, 4, 1),
                    notificationsEnabled: false,
                    notificationHour: nil,
                    notificationMinute: nil,
                    createdAt: makeDate(2026, 4, 1),
                    completions: [
                        BackupCompletion(id: completionID, date: makeDate(2026, 4, 1), count: 1),
                        BackupCompletion(id: duplicateCompletionID, date: makeDate(2026, 4, 1, hour: 12), count: 1)
                    ]
                )
            ],
            things: []
        )
        let data = try JSONEncoder.habitsBackupEncoder.encode(backup)

        do {
            _ = try BackupService.decodePreview(from: data)
            Issue.record("Duplicate completion periods were unexpectedly accepted.")
        } catch let error as BackupServiceError {
            #expect(error == .validationFailed("The backup contains duplicate completion periods."))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Import merges completions by period with deterministic sync ID")
    @MainActor
    func importMergesCompletionsByPeriod() async throws {
        let context = try makeContext()
        let habitID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let habit = Habit(id: habitID, name: "Read")
        let periodStart = HabitCompletion.periodStart(for: makeDate(2026, 4, 28), habit: habit)
        let existing = HabitCompletion(
            id: UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!,
            date: makeDate(2026, 4, 28, hour: 8),
            periodStart: periodStart,
            count: 1,
            habit: habit
        )
        context.insert(habit)
        context.insert(existing)
        try context.save()

        let backup = HabitsBackup(
            format: HabitsBackup.format,
            schemaVersion: HabitsBackup.supportedSchemaVersion,
            exportedAt: makeDate(2026, 4, 30),
            appVersion: nil,
            appBuild: nil,
            habits: [
                BackupHabit(
                    id: habitID,
                    name: "Read",
                    frequency: HabitFrequency.daily.rawValue,
                    customIntervalValue: nil,
                    customIntervalUnit: nil,
                    timesToComplete: 1,
                    startDate: makeDate(2026, 4, 1),
                    notificationsEnabled: false,
                    notificationHour: nil,
                    notificationMinute: nil,
                    createdAt: makeDate(2026, 4, 1),
                    completions: [
                        BackupCompletion(
                            id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
                            date: makeDate(2026, 4, 28, hour: 18),
                            count: 3
                        )
                    ]
                )
            ],
            things: []
        )

        _ = try await BackupService.importBackup(
            backup,
            mode: .merge,
            context: context,
            schedulesNotifications: false
        )

        let completions = try context.fetch(FetchDescriptor<HabitCompletion>())
        #expect(completions.count == 1)
        #expect(completions.first?.id == HabitCompletion.deterministicID(habitID: habitID, periodStart: periodStart))
        #expect(completions.first?.count == 3)
    }

    @Test("Duplicate thing IDs are rejected")
    func duplicateThingIDsAreRejected() throws {
        let thingID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let backup = HabitsBackup(
            format: HabitsBackup.format,
            schemaVersion: HabitsBackup.supportedSchemaVersion,
            exportedAt: makeDate(2026, 4, 30),
            appVersion: nil,
            appBuild: nil,
            habits: [],
            things: [
                BackupThing(
                    id: thingID,
                    title: "First",
                    dueDate: makeDate(2026, 5, 1),
                    isCompleted: false,
                    completedAt: nil
                ),
                BackupThing(
                    id: thingID,
                    title: "Second",
                    dueDate: makeDate(2026, 5, 2),
                    isCompleted: false,
                    completedAt: nil
                )
            ]
        )
        let data = try JSONEncoder.habitsBackupEncoder.encode(backup)

        do {
            _ = try BackupService.decodePreview(from: data)
            Issue.record("Duplicate thing IDs were unexpectedly accepted.")
        } catch let error as BackupServiceError {
            #expect(error == .validationFailed("The backup contains duplicate thing IDs."))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Thing titles allow 400 characters and reject longer values")
    func thingTitleLengthValidation() throws {
        let validBackup = HabitsBackup(
            format: HabitsBackup.format,
            schemaVersion: HabitsBackup.supportedSchemaVersion,
            exportedAt: makeDate(2026, 4, 30),
            appVersion: nil,
            appBuild: nil,
            habits: [],
            things: [
                BackupThing(
                    id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
                    title: String(repeating: "A", count: Thing.maxTitleLength),
                    dueDate: makeDate(2026, 5, 1),
                    isCompleted: false,
                    completedAt: nil
                )
            ]
        )
        let validData = try JSONEncoder.habitsBackupEncoder.encode(validBackup)
        let preview = try BackupService.decodePreview(from: validData)

        #expect(preview.backup.things.first?.title.count == Thing.maxTitleLength)

        let invalidBackup = HabitsBackup(
            format: HabitsBackup.format,
            schemaVersion: HabitsBackup.supportedSchemaVersion,
            exportedAt: makeDate(2026, 4, 30),
            appVersion: nil,
            appBuild: nil,
            habits: [],
            things: [
                BackupThing(
                    id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
                    title: String(repeating: "A", count: Thing.maxTitleLength + 1),
                    dueDate: makeDate(2026, 5, 1),
                    isCompleted: false,
                    completedAt: nil
                )
            ]
        )
        let invalidData = try JSONEncoder.habitsBackupEncoder.encode(invalidBackup)

        do {
            _ = try BackupService.decodePreview(from: invalidData)
            Issue.record("Overlong thing title was unexpectedly accepted.")
        } catch let error as BackupServiceError {
            #expect(error == .validationFailed("The backup contains a thing with an invalid title."))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Thing completion state must match completedAt")
    func thingCompletionStateMustMatchCompletedAt() throws {
        let invalidBackups = [
            HabitsBackup(
                format: HabitsBackup.format,
                schemaVersion: HabitsBackup.supportedSchemaVersion,
                exportedAt: makeDate(2026, 4, 30),
                appVersion: nil,
                appBuild: nil,
                habits: [],
                things: [
                    BackupThing(
                        id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                        title: "Missing timestamp",
                        dueDate: makeDate(2026, 5, 1),
                        isCompleted: true,
                        completedAt: nil
                    )
                ]
            ),
            HabitsBackup(
                format: HabitsBackup.format,
                schemaVersion: HabitsBackup.supportedSchemaVersion,
                exportedAt: makeDate(2026, 4, 30),
                appVersion: nil,
                appBuild: nil,
                habits: [],
                things: [
                    BackupThing(
                        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
                        title: "Unexpected timestamp",
                        dueDate: makeDate(2026, 5, 1),
                        isCompleted: false,
                        completedAt: makeDate(2026, 5, 1, hour: 9)
                    )
                ]
            )
        ]

        for backup in invalidBackups {
            let data = try JSONEncoder.habitsBackupEncoder.encode(backup)

            do {
                _ = try BackupService.decodePreview(from: data)
                Issue.record("Invalid thing completion state was unexpectedly accepted.")
            } catch let error as BackupServiceError {
                #expect(error == .validationFailed("The backup contains a thing with an invalid completion state."))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Habit.self, HabitCompletion.self, Thing.self, configurations: config)
        return ModelContext(container)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}

private extension JSONEncoder {
    static var habitsBackupEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
