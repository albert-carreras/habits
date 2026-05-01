import SwiftUI
import WidgetKit

struct AddThingLockScreenWidget: Widget {
    let kind = "AddThingLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: AddThingProvider()
        ) { _ in
            AddThingLockScreenView()
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "com.albertc.habit://add-thing"))
        }
        .configurationDisplayName("Add Thing")
        .description("Quickly add a new thing")
        .supportedFamilies([.accessoryCircular])
    }
}

struct AddThingProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: .now)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct AddThingLockScreenView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
        }
    }
}
