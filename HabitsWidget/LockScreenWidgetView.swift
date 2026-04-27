import SwiftUI
import WidgetKit

struct HabitsLockScreenWidget: Widget {
    let kind = "HabitsLockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HabitSelectionIntent.self,
            provider: HabitWidgetProvider()
        ) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Habit Lock Screen")
        .description("Show a habit's current progress on the Lock Screen")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: HabitWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 2) {
                Text(initials)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)

                Text(progressText)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.habitName)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                Text(progressText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(entry.isCompleted ? WidgetTheme.accent(for: colorScheme) : WidgetTheme.muted(for: colorScheme))
            }
        }
    }

    private var progressText: String {
        guard entry.isDueToday else { return "Day off" }
        return "\(entry.completionCount)/\(entry.timesToComplete)"
    }

    private var initials: String {
        let words = entry.habitName.split(separator: " ")
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "H" : String(letters).uppercased()
    }
}
