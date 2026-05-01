import Foundation

struct ThingWidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var things: [ThingWidgetItem]

    static let empty = ThingWidgetSnapshot(generatedAt: .distantPast, things: [])
}

struct ThingWidgetItem: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var dueDate: Date
    var isCompleted: Bool
}

enum ThingWidgetDataStore {
    static let appGroupIdentifier = "group.com.albertc.habits"

    private static let fileName = "thing-widget-snapshot.json"

    static func loadSnapshot() -> ThingWidgetSnapshot {
        guard let url = try? snapshotURL(), let data = try? Data(contentsOf: url) else {
            return .empty
        }

        return (try? JSONDecoder().decode(ThingWidgetSnapshot.self, from: data)) ?? .empty
    }

    static func saveSnapshot(_ snapshot: ThingWidgetSnapshot) throws {
        let url = try snapshotURL()
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    private static func snapshotURL() throws -> URL {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw ThingWidgetDataStoreError.appGroupUnavailable
        }

        try? fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        return containerURL.appendingPathComponent(fileName)
    }
}

enum ThingWidgetDataStoreError: Error {
    case appGroupUnavailable
}
