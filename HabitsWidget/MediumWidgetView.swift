import SwiftUI
import WidgetKit

struct HabitsMediumWidget: Widget {
    let kind = "HabitsMediumWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HabitSelectionIntent.self,
            provider: HabitWidgetProvider()
        ) { entry in
            MediumWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Habit Detail")
        .description("Track a habit with streak info")
        .supportedFamilies([.systemMedium])
    }
}

struct MediumWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: HabitWidgetEntry

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(WidgetTheme.border(for: colorScheme), lineWidth: 5)
                    .frame(width: 60, height: 60)

                if !entry.isDueToday {
                    Text("OFF")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WidgetTheme.muted(for: colorScheme))
                } else if entry.timesToComplete == 1 {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 54))
                        .foregroundStyle(entry.isCompleted ? WidgetTheme.accent(for: colorScheme) : WidgetTheme.muted(for: colorScheme))
                } else {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(WidgetTheme.accent(for: colorScheme), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    Text("\(entry.completionCount)/\(entry.timesToComplete)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.habitName)
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)

                Label(streakText, systemImage: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WidgetTheme.tag(for: colorScheme))

                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(entry.isCompleted ? WidgetTheme.accent(for: colorScheme) : WidgetTheme.muted(for: colorScheme))
            }

            Spacer()
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

    private var streakText: String {
        "\(entry.streakDays) day\(entry.streakDays == 1 ? "" : "s") streak"
    }
}
