import Foundation
import SwiftData

struct SyncCursor: Codable, Equatable {
    var updatedAt: Date
    var id: UUID
}

struct SyncServiceResult: Equatable {
    var pushedCount: Int
    var pulledCount: Int
}

struct SyncCompletionConflictKey: Hashable {
    var habitID: UUID
    var periodStart: Date
}

@MainActor
enum SyncService {
    static let staleSyncInterval: TimeInterval = 5 * 60
    static let pageSize = 500

    static let lastSuccessfulSyncKeyPrefix = "sync.lastSuccessfulSyncAt"

    private static let clientIDKey = "sync.clientID"
    private static let lastActiveSyncKeyPrefix = "sync.lastActiveSyncAt"
    private static let requiresLocalDataDecisionKey = "sync.requiresLocalDataDecision"
    private static let cursorKeyPrefix = "sync.cursor"
    private static var debounceTask: Task<Void, Never>?
    private static var retryTask: Task<Void, Never>?
    private static let pushRetryDelays: [UInt64] = [
        10_000_000_000,
        30_000_000_000,
        60_000_000_000,
        120_000_000_000,
        300_000_000_000
    ]

    static var clientID: UUID {
        if let rawValue = UserDefaults.standard.string(forKey: clientIDKey),
           let id = UUID(uuidString: rawValue) {
            return id
        }

        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: clientIDKey)
        return id
    }

    static func schedulePush(context: ModelContext) {
        guard !AppEnvironment.disablesRemoteSync else { return }
        guard !requiresLocalDataDecision else { return }
        guard let user = supabase.auth.currentUser else { return }

        debounceTask?.cancel()
        retryTask?.cancel()
        let expectedUserID = user.id
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            do {
                _ = try await pushDirtyRows(context: context, expectedUserID: expectedUserID)
                retryTask = nil
            } catch SyncServiceError.accountChanged {
                retryTask = nil
            } catch {
                #if DEBUG
                print("SyncService debounced push failed: \(error)")
                #endif
                schedulePushRetry(context: context, expectedUserID: expectedUserID, attempt: 0)
            }
        }
    }

    static func cancelPendingPush() {
        debounceTask?.cancel()
        debounceTask = nil
        retryTask?.cancel()
        retryTask = nil
    }

    static func syncIfStale(context: ModelContext) async throws -> SyncServiceResult {
        guard !AppEnvironment.disablesRemoteSync else {
            return SyncServiceResult(pushedCount: 0, pulledCount: 0)
        }
        guard !requiresLocalDataDecision else {
            return SyncServiceResult(pushedCount: 0, pulledCount: 0)
        }

        let user = try await supabase.auth.session.user
        let lastSync = UserDefaults.standard.object(forKey: lastActiveSyncKey(userID: user.id)) as? Date
        if let lastSync, Date.now.timeIntervalSince(lastSync) < staleSyncInterval {
            return SyncServiceResult(pushedCount: 0, pulledCount: 0)
        }

        let result = try await forceSync(context: context)
        return result
    }

    static func forceSync(context: ModelContext) async throws -> SyncServiceResult {
        guard !AppEnvironment.disablesRemoteSync else {
            return SyncServiceResult(pushedCount: 0, pulledCount: 0)
        }
        guard !requiresLocalDataDecision else {
            return SyncServiceResult(pushedCount: 0, pulledCount: 0)
        }

        let user = try await supabase.auth.session.user
        debounceTask?.cancel()
        retryTask?.cancel()
        do {
            let pushedCount = try await pushDirtyRows(context: context, expectedUserID: user.id)
            let pulledCount = try await pullRemoteRows(context: context, expectedUserID: user.id)
            syncWidgets(context: context)
            recordSuccessfulSync(userID: user.id)
            return SyncServiceResult(pushedCount: pushedCount, pulledCount: pulledCount)
        } catch {
            syncWidgets(context: context)
            throw error
        }
    }

    static func replaceLocalDataWithRemote(context: ModelContext) async throws -> SyncServiceResult {
        guard !AppEnvironment.disablesRemoteSync else {
            try BackupService.deleteAllLocalData(context: context)
            syncWidgets(context: context)
            clearLocalDataDecisionRequirement()
            return SyncServiceResult(pushedCount: 0, pulledCount: 0)
        }

        let user = try await supabase.auth.session.user
        debounceTask?.cancel()
        retryTask?.cancel()
        let localBackup = try BackupService.makeBackup(context: context)
        try BackupService.deleteAllLocalData(context: context)
        resetCursors(userID: user.id)
        do {
            let pulledCount = try await pullRemoteRows(context: context, expectedUserID: user.id)
            syncWidgets(context: context)
            recordSuccessfulSync(userID: user.id)
            clearLocalDataDecisionRequirement()
            return SyncServiceResult(pushedCount: 0, pulledCount: pulledCount)
        } catch {
            resetCursors(userID: user.id)
            try? BackupService.deleteAllLocalData(context: context)
            do {
                _ = try await BackupService.importBackup(
                    localBackup,
                    mode: .replace,
                    context: context
                )
            } catch {
                #if DEBUG
                print("SyncService failed to restore local data after replace failure: \(error)")
                #endif
            }
            syncWidgets(context: context)
            throw error
        }
    }

    static func mergeLocalDataIntoRemoteAccount(context: ModelContext) async throws -> SyncServiceResult {
        guard !AppEnvironment.disablesRemoteSync else {
            return SyncServiceResult(pushedCount: 0, pulledCount: 0)
        }

        let user = try await supabase.auth.session.user
        debounceTask?.cancel()
        retryTask?.cancel()
        try prepareLocalDataForAccountMerge(context: context)
        let pushedCount = try await pushDirtyRows(
            context: context,
            allowsPendingLocalDataDecision: true,
            expectedUserID: user.id
        )
        resetCursors(userID: user.id)
        do {
            let pulledCount = try await pullRemoteRows(context: context, expectedUserID: user.id)
            syncWidgets(context: context)
            recordSuccessfulSync(userID: user.id)
            clearLocalDataDecisionRequirement()
            return SyncServiceResult(pushedCount: pushedCount, pulledCount: pulledCount)
        } catch {
            syncWidgets(context: context)
            throw error
        }
    }

    static func lastSuccessfulSyncAt(userID: UUID?) -> Date? {
        guard let userID else { return nil }
        return UserDefaults.standard.object(forKey: lastSuccessfulSyncKey(userID: userID)) as? Date
    }

    static func recordSuccessfulSync(userID: UUID, at date: Date = .now) {
        UserDefaults.standard.set(date, forKey: lastSuccessfulSyncKey(userID: userID))
        UserDefaults.standard.set(date, forKey: lastActiveSyncKey(userID: userID))
    }

    static var requiresLocalDataDecision: Bool {
        UserDefaults.standard.bool(forKey: requiresLocalDataDecisionKey)
    }

    static func requireLocalDataDecision() {
        UserDefaults.standard.set(true, forKey: requiresLocalDataDecisionKey)
    }

    static func clearLocalDataDecisionRequirement() {
        UserDefaults.standard.removeObject(forKey: requiresLocalDataDecisionKey)
    }

    @discardableResult
    static func pushDirtyRows(
        context: ModelContext,
        allowsPendingLocalDataDecision: Bool = false,
        expectedUserID: UUID? = nil
    ) async throws -> Int {
        guard !AppEnvironment.disablesRemoteSync else { return 0 }
        guard allowsPendingLocalDataDecision || !requiresLocalDataDecision else { return 0 }

        let user = try await supabase.auth.session.user
        guard isExpectedSyncUser(actualUserID: user.id, expectedUserID: expectedUserID) else {
            throw SyncServiceError.accountChanged
        }
        let clientID = clientID
        let habits = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.syncNeedsPush == nil || $0.syncNeedsPush == true }))
        let completions = try context.fetch(FetchDescriptor<HabitCompletion>(predicate: #Predicate { $0.syncNeedsPush == nil || $0.syncNeedsPush == true }))
        let things = try context.fetch(FetchDescriptor<Thing>(predicate: #Predicate { $0.syncNeedsPush == nil || $0.syncNeedsPush == true }))
        let snapshots = PushSnapshots(habits: habits, completions: completions, things: things)

        var acknowledgedCount = 0

        acknowledgedCount += try await pushHabits(
            habits.filter { $0.syncDeletedAt == nil },
            userID: user.id,
            clientID: clientID,
            snapshots: snapshots.habits
        )
        acknowledgedCount += try await pushThings(
            things.filter { $0.syncDeletedAt == nil },
            userID: user.id,
            clientID: clientID,
            snapshots: snapshots.things
        )
        acknowledgedCount += try await pushCompletions(
            completions.filter { $0.syncDeletedAt == nil },
            userID: user.id,
            clientID: clientID,
            snapshots: snapshots.completions
        )
        acknowledgedCount += try await pushCompletions(
            completions.filter { $0.syncDeletedAt != nil },
            userID: user.id,
            clientID: clientID,
            snapshots: snapshots.completions
        )
        acknowledgedCount += try await pushThings(
            things.filter { $0.syncDeletedAt != nil },
            userID: user.id,
            clientID: clientID,
            snapshots: snapshots.things
        )
        acknowledgedCount += try await pushHabits(
            habits.filter { $0.syncDeletedAt != nil },
            userID: user.id,
            clientID: clientID,
            snapshots: snapshots.habits
        )

        if acknowledgedCount > 0 {
            try context.save()
        }
        return acknowledgedCount
    }

    @discardableResult
    static func pullRemoteRows(context: ModelContext, expectedUserID: UUID? = nil) async throws -> Int {
        let user = try await supabase.auth.session.user
        guard isExpectedSyncUser(actualUserID: user.id, expectedUserID: expectedUserID) else {
            throw SyncServiceError.accountChanged
        }
        let localClientID = clientID
        let habitResult = try await pullHabits(userID: user.id, clientID: localClientID, context: context)
        let thingResult = try await pullThings(userID: user.id, clientID: localClientID, context: context)
        let completionResult = try await pullCompletions(userID: user.id, clientID: localClientID, context: context)

        let appliedCount = habitResult.appliedCount + thingResult.appliedCount + completionResult.appliedCount
        let localChangeCount = habitResult.localChangeCount + thingResult.localChangeCount + completionResult.localChangeCount

        if localChangeCount > 0 {
            try context.save()
        }

        saveCursorIfPresent(for: .habits, userID: user.id, cursor: habitResult.cursor)
        saveCursorIfPresent(for: .things, userID: user.id, cursor: thingResult.cursor)
        saveCursorIfPresent(for: .completions, userID: user.id, cursor: completionResult.cursor)

        if appliedCount > 0 {
            syncWidgets(context: context)
        }
        return appliedCount
    }

    static func isExpectedSyncUser(actualUserID: UUID, expectedUserID: UUID?) -> Bool {
        guard let expectedUserID else { return true }
        return actualUserID == expectedUserID
    }

    static func shouldClearDirty(localUpdatedAt: Date, pushedAt: Date) -> Bool {
        localUpdatedAt <= pushedAt
    }

    static func shouldApplyRemote(remoteUpdatedAt: Date, localRemoteUpdatedAt: Date?) -> Bool {
        guard let localRemoteUpdatedAt else { return true }
        return remoteUpdatedAt > localRemoteUpdatedAt
    }

    static func shouldSkipOwnRemoteEcho(remoteClientID: UUID, localClientID: UUID, localNeedsPush: Bool?) -> Bool {
        remoteClientID == localClientID && localNeedsPush != false
    }

    static func hasPendingThingFieldEdits(_ thing: Thing) -> Bool {
        thing.syncTitleUpdatedAt != nil
            || thing.syncDueDateUpdatedAt != nil
            || thing.syncCompletionUpdatedAt != nil
            || thing.syncDeletionUpdatedAt != nil
    }

    nonisolated static func completionConflictKey(habitID: UUID, periodStart: Date) -> SyncCompletionConflictKey {
        SyncCompletionConflictKey(habitID: habitID, periodStart: periodStart)
    }

    static func completionConflictKey(for completion: HabitCompletion) -> SyncCompletionConflictKey? {
        guard let habit = completion.habit else { return nil }
        let periodStart = completion.periodStart ?? HabitCompletion.periodStart(for: completion.date, habit: habit)
        return completionConflictKey(habitID: habit.id, periodStart: periodStart)
    }

    static func prepareLocalDataForAccountMerge(context: ModelContext, at date: Date = .now) throws {
        let habits = try context.fetch(FetchDescriptor<Habit>())
        let completions = try context.fetch(FetchDescriptor<HabitCompletion>())
        let things = try context.fetch(FetchDescriptor<Thing>())

        for completion in completions where completion.syncDeletedAt != nil || completion.habit?.syncDeletedAt != nil {
            context.delete(completion)
        }

        for habit in habits where habit.syncDeletedAt != nil {
            NotificationService.removeNotification(for: habit)
            context.delete(habit)
        }

        for thing in things where thing.syncDeletedAt != nil {
            context.delete(thing)
        }

        for habit in habits where habit.syncDeletedAt == nil {
            habit.syncUpdatedAt = date
            habit.syncRemoteUpdatedAt = nil
            habit.syncNeedsPush = true
        }

        for completion in completions where completion.syncDeletedAt == nil && completion.habit?.syncDeletedAt == nil {
            completion.syncUpdatedAt = date
            completion.syncRemoteUpdatedAt = nil
            completion.syncNeedsPush = true
        }

        for thing in things where thing.syncDeletedAt == nil {
            thing.syncUpdatedAt = date
            thing.syncRemoteUpdatedAt = nil
            thing.syncNeedsPush = true
        }

        try context.save()
    }

    static func cursorAdvanced(from cursor: SyncCursor?, with updatedAt: Date, id: UUID) -> SyncCursor {
        guard let cursor else { return SyncCursor(updatedAt: updatedAt, id: id) }
        if updatedAt > cursor.updatedAt { return SyncCursor(updatedAt: updatedAt, id: id) }
        if updatedAt == cursor.updatedAt && id.uuidString > cursor.id.uuidString {
            return SyncCursor(updatedAt: updatedAt, id: id)
        }
        return cursor
    }

    private static func pushHabits(
        _ habits: [Habit],
        userID: UUID,
        clientID: UUID,
        snapshots: [UUID: Date]
    ) async throws -> Int {
        try await pushRows(
            habits,
            table: .habits,
            onConflict: "id",
            remoteType: SyncHabitRecord.self,
            snapshots: snapshots,
            makeRecord: { SyncHabitUpsert(habit: $0, userID: userID, clientID: clientID) },
            localID: \.id,
            localUpdatedAt: \.syncUpdatedAt,
            acknowledge: acknowledge
        )
    }

    private static func pushCompletions(
        _ completions: [HabitCompletion],
        userID: UUID,
        clientID: UUID,
        snapshots: [UUID: Date]
    ) async throws -> Int {
        guard !completions.isEmpty else { return 0 }
        let completionsToPush = preferredCompletionsByConflictKey(completions)
        let records = completionsToPush.compactMap { SyncCompletionUpsert(completion: $0, userID: userID, clientID: clientID) }
        guard !records.isEmpty else { return 0 }

        let returned: [SyncCompletionRecord] = try await supabase
            .from(SyncTable.completions.rawValue)
            .upsert(records, onConflict: "user_id,habit_id,period_start", returning: .representation)
            .execute()
            .value
        let returnedByID = Dictionary(uniqueKeysWithValues: returned.map { ($0.id, $0) })
        let returnedByConflictKey = Dictionary(uniqueKeysWithValues: returned.map { ($0.conflictKey, $0) })

        for completion in completionsToPush {
            guard let snapshot = snapshots[completion.id],
                  shouldClearDirty(localUpdatedAt: completion.syncUpdatedAt ?? .distantPast, pushedAt: snapshot) else {
                continue
            }

            let returned = returnedByID[completion.id]
                ?? completionConflictKey(for: completion).flatMap { returnedByConflictKey[$0] }
            guard let returned else { continue }

            acknowledge(completion, remoteUpdatedAt: returned.updatedAt)
        }
        return returned.count
    }

    private static func pushThings(
        _ things: [Thing],
        userID: UUID,
        clientID: UUID,
        snapshots: [UUID: Date]
    ) async throws -> Int {
        var fullRows: [Thing] = []
        var patchRows: [Thing] = []

        for thing in things {
            let record = SyncThingUpsert(thing: thing, userID: userID, clientID: clientID)
            if record.encodesFullRow {
                fullRows.append(thing)
            } else {
                patchRows.append(thing)
            }
        }

        var acknowledgedCount = try await pushRows(
            fullRows,
            table: .things,
            onConflict: "id",
            remoteType: SyncThingRecord.self,
            snapshots: snapshots,
            makeRecord: { SyncThingUpsert(thing: $0, userID: userID, clientID: clientID) },
            localID: \.id,
            localUpdatedAt: \.syncUpdatedAt,
            acknowledge: acknowledge
        )

        for thing in patchRows {
            acknowledgedCount += try await updateThing(
                thing,
                userID: userID,
                clientID: clientID,
                snapshots: snapshots
            )
        }

        return acknowledgedCount
    }

    private static func updateThing(
        _ thing: Thing,
        userID: UUID,
        clientID: UUID,
        snapshots: [UUID: Date]
    ) async throws -> Int {
        let record = SyncThingUpsert(thing: thing, userID: userID, clientID: clientID)
        let returned: [SyncThingRecord] = try await supabase
            .from(SyncTable.things.rawValue)
            .update(record, returning: .representation)
            .eq("id", value: thing.id.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value

        if let returned = returned.first {
            if let snapshot = snapshots[thing.id],
               shouldClearDirty(localUpdatedAt: thing.syncUpdatedAt ?? .distantPast, pushedAt: snapshot) {
                acknowledge(thing, remoteUpdatedAt: returned.updatedAt)
            }
            return 1
        }

        return try await pushRows(
            [thing],
            table: .things,
            onConflict: "id",
            remoteType: SyncThingRecord.self,
            snapshots: snapshots,
            makeRecord: { SyncThingUpsert(thing: $0, userID: userID, clientID: clientID, forceFullRow: true) },
            localID: \.id,
            localUpdatedAt: \.syncUpdatedAt,
            acknowledge: acknowledge
        )
    }

    private static func pushRows<Local, Upsert: Encodable, Remote: Decodable & SyncRemoteRecord>(
        _ localRows: [Local],
        table: SyncTable,
        onConflict: String,
        remoteType: Remote.Type,
        snapshots: [UUID: Date],
        makeRecord: (Local) -> Upsert?,
        localID: KeyPath<Local, UUID>,
        localUpdatedAt: KeyPath<Local, Date?>,
        acknowledge: (Local, Date) -> Void
    ) async throws -> Int {
        guard !localRows.isEmpty else { return 0 }
        let records = localRows.compactMap(makeRecord)
        guard !records.isEmpty else { return 0 }

        let returned: [Remote] = try await supabase
            .from(table.rawValue)
            .upsert(records, onConflict: onConflict, returning: .representation)
            .execute()
            .value
        let returnedByID = Dictionary(uniqueKeysWithValues: returned.map { ($0.id, $0) })

        for localRow in localRows {
            let id = localRow[keyPath: localID]
            guard let snapshot = snapshots[id],
                  shouldClearDirty(localUpdatedAt: localRow[keyPath: localUpdatedAt] ?? .distantPast, pushedAt: snapshot),
                  let returned = returnedByID[id] else { continue }
            acknowledge(localRow, returned.updatedAt)
        }
        return returned.count
    }

    private static func pullHabits(userID: UUID, clientID: UUID, context: ModelContext) async throws -> SyncPullTableResult {
        var habitsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Habit>()).map { ($0.id, $0) })
        return try await pullRows(table: .habits, userID: userID) { (record: SyncHabitRecord) in
            let result = try apply(record, clientID: clientID, context: context, habitsByID: &habitsByID)
            if result.changedLocalStore, let habit = habitsByID[record.id] {
                await syncNotification(for: habit)
            }
            return result
        }
    }

    private static func pullCompletions(userID: UUID, clientID: UUID, context: ModelContext) async throws -> SyncPullTableResult {
        let localCompletions = try context.fetch(FetchDescriptor<HabitCompletion>())
        var completionsByID = Dictionary(uniqueKeysWithValues: localCompletions.map { ($0.id, $0) })
        var completionsByConflictKey: [SyncCompletionConflictKey: HabitCompletion] = [:]
        for completion in localCompletions {
            guard let key = completionConflictKey(for: completion) else { continue }
            completionsByConflictKey[key] = preferredCompletion(
                existing: completionsByConflictKey[key],
                candidate: completion
            )
        }
        var habitsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Habit>()).map { ($0.id, $0) })
        return try await pullRows(table: .completions, userID: userID) { (record: SyncCompletionRecord) in
            var fetchedParentChangedLocalStore = false
            if habitsByID[record.habitID] == nil {
                if let parent = try await fetchRemoteHabit(id: record.habitID, userID: userID) {
                    let parentResult = try apply(parent, clientID: clientID, context: context, habitsByID: &habitsByID)
                    fetchedParentChangedLocalStore = parentResult.changedLocalStore
                    if let habit = habitsByID[parent.id] {
                        await syncNotification(for: habit)
                    }
                }
            }
            guard habitsByID[record.habitID] != nil else {
                return .skippedInvalid
            }
            let completionResult = try apply(
                record,
                clientID: clientID,
                context: context,
                completionsByID: &completionsByID,
                completionsByConflictKey: &completionsByConflictKey,
                habitsByID: habitsByID
            )
            if fetchedParentChangedLocalStore && !completionResult.changedLocalStore {
                return .acknowledged
            }
            return completionResult
        }
    }

    private static func pullThings(userID: UUID, clientID: UUID, context: ModelContext) async throws -> SyncPullTableResult {
        var thingsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Thing>()).map { ($0.id, $0) })
        return try await pullRows(table: .things, userID: userID) { (record: SyncThingRecord) in
            try apply(record, clientID: clientID, context: context, thingsByID: &thingsByID)
        }
    }

    private static func pullRows<T: Decodable & SyncRemoteRecord>(
        table: SyncTable,
        userID: UUID,
        apply: @MainActor (T) async throws -> SyncApplyResult
    ) async throws -> SyncPullTableResult {
        let records: [T] = try await fetchRemoteRows(table: table, userID: userID)
        var cursor = cursor(for: table, userID: userID)
        var applied = 0
        var localChanges = 0
        for record in records {
            let result = try await apply(record)
            if result.appliedRemote {
                applied += 1
            }
            if result.changedLocalStore {
                localChanges += 1
            }
            cursor = cursorAdvanced(from: cursor, with: record.updatedAt, id: record.id)
        }
        return SyncPullTableResult(appliedCount: applied, localChangeCount: localChanges, cursor: cursor)
    }

    private static func fetchRemoteRows<T: Decodable & SyncRemoteRecord>(table: SyncTable, userID: UUID) async throws -> [T] {
        var records: [T] = []
        var pageCursor = cursor(for: table, userID: userID)

        while true {
            let page: [T] = try await fetchRemotePage(table: table, userID: userID, after: pageCursor)
            records.append(contentsOf: page)

            guard page.count == pageSize, let last = page.last else {
                return records
            }
            pageCursor = SyncCursor(updatedAt: last.updatedAt, id: last.id)
        }
    }

    private static func fetchRemotePage<T: Decodable>(
        table: SyncTable,
        userID: UUID,
        after cursor: SyncCursor?
    ) async throws -> [T] {
        if let cursor {
            return try await supabase
                .from(table.rawValue)
                .select()
                .eq("user_id", value: userID.uuidString)
                .or("updated_at.gt.\(isoString(cursor.updatedAt)),and(updated_at.eq.\(isoString(cursor.updatedAt)),id.gt.\(cursor.id.uuidString))")
                .order("updated_at", ascending: true)
                .order("id", ascending: true)
                .limit(pageSize)
                .execute()
                .value
        }

        return try await supabase
            .from(table.rawValue)
            .select()
            .eq("user_id", value: userID.uuidString)
            .order("updated_at", ascending: true)
            .order("id", ascending: true)
            .limit(pageSize)
            .execute()
            .value
    }

    private static func fetchRemoteHabit(id: UUID, userID: UUID) async throws -> SyncHabitRecord? {
        let records: [SyncHabitRecord] = try await supabase
            .from(SyncTable.habits.rawValue)
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        return records.first
    }

    private static func apply(
        _ record: SyncHabitRecord,
        clientID: UUID,
        context: ModelContext,
        habitsByID: inout [UUID: Habit]
    ) throws -> SyncApplyResult {
        if let habit = habitsByID[record.id] {
            if shouldSkipOwnRemoteEcho(remoteClientID: record.clientID, localClientID: clientID, localNeedsPush: habit.syncNeedsPush) {
                return .unchanged
            }
            if record.clientID == clientID && habit.syncNeedsPush == false {
                acknowledge(habit, remoteUpdatedAt: record.updatedAt)
                return .acknowledged
            }
            guard shouldApplyRemote(remoteUpdatedAt: record.updatedAt, localRemoteUpdatedAt: habit.syncRemoteUpdatedAt) else {
                return .unchanged
            }
            try record.apply(to: habit)
            acknowledge(habit, remoteUpdatedAt: record.updatedAt)
            return .applied
        }

        let habit = try record.makeHabit()
        context.insert(habit)
        habitsByID[record.id] = habit
        return .applied
    }

    private static func apply(
        _ record: SyncCompletionRecord,
        clientID: UUID,
        context: ModelContext,
        completionsByID: inout [UUID: HabitCompletion],
        completionsByConflictKey: inout [SyncCompletionConflictKey: HabitCompletion],
        habitsByID: [UUID: Habit]
    ) throws -> SyncApplyResult {
        guard let habit = habitsByID[record.habitID] else {
            return .skippedInvalid
        }

        if let completion = completionsByID[record.id] ?? completionsByConflictKey[record.conflictKey] {
            if shouldSkipOwnRemoteEcho(remoteClientID: record.clientID, localClientID: clientID, localNeedsPush: completion.syncNeedsPush) {
                return .unchanged
            }
            if record.clientID == clientID && completion.syncNeedsPush == false {
                acknowledge(completion, remoteUpdatedAt: record.updatedAt)
                completionsByID[record.id] = completion
                completionsByConflictKey[record.conflictKey] = completion
                return .acknowledged
            }
            guard shouldApplyRemote(remoteUpdatedAt: record.updatedAt, localRemoteUpdatedAt: completion.syncRemoteUpdatedAt) else {
                return .unchanged
            }
            record.apply(to: completion, habit: habit)
            acknowledge(completion, remoteUpdatedAt: record.updatedAt)
            completionsByID[record.id] = completion
            completionsByConflictKey[record.conflictKey] = completion
            return .applied
        }

        let completion = record.makeCompletion(habit: habit)
        context.insert(completion)
        completionsByID[record.id] = completion
        completionsByConflictKey[record.conflictKey] = completion
        return .applied
    }

    private static func apply(
        _ record: SyncThingRecord,
        clientID: UUID,
        context: ModelContext,
        thingsByID: inout [UUID: Thing]
    ) throws -> SyncApplyResult {
        if let thing = thingsByID[record.id] {
            if shouldSkipOwnRemoteEcho(remoteClientID: record.clientID, localClientID: clientID, localNeedsPush: thing.syncNeedsPush) {
                return .unchanged
            }
            if record.clientID == clientID && thing.syncNeedsPush == false {
                acknowledge(thing, remoteUpdatedAt: record.updatedAt)
                return .acknowledged
            }
            guard shouldApplyRemote(remoteUpdatedAt: record.updatedAt, localRemoteUpdatedAt: thing.syncRemoteUpdatedAt) else {
                return .unchanged
            }
            let preservesLocalEdits = hasPendingThingFieldEdits(thing)
            try record.apply(to: thing)
            if preservesLocalEdits {
                thing.syncRemoteUpdatedAt = record.updatedAt
                thing.syncNeedsPush = true
            } else {
                acknowledge(thing, remoteUpdatedAt: record.updatedAt)
            }
            return .applied
        }

        let thing = try record.makeThing()
        context.insert(thing)
        thingsByID[record.id] = thing
        return .applied
    }

    private static func acknowledge(_ habit: Habit, remoteUpdatedAt: Date) {
        habit.syncRemoteUpdatedAt = remoteUpdatedAt
        habit.syncNeedsPush = false
    }

    private static func acknowledge(_ completion: HabitCompletion, remoteUpdatedAt: Date) {
        completion.syncRemoteUpdatedAt = remoteUpdatedAt
        completion.syncNeedsPush = false
    }

    private static func preferredCompletion(existing: HabitCompletion?, candidate: HabitCompletion) -> HabitCompletion {
        guard let existing else { return candidate }
        if existing.syncDeletedAt != nil && candidate.syncDeletedAt == nil {
            return candidate
        }
        if existing.syncDeletedAt == nil && candidate.syncDeletedAt != nil {
            return existing
        }
        return (candidate.syncRemoteUpdatedAt ?? candidate.syncUpdatedAt ?? .distantPast) >
            (existing.syncRemoteUpdatedAt ?? existing.syncUpdatedAt ?? .distantPast)
            ? candidate
            : existing
    }

    private static func preferredCompletionsByConflictKey(_ completions: [HabitCompletion]) -> [HabitCompletion] {
        var keyed: [SyncCompletionConflictKey: HabitCompletion] = [:]
        var unkeyed: [HabitCompletion] = []

        for completion in completions {
            guard let key = completionConflictKey(for: completion) else {
                unkeyed.append(completion)
                continue
            }

            keyed[key] = preferredCompletion(existing: keyed[key], candidate: completion)
        }

        return Array(keyed.values) + unkeyed
    }

    private static func acknowledge(_ thing: Thing, remoteUpdatedAt: Date) {
        thing.syncRemoteUpdatedAt = remoteUpdatedAt
        thing.syncNeedsPush = false
        thing.syncTitleUpdatedAt = nil
        thing.syncDueDateUpdatedAt = nil
        thing.syncCompletionUpdatedAt = nil
        thing.syncDeletionUpdatedAt = nil
    }

    private static func schedulePushRetry(context: ModelContext, expectedUserID: UUID, attempt: Int) {
        retryTask?.cancel()
        let delay = pushRetryDelays[min(attempt, pushRetryDelays.count - 1)]
        retryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            do {
                _ = try await pushDirtyRows(context: context, expectedUserID: expectedUserID)
                retryTask = nil
            } catch SyncServiceError.accountChanged {
                retryTask = nil
            } catch {
                #if DEBUG
                print("SyncService retry push failed: \(error)")
                #endif
                schedulePushRetry(context: context, expectedUserID: expectedUserID, attempt: attempt + 1)
            }
        }
    }

    private static func syncWidgets(context: ModelContext) {
        HabitWidgetSyncService.sync(context: context)
        ThingWidgetSyncService.sync(context: context)
    }

    private static func syncNotification(for habit: Habit) async {
        if habit.syncDeletedAt != nil || !habit.notificationsEnabled {
            NotificationService.removeNotification(for: habit)
        } else {
            _ = await NotificationService.scheduleNotification(for: habit)
        }
    }

    private static func cursor(for table: SyncTable, userID: UUID) -> SyncCursor? {
        let key = cursorKey(table: table, userID: userID)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SyncCursor.self, from: data)
    }

    private static func saveCursor(for table: SyncTable, userID: UUID, cursor: SyncCursor) {
        let key = cursorKey(table: table, userID: userID)
        guard let data = try? JSONEncoder().encode(cursor) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func saveCursorIfPresent(for table: SyncTable, userID: UUID, cursor: SyncCursor?) {
        guard let cursor else { return }
        saveCursor(for: table, userID: userID, cursor: cursor)
    }

    private static func resetCursors(userID: UUID) {
        for table in SyncTable.allCases {
            UserDefaults.standard.removeObject(forKey: cursorKey(table: table, userID: userID))
        }
    }

    private static func lastActiveSyncKey(userID: UUID) -> String {
        "\(lastActiveSyncKeyPrefix).\(userID.uuidString)"
    }

    static func lastSuccessfulSyncKey(userID: UUID) -> String {
        "\(lastSuccessfulSyncKeyPrefix).\(userID.uuidString)"
    }

    private static func cursorKey(table: SyncTable, userID: UUID) -> String {
        "\(cursorKeyPrefix).\(userID.uuidString).\(table.rawValue)"
    }

    private static func isoString(_ date: Date) -> String {
        SyncDateCoding.timestampString(date)
    }
}

private enum SyncDateCoding {
    private static let timestampStringFormatterKey = "Habits.SyncDateCoding.timestampStringFormatter"
    private static let fractionalISOFormatterKey = "Habits.SyncDateCoding.fractionalISOFormatter"
    private static let wholeISOFormatterKey = "Habits.SyncDateCoding.wholeISOFormatter"

    static func dateOnlyString(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    static func dateOnly(from string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    static func timestampString(_ date: Date) -> String {
        timestampFormatter(key: timestampStringFormatterKey, format: "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX")
            .string(from: date)
    }

    static func timestamp(from string: String) -> Date? {
        let fractionalFormatter = isoFormatter(key: fractionalISOFormatterKey, options: [.withInternetDateTime, .withFractionalSeconds])
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let wholeFormatter = isoFormatter(key: wholeISOFormatterKey, options: [.withInternetDateTime])
        if let date = wholeFormatter.date(from: string) {
            return date
        }

        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        ] {
            let formatter = timestampFormatter(key: "Habits.SyncDateCoding.\(format)", format: format)
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }

    private static func timestampFormatter(key: String, format: String) -> DateFormatter {
        if let formatter = Thread.current.threadDictionary[key] as? DateFormatter {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }

    private static func isoFormatter(key: String, options: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        if let formatter = Thread.current.threadDictionary[key] as? ISO8601DateFormatter {
            return formatter
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        Thread.current.threadDictionary[key] = formatter
        return formatter
    }
}

private extension KeyedDecodingContainer {
    func decodeSyncDateOnly(forKey key: Key) throws -> Date {
        if let string = try? decode(String.self, forKey: key),
           let date = SyncDateCoding.dateOnly(from: string) {
            return date
        }

        if let date = try? decode(Date.self, forKey: key) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Invalid SQL date format."
        )
    }

    func decodeSyncTimestamp(forKey key: Key) throws -> Date {
        if let string = try? decode(String.self, forKey: key),
           let date = SyncDateCoding.timestamp(from: string) {
            return date
        }

        if let date = try? decode(Date.self, forKey: key) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: self,
            debugDescription: "Invalid timestamp format."
        )
    }

    func decodeSyncOptionalTimestamp(forKey key: Key) throws -> Date? {
        if try decodeNil(forKey: key) {
            return nil
        }

        if let string = try? decode(String.self, forKey: key) {
            guard let date = SyncDateCoding.timestamp(from: string) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key,
                    in: self,
                    debugDescription: "Invalid timestamp format."
                )
            }
            return date
        }

        return try decodeIfPresent(Date.self, forKey: key)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeSyncDateOnly(_ date: Date, forKey key: Key) throws {
        try encode(SyncDateCoding.dateOnlyString(date), forKey: key)
    }
}

private struct PushSnapshots {
    var habits: [UUID: Date]
    var completions: [UUID: Date]
    var things: [UUID: Date]

    init(habits: [Habit], completions: [HabitCompletion], things: [Thing]) {
        self.habits = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.syncUpdatedAt ?? .distantPast) })
        self.completions = Dictionary(uniqueKeysWithValues: completions.map { ($0.id, $0.syncUpdatedAt ?? .distantPast) })
        self.things = Dictionary(uniqueKeysWithValues: things.map { ($0.id, $0.syncUpdatedAt ?? .distantPast) })
    }
}

private struct SyncPullTableResult {
    var appliedCount: Int
    var localChangeCount: Int
    var cursor: SyncCursor?
}

private enum SyncApplyResult: Equatable {
    case unchanged
    case acknowledged
    case applied
    case skippedInvalid

    var appliedRemote: Bool {
        self == .applied
    }

    var changedLocalStore: Bool {
        self == .acknowledged || self == .applied
    }
}

private enum SyncServiceError: LocalizedError {
    case accountChanged
    case invalidRemoteHabit(String)
    case invalidRemoteThing(String)

    var errorDescription: String? {
        switch self {
        case .accountChanged:
            return "The signed-in account changed while sync was in progress."
        case .invalidRemoteHabit(let reason):
            return "The remote habit data is invalid: \(reason)"
        case .invalidRemoteThing(let reason):
            return "The remote thing data is invalid: \(reason)"
        }
    }
}

private enum SyncTable: String, CaseIterable {
    case habits
    case completions = "habit_completions"
    case things
}

protocol SyncRemoteRecord: Sendable {
    var id: UUID { get }
    var updatedAt: Date { get }
}

struct SyncHabitUpsert: Codable, Equatable {
    var id: UUID
    var userID: UUID
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
    var deletedAt: Date?
    var clientID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case frequency
        case customIntervalValue = "custom_interval_value"
        case customIntervalUnit = "custom_interval_unit"
        case timesToComplete = "times_to_complete"
        case startDate = "start_date"
        case notificationsEnabled = "notifications_enabled"
        case notificationHour = "notification_hour"
        case notificationMinute = "notification_minute"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
        case clientID = "client_id"
    }

    init(habit: Habit, userID: UUID, clientID: UUID) {
        id = habit.id
        self.userID = userID
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
        deletedAt = habit.syncDeletedAt
        self.clientID = clientID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(name, forKey: .name)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(customIntervalValue, forKey: .customIntervalValue)
        try container.encode(customIntervalUnit, forKey: .customIntervalUnit)
        try container.encode(timesToComplete, forKey: .timesToComplete)
        try container.encodeSyncDateOnly(startDate, forKey: .startDate)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(notificationHour, forKey: .notificationHour)
        try container.encode(notificationMinute, forKey: .notificationMinute)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(clientID, forKey: .clientID)
    }
}

struct SyncHabitRecord: Codable, Equatable, SyncRemoteRecord {
    var id: UUID
    var userID: UUID
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
    var updatedAt: Date
    var deletedAt: Date?
    var clientID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case frequency
        case customIntervalValue = "custom_interval_value"
        case customIntervalUnit = "custom_interval_unit"
        case timesToComplete = "times_to_complete"
        case startDate = "start_date"
        case notificationsEnabled = "notifications_enabled"
        case notificationHour = "notification_hour"
        case notificationMinute = "notification_minute"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientID = "client_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        frequency = try container.decode(String.self, forKey: .frequency)
        customIntervalValue = try container.decodeIfPresent(Int.self, forKey: .customIntervalValue)
        customIntervalUnit = try container.decodeIfPresent(String.self, forKey: .customIntervalUnit)
        timesToComplete = try container.decode(Int.self, forKey: .timesToComplete)
        startDate = try container.decodeSyncDateOnly(forKey: .startDate)
        notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        notificationHour = try container.decodeIfPresent(Int.self, forKey: .notificationHour)
        notificationMinute = try container.decodeIfPresent(Int.self, forKey: .notificationMinute)
        createdAt = try container.decodeSyncTimestamp(forKey: .createdAt)
        updatedAt = try container.decodeSyncTimestamp(forKey: .updatedAt)
        deletedAt = try container.decodeSyncOptionalTimestamp(forKey: .deletedAt)
        clientID = try container.decode(UUID.self, forKey: .clientID)
    }

    func makeHabit() throws -> Habit {
        let validated = try validatedFields()
        return Habit(
            id: id,
            name: validated.name,
            frequency: validated.frequency,
            customIntervalValue: validated.customIntervalValue,
            customIntervalUnit: validated.customIntervalUnit,
            timesToComplete: timesToComplete,
            startDate: startDate,
            notificationsEnabled: notificationsEnabled,
            notificationHour: notificationHour,
            notificationMinute: notificationMinute,
            createdAt: createdAt,
            syncUpdatedAt: updatedAt,
            syncDeletedAt: deletedAt,
            syncRemoteUpdatedAt: updatedAt,
            syncNeedsPush: false
        )
    }

    func apply(to habit: Habit) throws {
        let validated = try validatedFields()
        habit.name = validated.name
        habit.frequency = validated.frequency
        habit.customIntervalValue = validated.customIntervalValue
        habit.customIntervalUnit = validated.customIntervalUnit
        habit.timesToComplete = timesToComplete
        habit.startDate = startDate
        habit.notificationsEnabled = notificationsEnabled
        habit.notificationHour = notificationHour
        habit.notificationMinute = notificationMinute
        habit.createdAt = createdAt
        habit.syncDeletedAt = deletedAt
    }

    private func validatedFields() throws -> (
        name: String,
        frequency: HabitFrequency,
        customIntervalValue: Int?,
        customIntervalUnit: CustomIntervalUnit?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= Habit.maxNameLength else {
            throw SyncServiceError.invalidRemoteHabit("name is empty or too long")
        }

        guard (1...Habit.maxTimesToComplete).contains(timesToComplete) else {
            throw SyncServiceError.invalidRemoteHabit("goal is out of range")
        }

        guard let frequency = HabitFrequency(rawValue: frequency) else {
            throw SyncServiceError.invalidRemoteHabit("unknown frequency")
        }

        if frequency == .custom {
            guard let customIntervalValue,
                  (1...Habit.maxCustomIntervalValue).contains(customIntervalValue),
                  let customIntervalUnitRawValue = customIntervalUnit,
                  let customIntervalUnit = CustomIntervalUnit(rawValue: customIntervalUnitRawValue) else {
                throw SyncServiceError.invalidRemoteHabit("invalid custom interval")
            }
            return (
                name: trimmedName,
                frequency: frequency,
                customIntervalValue: customIntervalValue,
                customIntervalUnit: customIntervalUnit
            )
        }

        guard customIntervalValue == nil, customIntervalUnit == nil else {
            throw SyncServiceError.invalidRemoteHabit("non-custom habit has custom interval fields")
        }

        return (
            name: trimmedName,
            frequency: frequency,
            customIntervalValue: nil,
            customIntervalUnit: nil
        )
    }
}

struct SyncCompletionUpsert: Codable, Equatable {
    var id: UUID
    var userID: UUID
    var habitID: UUID
    var periodStart: Date
    var date: Date
    var count: Int
    var createdAt: Date
    var deletedAt: Date?
    var clientID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case habitID = "habit_id"
        case periodStart = "period_start"
        case date
        case count
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
        case clientID = "client_id"
    }

    init?(completion: HabitCompletion, userID: UUID, clientID: UUID) {
        guard let habitID = completion.habit?.id else { return nil }
        id = completion.id
        self.userID = userID
        self.habitID = habitID
        periodStart = completion.periodStart ?? HabitCompletion.periodStart(for: completion.date, habit: completion.habit)
        date = completion.date
        count = completion.count
        createdAt = completion.date
        deletedAt = completion.syncDeletedAt
        self.clientID = clientID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(habitID, forKey: .habitID)
        try container.encodeSyncDateOnly(periodStart, forKey: .periodStart)
        try container.encode(date, forKey: .date)
        try container.encode(count, forKey: .count)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(clientID, forKey: .clientID)
    }
}

struct SyncCompletionRecord: Codable, Equatable, SyncRemoteRecord {
    var id: UUID
    var userID: UUID
    var habitID: UUID
    var periodStart: Date
    var date: Date
    var count: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var clientID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case habitID = "habit_id"
        case periodStart = "period_start"
        case date
        case count
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientID = "client_id"
    }

    var conflictKey: SyncCompletionConflictKey {
        SyncService.completionConflictKey(habitID: habitID, periodStart: periodStart)
    }

    init(
        id: UUID,
        userID: UUID,
        habitID: UUID,
        periodStart: Date,
        date: Date,
        count: Int,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        clientID: UUID
    ) {
        self.id = id
        self.userID = userID
        self.habitID = habitID
        self.periodStart = periodStart
        self.date = date
        self.count = count
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.clientID = clientID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        habitID = try container.decode(UUID.self, forKey: .habitID)
        periodStart = try container.decodeSyncDateOnly(forKey: .periodStart)
        date = try container.decodeSyncTimestamp(forKey: .date)
        count = try container.decode(Int.self, forKey: .count)
        createdAt = try container.decodeSyncTimestamp(forKey: .createdAt)
        updatedAt = try container.decodeSyncTimestamp(forKey: .updatedAt)
        deletedAt = try container.decodeSyncOptionalTimestamp(forKey: .deletedAt)
        clientID = try container.decode(UUID.self, forKey: .clientID)
    }

    func makeCompletion(habit: Habit?) -> HabitCompletion {
        HabitCompletion(
            id: id,
            date: date,
            periodStart: periodStart,
            count: count,
            habit: habit,
            syncUpdatedAt: updatedAt,
            syncDeletedAt: deletedAt,
            syncRemoteUpdatedAt: updatedAt,
            syncNeedsPush: false
        )
    }

    func apply(to completion: HabitCompletion, habit: Habit?) {
        completion.date = date
        completion.periodStart = periodStart
        completion.count = count
        completion.habit = habit
        completion.syncDeletedAt = deletedAt
    }
}

struct ThingDirtyFields: OptionSet {
    let rawValue: Int

    static let title = ThingDirtyFields(rawValue: 1 << 0)
    static let dueDate = ThingDirtyFields(rawValue: 1 << 1)
    static let completion = ThingDirtyFields(rawValue: 1 << 2)
    static let deletion = ThingDirtyFields(rawValue: 1 << 3)
}

struct SyncThingUpsert: Encodable, Equatable {
    var id: UUID
    var userID: UUID
    var title: String
    var dueDate: Date
    var isCompleted: Bool
    var completedAt: Date?
    var deletedAt: Date?
    var clientID: UUID
    var dirtyFields: ThingDirtyFields?
    static let fullRowDirtyFields: ThingDirtyFields = [.title, .dueDate, .completion, .deletion]

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case dueDate = "due_date"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case deletedAt = "deleted_at"
        case clientID = "client_id"
    }

    init(thing: Thing, userID: UUID, clientID: UUID, forceFullRow: Bool = false) {
        id = thing.id
        self.userID = userID
        title = thing.title
        dueDate = thing.dueDate
        isCompleted = thing.isCompleted
        completedAt = thing.completedAt
        deletedAt = thing.syncDeletedAt
        self.clientID = clientID
        dirtyFields = forceFullRow ? Self.fullRowDirtyFields : Self.dirtyFields(for: thing)
    }

    var encodesFullRow: Bool {
        (dirtyFields ?? Self.fullRowDirtyFields).isSuperset(of: Self.fullRowDirtyFields)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let fields = dirtyFields ?? Self.fullRowDirtyFields

        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        if encodesFullRow || fields.contains(.title) {
            try container.encode(title, forKey: .title)
        }
        if encodesFullRow || fields.contains(.dueDate) {
            try container.encodeSyncDateOnly(dueDate, forKey: .dueDate)
        }
        if encodesFullRow || fields.contains(.completion) {
            try container.encode(isCompleted, forKey: .isCompleted)
            try container.encode(completedAt, forKey: .completedAt)
        }
        if encodesFullRow || fields.contains(.deletion) {
            try container.encode(deletedAt, forKey: .deletedAt)
        }
        try container.encode(clientID, forKey: .clientID)
    }

    private static func dirtyFields(for thing: Thing) -> ThingDirtyFields {
        guard thing.syncRemoteUpdatedAt != nil else {
            return Self.fullRowDirtyFields
        }

        var fields: ThingDirtyFields = []
        if thing.syncTitleUpdatedAt != nil {
            fields.insert(.title)
        }
        if thing.syncDueDateUpdatedAt != nil {
            fields.insert(.dueDate)
        }
        if thing.syncCompletionUpdatedAt != nil {
            fields.insert(.completion)
        }
        if thing.syncDeletionUpdatedAt != nil || thing.syncDeletedAt != nil {
            fields.insert(.deletion)
        }
        return fields.isEmpty ? Self.fullRowDirtyFields : fields
    }
}

struct SyncThingRecord: Codable, Equatable, SyncRemoteRecord {
    var id: UUID
    var userID: UUID
    var title: String
    var dueDate: Date
    var isCompleted: Bool
    var completedAt: Date?
    var updatedAt: Date
    var deletedAt: Date?
    var clientID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case dueDate = "due_date"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case clientID = "client_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        title = try container.decode(String.self, forKey: .title)
        dueDate = try container.decodeSyncDateOnly(forKey: .dueDate)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        completedAt = try container.decodeSyncOptionalTimestamp(forKey: .completedAt)
        updatedAt = try container.decodeSyncTimestamp(forKey: .updatedAt)
        deletedAt = try container.decodeSyncOptionalTimestamp(forKey: .deletedAt)
        clientID = try container.decode(UUID.self, forKey: .clientID)
    }

    func makeThing() throws -> Thing {
        let validatedTitle = try validatedTitle()
        return Thing(
            id: id,
            title: validatedTitle,
            dueDate: dueDate,
            isCompleted: isCompleted,
            completedAt: completedAt,
            syncUpdatedAt: updatedAt,
            syncDeletedAt: deletedAt,
            syncRemoteUpdatedAt: updatedAt,
            syncNeedsPush: false
        )
    }

    func apply(to thing: Thing) throws {
        let validatedTitle = try validatedTitle()
        if thing.syncTitleUpdatedAt == nil {
            thing.title = validatedTitle
        }
        if thing.syncDueDateUpdatedAt == nil {
            thing.dueDate = dueDate
        }
        if thing.syncCompletionUpdatedAt == nil {
            thing.isCompleted = isCompleted
            thing.completedAt = completedAt
        }
        if thing.syncDeletionUpdatedAt == nil {
            thing.syncDeletedAt = deletedAt
        }
    }

    private func validatedTitle() throws -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, trimmedTitle.count <= Thing.maxTitleLength else {
            throw SyncServiceError.invalidRemoteThing("title is empty or too long")
        }

        guard isCompleted == (completedAt != nil) else {
            throw SyncServiceError.invalidRemoteThing("completion state is inconsistent")
        }

        return trimmedTitle
    }
}
