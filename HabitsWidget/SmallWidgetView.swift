import SwiftUI
import WidgetKit

struct HabitsSmallWidget: Widget {
    let kind = "HabitsSmallWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HabitSelectionIntent.self,
            provider: HabitWidgetProvider()
        ) { entry in
            SmallWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Habit")
        .description("Track a single habit")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: HabitWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetTheme.accent(for: colorScheme))

                Text(entry.habitName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetTheme.accent(for: colorScheme))
                    .textCase(.uppercase)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(WidgetTheme.border(for: colorScheme), lineWidth: 5)
                    .frame(width: 64, height: 64)

                if !entry.isDueToday {
                    Text("OFF")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WidgetTheme.muted(for: colorScheme))
                } else if entry.timesToComplete == 1 {
                    Image(systemName: entry.isCompleted ? "checkmark" : "")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(WidgetTheme.accent(for: colorScheme))
                } else {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(WidgetTheme.accent(for: colorScheme), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))

                    Text("\(entry.completionCount)")
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)

            Text(statusText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(entry.isCompleted ? WidgetTheme.accent(for: colorScheme) : WidgetTheme.muted(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
    }

    private var progress: CGFloat {
        guard entry.timesToComplete > 0 else { return 0 }
        return min(CGFloat(entry.completionCount) / CGFloat(entry.timesToComplete), 1)
    }

    private var statusText: String {
        guard entry.isDueToday else { return "Day off" }
        if entry.isCompleted { return "Done" }
        return "\(entry.completionCount) of \(entry.timesToComplete)"
    }
}
