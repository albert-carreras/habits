import Foundation
import SwiftData
import Testing
@testable import Habits

@Suite("Supabase services")
struct SupabaseServiceTests {
    @Test("Supabase configuration points at the configured project")
    func configurationUsesProjectValues() {
        #expect(SupabaseConfiguration.url.absoluteString == "https://fzgoupebkrkjebogqmtb.supabase.co")
        #expect(SupabaseConfiguration.publishableKey == "sb_publishable_BUX0OwD7OQ5gn-WrgSE8pQ_wZOsj8DA")
        #expect(SupabaseConfiguration.redirectURL.absoluteString == "com.albertc.habit://auth-callback")
        #expect(SupabaseConfiguration.googleIOSClientID == "94500561889-nipnafo2ubg1td8icodvrnmltius33ud.apps.googleusercontent.com")
        #expect(SupabaseConfiguration.googleWebClientID == "94500561889-2ebd5mafvuouuq84ko0k6irdu8nh2v37.apps.googleusercontent.com")
    }

    @Test("Google iOS client ID matches the registered URL scheme")
    func googleClientIDMatchesURLScheme() {
        let reversedClientID = SupabaseConfiguration.googleIOSClientID
            .split(separator: ".")
            .reversed()
            .joined(separator: ".")

        #expect(reversedClientID == "com.googleusercontent.apps.94500561889-nipnafo2ubg1td8icodvrnmltius33ud")
    }

    @Test("Habit push payload omits server timestamp")
    func habitPushPayloadOmitsServerTimestamp() throws {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let clientID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let habit = Habit(
            name: "Read",
            frequency: .weekly,
            timesToComplete: 2,
            startDate: Date(timeIntervalSince1970: 1_777_000_000),
            createdAt: Date(timeIntervalSince1970: 1_777_000_001),
            syncUpdatedAt: Date(timeIntervalSince1970: 1_777_000_002)
        )
        let record = SyncHabitUpsert(habit: habit, userID: userID, clientID: clientID)

        let data = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["user_id"] != nil)
        #expect(object["created_at"] != nil)
        #expect(object["updated_at"] == nil)
        #expect(object["userID"] == nil)
        #expect(object["updatedAt"] == nil)
    }

    @Test("Completion and thing push payloads omit server timestamp")
    func completionAndThingPushPayloadsOmitServerTimestamp() throws {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let clientID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let habit = Habit(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, name: "Read")
        let completion = HabitCompletion(
            date: Date(timeIntervalSince1970: 1_777_000_000),
            count: 1,
            habit: habit,
            syncUpdatedAt: Date(timeIntervalSince1970: 1_777_000_001)
        )
        let thing = Thing(
            title: "Buy milk",
            dueDate: Date(timeIntervalSince1970: 1_777_000_002),
            syncUpdatedAt: Date(timeIntervalSince1970: 1_777_000_003)
        )

        let completionRecord = try #require(SyncCompletionUpsert(completion: completion, userID: userID, clientID: clientID))
        let completionData = try JSONEncoder().encode(completionRecord)
        let completionObject = try #require(JSONSerialization.jsonObject(with: completionData) as? [String: Any])
        #expect(completionObject["updated_at"] == nil)
        #expect(completionObject["created_at"] != nil)

        let thingData = try JSONEncoder().encode(SyncThingUpsert(thing: thing, userID: userID, clientID: clientID))
        let thingObject = try #require(JSONSerialization.jsonObject(with: thingData) as? [String: Any])
        #expect(thingObject["updated_at"] == nil)
        #expect(thingObject["due_date"] != nil)
        #expect(thingObject["completed_at"] is NSNull)
        #expect(thingObject["deleted_at"] is NSNull)
    }

    @Test("Thing push payload encodes only locally changed fields for synced rows")
    func thingPushPayloadEncodesOnlyLocallyChangedFields() throws {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let clientID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let remoteUpdatedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let dirtyAt = Date(timeIntervalSince1970: 1_777_000_010)
        let thing = Thing(
            title: "Renamed elsewhere",
            dueDate: Date(timeIntervalSince1970: 1_777_000_020),
            isCompleted: false,
            completedAt: nil,
            syncUpdatedAt: dirtyAt,
            syncRemoteUpdatedAt: remoteUpdatedAt,
            syncNeedsPush: true,
            syncTitleUpdatedAt: dirtyAt
        )

        let data = try JSONEncoder().encode(SyncThingUpsert(thing: thing, userID: userID, clientID: clientID))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(!SyncThingUpsert(thing: thing, userID: userID, clientID: clientID).encodesFullRow)
        #expect(object["title"] as? String == "Renamed elsewhere")
        #expect(object["due_date"] == nil)
        #expect(object["is_completed"] == nil)
        #expect(object["completed_at"] == nil)
        #expect(object["deleted_at"] == nil)
        #expect(object["client_id"] != nil)
    }

    @Test("Unsynced thing push payload encodes a full row even with field dirty markers")
    func unsyncedThingPushPayloadEncodesFullRow() throws {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let clientID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let dirtyAt = Date(timeIntervalSince1970: 1_777_000_010)
        let thing = Thing(
            title: "Draft",
            isCompleted: false,
            completedAt: nil,
            syncUpdatedAt: dirtyAt,
            syncRemoteUpdatedAt: nil,
            syncNeedsPush: true,
            syncTitleUpdatedAt: dirtyAt
        )

        let data = try JSONEncoder().encode(SyncThingUpsert(thing: thing, userID: userID, clientID: clientID))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(SyncThingUpsert(thing: thing, userID: userID, clientID: clientID).encodesFullRow)
        #expect(object["title"] as? String == "Draft")
        #expect(object["due_date"] != nil)
        #expect(object["is_completed"] as? Bool == false)
        #expect(object["completed_at"] is NSNull)
        #expect(object["deleted_at"] is NSNull)
    }

    @Test("Thing completion push encodes null completedAt when reopening")
    func thingCompletionPushEncodesNullCompletedAt() throws {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let clientID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let dirtyAt = Date(timeIntervalSince1970: 1_777_000_010)
        let thing = Thing(
            title: "Pay bill",
            isCompleted: false,
            completedAt: nil,
            syncUpdatedAt: dirtyAt,
            syncRemoteUpdatedAt: Date(timeIntervalSince1970: 1_777_000_000),
            syncNeedsPush: true,
            syncCompletionUpdatedAt: dirtyAt
        )

        let data = try JSONEncoder().encode(SyncThingUpsert(thing: thing, userID: userID, clientID: clientID))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(!SyncThingUpsert(thing: thing, userID: userID, clientID: clientID).encodesFullRow)
        #expect(object["title"] == nil)
        #expect(object["is_completed"] as? Bool == false)
        #expect(object["completed_at"] is NSNull)
        #expect(object["deleted_at"] == nil)
    }

    @Test("Forced full thing payload includes non-null fields for upsert fallback")
    func forcedFullThingPayloadIncludesNonNullFields() throws {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let clientID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let dirtyAt = Date(timeIntervalSince1970: 1_777_000_010)
        let thing = Thing(
            title: "Pay bill",
            isCompleted: false,
            completedAt: nil,
            syncUpdatedAt: dirtyAt,
            syncRemoteUpdatedAt: Date(timeIntervalSince1970: 1_777_000_000),
            syncNeedsPush: true,
            syncCompletionUpdatedAt: dirtyAt
        )

        let record = SyncThingUpsert(thing: thing, userID: userID, clientID: clientID, forceFullRow: true)
        let data = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(record.encodesFullRow)
        #expect(object["title"] as? String == "Pay bill")
        #expect(object["due_date"] != nil)
        #expect(object["is_completed"] as? Bool == false)
        #expect(object["completed_at"] is NSNull)
        #expect(object["deleted_at"] is NSNull)
    }

    @Test("Sync push payloads encode Postgres date columns as date-only strings")
    func syncPushPayloadsEncodeDateOnlyColumns() throws {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let clientID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let calendar = Calendar.current
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 29, hour: 10)))
        let habit = Habit(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, name: "Read", startDate: date)
        let completion = HabitCompletion(date: date, periodStart: date, count: 1, habit: habit)
        let thing = Thing(title: "Buy milk", dueDate: date)

        let habitData = try JSONEncoder().encode(SyncHabitUpsert(habit: habit, userID: userID, clientID: clientID))
        let habitObject = try #require(JSONSerialization.jsonObject(with: habitData) as? [String: Any])
        #expect(habitObject["start_date"] as? String == "2026-04-29")

        let completionRecord = try #require(SyncCompletionUpsert(completion: completion, userID: userID, clientID: clientID))
        let completionData = try JSONEncoder().encode(completionRecord)
        let completionObject = try #require(JSONSerialization.jsonObject(with: completionData) as? [String: Any])
        #expect(completionObject["period_start"] as? String == "2026-04-29")

        let thingData = try JSONEncoder().encode(SyncThingUpsert(thing: thing, userID: userID, clientID: clientID))
        let thingObject = try #require(JSONSerialization.jsonObject(with: thingData) as? [String: Any])
        #expect(thingObject["due_date"] as? String == "2026-04-29")
    }

    @Test("Sync records decode Supabase date and timestamp formats")
    func syncRecordsDecodeSupabaseDateAndTimestampFormats() throws {
        let habitData = try #require("""
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "user_id": "11111111-1111-1111-1111-111111111111",
          "name": "Read",
          "frequency": "Daily",
          "custom_interval_value": null,
          "custom_interval_unit": null,
          "times_to_complete": 1,
          "start_date": "2026-04-29",
          "notifications_enabled": false,
          "notification_hour": null,
          "notification_minute": null,
          "created_at": "2026-04-29T08:00:00+00:00",
          "updated_at": "2026-04-29T08:01:02.123456+00:00",
          "deleted_at": null,
          "client_id": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8))
        let completionData = try #require("""
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "user_id": "11111111-1111-1111-1111-111111111111",
          "habit_id": "33333333-3333-3333-3333-333333333333",
          "period_start": "2026-04-29",
          "date": "2026-04-29T08:02:00+00:00",
          "count": 2,
          "created_at": "2026-04-29T08:02:00+00:00",
          "updated_at": "2026-04-29T08:03:00.123456+00:00",
          "deleted_at": null,
          "client_id": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8))
        let thingData = try #require("""
        {
          "id": "55555555-5555-5555-5555-555555555555",
          "user_id": "11111111-1111-1111-1111-111111111111",
          "title": "Buy milk",
          "due_date": "2026-04-29",
          "is_completed": true,
          "completed_at": "2026-04-29T08:04:00+00:00",
          "updated_at": "2026-04-29T08:05:00.123456+00:00",
          "deleted_at": null,
          "client_id": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8))

        let decoder = JSONDecoder()
        let habit = try decoder.decode(SyncHabitRecord.self, from: habitData)
        let completion = try decoder.decode(SyncCompletionRecord.self, from: completionData)
        let thing = try decoder.decode(SyncThingRecord.self, from: thingData)

        #expect(Self.yearMonthDay(for: habit.startDate) == [2026, 4, 29])
        #expect(Self.yearMonthDay(for: completion.periodStart) == [2026, 4, 29])
        #expect(Self.yearMonthDay(for: thing.dueDate) == [2026, 4, 29])
        #expect(habit.updatedAt.timeIntervalSince1970 > habit.createdAt.timeIntervalSince1970)
        #expect(completion.updatedAt.timeIntervalSince1970 > completion.createdAt.timeIntervalSince1970)
        #expect(thing.completedAt != nil)
    }

    @Test("Thing remote apply preserves locally dirty fields")
    @MainActor
    func thingRemoteApplyPreservesLocallyDirtyFields() throws {
        let dirtyAt = Date(timeIntervalSince1970: 1_777_000_010)
        let local = Thing(
            title: "Local rename",
            isCompleted: false,
            completedAt: nil,
            syncUpdatedAt: dirtyAt,
            syncRemoteUpdatedAt: Date(timeIntervalSince1970: 1_777_000_000),
            syncNeedsPush: true,
            syncTitleUpdatedAt: dirtyAt
        )
        let remoteData = try #require("""
        {
          "id": "\(local.id.uuidString)",
          "user_id": "11111111-1111-1111-1111-111111111111",
          "title": "Remote title",
          "due_date": "2026-04-29",
          "is_completed": true,
          "completed_at": "2026-04-29T08:04:00+00:00",
          "updated_at": "2026-04-29T08:05:00+00:00",
          "deleted_at": null,
          "client_id": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8))
        let remote = try JSONDecoder().decode(SyncThingRecord.self, from: remoteData)

        try remote.apply(to: local)

        #expect(local.title == "Local rename")
        #expect(local.isCompleted)
        #expect(local.completedAt != nil)
        #expect(SyncService.hasPendingThingFieldEdits(local))
    }

    @Test("Account deletion response decodes API contract")
    func accountDeletionResponseDecodesContract() throws {
        let data = try #require(#"{ "deleted": true }"#.data(using: .utf8))

        let response = try JSONDecoder().decode(AccountDeletionResponse.self, from: data)

        #expect(response == AccountDeletionResponse(deleted: true))
    }

    @Test("Account deletion request uses DELETE and bearer token")
    func accountDeletionRequestUsesDeleteAndBearerToken() throws {
        let request = SupabaseAccountDeletionService.makeRequest(accessToken: "test-access-token")

        #expect(request.url?.absoluteString == "https://fzgoupebkrkjebogqmtb.supabase.co/functions/v1/delete-account")
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
        #expect(request.value(forHTTPHeaderField: "apikey") == SupabaseConfiguration.publishableKey)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Sync dirty acknowledgement preserves newer local edits")
    @MainActor
    func dirtyAcknowledgementChecksLocalTimestamp() {
        let pushedAt = Date(timeIntervalSince1970: 100)

        #expect(SyncService.shouldClearDirty(localUpdatedAt: pushedAt, pushedAt: pushedAt))
        #expect(SyncService.shouldClearDirty(localUpdatedAt: Date(timeIntervalSince1970: 99), pushedAt: pushedAt))
        #expect(!SyncService.shouldClearDirty(localUpdatedAt: Date(timeIntervalSince1970: 101), pushedAt: pushedAt))
    }

    @Test("Last successful sync timestamp is scoped by user")
    @MainActor
    func lastSuccessfulSyncTimestampIsScopedByUser() {
        let userA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let userB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let syncedAt = Date(timeIntervalSince1970: 1_777_000_100)

        UserDefaults.standard.removeObject(forKey: SyncService.lastSuccessfulSyncKey(userID: userA))
        UserDefaults.standard.removeObject(forKey: SyncService.lastSuccessfulSyncKey(userID: userB))

        SyncService.recordSuccessfulSync(userID: userA, at: syncedAt)

        #expect(SyncService.lastSuccessfulSyncAt(userID: userA) == syncedAt)
        #expect(SyncService.lastSuccessfulSyncAt(userID: userB) == nil)
        #expect(SyncService.lastSuccessfulSyncAt(userID: nil) == nil)

        UserDefaults.standard.removeObject(forKey: SyncService.lastSuccessfulSyncKey(userID: userA))
    }

    @Test("Sync account guard rejects stale scheduled work")
    @MainActor
    func syncAccountGuardRejectsStaleScheduledWork() {
        let userA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let userB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        #expect(SyncService.isExpectedSyncUser(actualUserID: userA, expectedUserID: nil))
        #expect(SyncService.isExpectedSyncUser(actualUserID: userA, expectedUserID: userA))
        #expect(!SyncService.isExpectedSyncUser(actualUserID: userB, expectedUserID: userA))
    }

    @Test("Sync skips own remote echo while local row is still dirty")
    @MainActor
    func syncSkipsOwnRemoteEchoForDirtyRows() {
        let localClientID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let otherClientID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        #expect(SyncService.shouldSkipOwnRemoteEcho(
            remoteClientID: localClientID,
            localClientID: localClientID,
            localNeedsPush: true
        ))
        #expect(SyncService.shouldSkipOwnRemoteEcho(
            remoteClientID: localClientID,
            localClientID: localClientID,
            localNeedsPush: nil
        ))
        #expect(!SyncService.shouldSkipOwnRemoteEcho(
            remoteClientID: localClientID,
            localClientID: localClientID,
            localNeedsPush: false
        ))
        #expect(!SyncService.shouldSkipOwnRemoteEcho(
            remoteClientID: otherClientID,
            localClientID: localClientID,
            localNeedsPush: true
        ))
    }

    @Test("Completion conflict key matches local and remote period identity")
    @MainActor
    func completionConflictKeyMatchesRemotePeriodIdentity() throws {
        let habitID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let clientID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let periodStart = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 29)))
        let habit = Habit(id: habitID, name: "Read")
        let local = HabitCompletion(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            date: periodStart,
            periodStart: periodStart,
            count: 1,
            habit: habit
        )
        let remote = SyncCompletionRecord(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            userID: userID,
            habitID: habitID,
            periodStart: periodStart,
            date: periodStart,
            count: 1,
            createdAt: periodStart,
            updatedAt: Date(timeIntervalSince1970: 1_777_000_000),
            deletedAt: nil,
            clientID: clientID
        )

        #expect(local.id != remote.id)
        #expect(SyncService.completionConflictKey(for: local) == remote.conflictKey)
    }

    @Test("Sync cursor advances by updatedAt then id")
    @MainActor
    func cursorAdvancesWithTimestampAndID() {
        let lowID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let highID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let timestamp = Date(timeIntervalSince1970: 100)
        let cursor = SyncCursor(updatedAt: timestamp, id: lowID)

        #expect(SyncService.cursorAdvanced(from: nil, with: timestamp, id: lowID) == cursor)
        #expect(SyncService.cursorAdvanced(from: cursor, with: timestamp, id: highID).id == highID)
        #expect(SyncService.cursorAdvanced(from: cursor, with: timestamp, id: lowID) == cursor)
        #expect(SyncService.cursorAdvanced(from: cursor, with: Date(timeIntervalSince1970: 101), id: lowID).updatedAt == Date(timeIntervalSince1970: 101))
    }

    @Test("Pending local data decision suppresses sync entry points")
    @MainActor
    func pendingLocalDataDecisionSuppressesSyncEntryPoints() async throws {
        let context = try makeContext()

        SyncService.clearLocalDataDecisionRequirement()
        SyncService.requireLocalDataDecision()

        #expect(SyncService.requiresLocalDataDecision)
        #expect(try await SyncService.syncIfStale(context: context) == SyncServiceResult(pushedCount: 0, pulledCount: 0))
        #expect(try await SyncService.forceSync(context: context) == SyncServiceResult(pushedCount: 0, pulledCount: 0))
        #expect(try await SyncService.pushDirtyRows(context: context) == 0)

        SyncService.clearLocalDataDecisionRequirement()
        #expect(!SyncService.requiresLocalDataDecision)
    }

    @Test("Preparing local data for account merge uploads visible rows and drops tombstones")
    @MainActor
    func preparingLocalDataForAccountMerge() throws {
        let context = try makeContext()
        let remoteTimestamp = Date(timeIntervalSince1970: 100)
        let mergeTimestamp = Date(timeIntervalSince1970: 200)
        let activeHabit = Habit(
            name: "Read",
            syncUpdatedAt: remoteTimestamp,
            syncRemoteUpdatedAt: remoteTimestamp,
            syncNeedsPush: false
        )
        let deletedHabit = Habit(name: "Deleted", syncDeletedAt: remoteTimestamp, syncNeedsPush: true)
        let activeCompletion = HabitCompletion(
            date: Date(timeIntervalSince1970: 10),
            count: 1,
            habit: activeHabit,
            syncUpdatedAt: remoteTimestamp,
            syncRemoteUpdatedAt: remoteTimestamp,
            syncNeedsPush: false
        )
        let deletedCompletion = HabitCompletion(
            date: Date(timeIntervalSince1970: 11),
            count: 1,
            habit: activeHabit,
            syncDeletedAt: remoteTimestamp,
            syncNeedsPush: true
        )
        let activeThing = Thing(
            title: "Buy milk",
            syncUpdatedAt: remoteTimestamp,
            syncRemoteUpdatedAt: remoteTimestamp,
            syncNeedsPush: false
        )
        let deletedThing = Thing(title: "Deleted thing", syncDeletedAt: remoteTimestamp, syncNeedsPush: true)
        context.insert(activeHabit)
        context.insert(deletedHabit)
        context.insert(activeCompletion)
        context.insert(deletedCompletion)
        context.insert(activeThing)
        context.insert(deletedThing)
        try context.save()

        try SyncService.prepareLocalDataForAccountMerge(context: context, at: mergeTimestamp)

        let habits = try context.fetch(FetchDescriptor<Habit>())
        let completions = try context.fetch(FetchDescriptor<HabitCompletion>())
        let things = try context.fetch(FetchDescriptor<Thing>())
        #expect(habits.map(\.name).sorted() == ["Read"])
        #expect(completions.count == 1)
        #expect(things.map(\.title).sorted() == ["Buy milk"])
        #expect(activeHabit.syncUpdatedAt == mergeTimestamp)
        #expect(activeHabit.syncRemoteUpdatedAt == nil)
        #expect(activeHabit.syncNeedsPush == true)
        #expect(activeCompletion.syncUpdatedAt == mergeTimestamp)
        #expect(activeCompletion.syncRemoteUpdatedAt == nil)
        #expect(activeCompletion.syncNeedsPush == true)
        #expect(activeThing.syncUpdatedAt == mergeTimestamp)
        #expect(activeThing.syncRemoteUpdatedAt == nil)
        #expect(activeThing.syncNeedsPush == true)
    }

    @Test("Invalid remote habit records are rejected instead of coerced")
    func invalidRemoteHabitRecordsAreRejected() throws {
        let habitData = try #require("""
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "user_id": "11111111-1111-1111-1111-111111111111",
          "name": "Read",
          "frequency": "Not a frequency",
          "custom_interval_value": null,
          "custom_interval_unit": null,
          "times_to_complete": 1,
          "start_date": "2026-04-29",
          "notifications_enabled": false,
          "notification_hour": null,
          "notification_minute": null,
          "created_at": "2026-04-29T08:00:00+00:00",
          "updated_at": "2026-04-29T08:01:02+00:00",
          "deleted_at": null,
          "client_id": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8))
        let remote = try JSONDecoder().decode(SyncHabitRecord.self, from: habitData)

        var didThrow = false
        do {
            _ = try remote.makeHabit()
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test("Valid remote records create local models")
    func validRemoteRecordsCreateLocalModels() throws {
        let habitData = try #require("""
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "user_id": "11111111-1111-1111-1111-111111111111",
          "name": "  Read  ",
          "frequency": "Custom",
          "custom_interval_value": 2,
          "custom_interval_unit": "Weeks",
          "times_to_complete": 3,
          "start_date": "2026-04-29",
          "notifications_enabled": true,
          "notification_hour": 8,
          "notification_minute": 30,
          "created_at": "2026-04-29T08:00:00+00:00",
          "updated_at": "2026-04-29T08:01:02+00:00",
          "deleted_at": null,
          "client_id": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8))
        let thingData = try #require("""
        {
          "id": "55555555-5555-5555-5555-555555555555",
          "user_id": "11111111-1111-1111-1111-111111111111",
          "title": "  Buy milk  ",
          "due_date": "2026-04-30",
          "is_completed": true,
          "completed_at": "2026-04-29T09:00:00+00:00",
          "updated_at": "2026-04-29T09:05:00+00:00",
          "deleted_at": null,
          "client_id": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8))

        let habit = try JSONDecoder().decode(SyncHabitRecord.self, from: habitData).makeHabit()
        let thing = try JSONDecoder().decode(SyncThingRecord.self, from: thingData).makeThing()

        #expect(habit.id == UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        #expect(habit.name == "Read")
        #expect(habit.frequency == .custom)
        #expect(habit.customIntervalValue == 2)
        #expect(habit.customIntervalUnit == .weeks)
        #expect(habit.timesToComplete == 3)
        #expect(habit.notificationsEnabled)
        #expect(habit.notificationHour == 8)
        #expect(habit.notificationMinute == 30)
        #expect(habit.syncUpdatedAt == habit.syncRemoteUpdatedAt)
        #expect(habit.syncNeedsPush == false)

        #expect(thing.id == UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
        #expect(thing.title == "Buy milk")
        #expect(thing.isCompleted)
        #expect(thing.completedAt != nil)
        #expect(thing.syncUpdatedAt == thing.syncRemoteUpdatedAt)
        #expect(thing.syncNeedsPush == false)
    }

    @Test("Invalid remote thing records are rejected instead of imported")
    func invalidRemoteThingRecordsAreRejected() throws {
        let thingData = try #require("""
        {
          "id": "55555555-5555-5555-5555-555555555555",
          "user_id": "11111111-1111-1111-1111-111111111111",
          "title": "   ",
          "due_date": "2026-04-29",
          "is_completed": true,
          "completed_at": null,
          "updated_at": "2026-04-29T08:05:00+00:00",
          "deleted_at": null,
          "client_id": "22222222-2222-2222-2222-222222222222"
        }
        """.data(using: .utf8))
        let remote = try JSONDecoder().decode(SyncThingRecord.self, from: thingData)

        var didThrow = false
        do {
            _ = try remote.makeThing()
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Habit.self, HabitCompletion.self, Thing.self, configurations: config)
        return ModelContext(container)
    }

    private static func yearMonthDay(for date: Date) -> [Int] {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return [components.year ?? 0, components.month ?? 0, components.day ?? 0]
    }
}
