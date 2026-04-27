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
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(WidgetTheme.border(for: colorScheme), lineWidth: 4)
                    .frame(width: 50, height: 50)

                if !entry.isDueToday {
                    Text("OFF")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WidgetTheme.muted(for: colorScheme))
                } else if entry.timesToComplete == 1 {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 44))
                        .foregroundStyle(entry.isCompleted ? WidgetTheme.accent(for: colorScheme) : WidgetTheme.muted(for: colorScheme))
                } else {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(WidgetTheme.accent(for: colorScheme), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))

                    Text("\(entry.completionCount)")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                }
            }

            Text(entry.habitName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(entry.isCompleted ? WidgetTheme.accent(for: colorScheme) : WidgetTheme.muted(for: colorScheme))
                .lineLimit(1)
        }
        .padding()
    }

    private var progress: CGFloat {
        guard entry.timesToComplete > 0 else { return 0 }
        return min(CGFloat(entry.completionCount) / CGFloat(entry.timesToComplete), 1)
    }

    private var statusText: String {
        guard entry.isDueToday else { return "Day off" }
        return "\(entry.completionCount)/\(entry.timesToComplete)"
    }
}
