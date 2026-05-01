import Foundation
import CryptoKit
import SwiftData

@Model
final class HabitCompletion {
    var id: UUID
    var date: Date
    var periodStart: Date?
    var count: Int
    var syncUpdatedAt: Date?
    var syncDeletedAt: Date?
    var syncRemoteUpdatedAt: Date?
    var syncNeedsPush: Bool?
    var habit: Habit?

    init(
        id: UUID? = nil,
        date: Date = .now,
        periodStart: Date? = nil,
        count: Int = 1,
        habit: Habit? = nil,
        syncUpdatedAt: Date? = .now,
        syncDeletedAt: Date? = nil,
        syncRemoteUpdatedAt: Date? = nil,
        syncNeedsPush: Bool? = true
    ) {
        let resolvedPeriodStart = periodStart ?? Self.periodStart(for: date, habit: habit)
        self.id = id
            ?? habit.map { Self.deterministicID(habitID: $0.id, periodStart: resolvedPeriodStart) }
            ?? UUID()
        self.date = date
        self.periodStart = resolvedPeriodStart
        self.count = count
        self.syncUpdatedAt = syncUpdatedAt
        self.syncDeletedAt = syncDeletedAt
        self.syncRemoteUpdatedAt = syncRemoteUpdatedAt
        self.syncNeedsPush = syncNeedsPush
        self.habit = habit
    }

    static func periodStart(for date: Date, habit: Habit?, calendar: Calendar = .current) -> Date {
        DateHelpers.periodStart(
            for: date,
            frequency: habit?.frequency ?? .daily,
            customValue: habit?.customIntervalValue,
            customUnit: habit?.customIntervalUnit,
            habitStart: habit?.startDate ?? date
        )
    }

    static func deterministicID(habitID: UUID, periodStart: Date) -> UUID {
        let periodKey = String(Int64(periodStart.timeIntervalSinceReferenceDate.rounded()))
        let key = "\(habitID.uuidString.lowercased()):\(periodKey)"
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = uuid_t(
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: uuid)
    }
}
