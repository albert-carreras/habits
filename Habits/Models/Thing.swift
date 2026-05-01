import Foundation
import SwiftData

@Model
final class Thing {
    static let maxTitleLength = 400

    var id: UUID
    var title: String
    var dueDate: Date
    var isCompleted: Bool
    var completedAt: Date?
    var syncUpdatedAt: Date?
    var syncDeletedAt: Date?
    var syncRemoteUpdatedAt: Date?
    var syncNeedsPush: Bool?
    var syncTitleUpdatedAt: Date?
    var syncDueDateUpdatedAt: Date?
    var syncCompletionUpdatedAt: Date?
    var syncDeletionUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date = .now,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        syncUpdatedAt: Date? = .now,
        syncDeletedAt: Date? = nil,
        syncRemoteUpdatedAt: Date? = nil,
        syncNeedsPush: Bool? = true,
        syncTitleUpdatedAt: Date? = nil,
        syncDueDateUpdatedAt: Date? = nil,
        syncCompletionUpdatedAt: Date? = nil,
        syncDeletionUpdatedAt: Date? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.title = title
        self.dueDate = calendar.startOfDay(for: dueDate)
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.syncUpdatedAt = syncUpdatedAt
        self.syncDeletedAt = syncDeletedAt
        self.syncRemoteUpdatedAt = syncRemoteUpdatedAt
        self.syncNeedsPush = syncNeedsPush
        self.syncTitleUpdatedAt = syncTitleUpdatedAt
        self.syncDueDateUpdatedAt = syncDueDateUpdatedAt
        self.syncCompletionUpdatedAt = syncCompletionUpdatedAt
        self.syncDeletionUpdatedAt = syncDeletionUpdatedAt
    }
}
