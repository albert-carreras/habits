import SwiftUI

struct HabitRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let habit: Habit
    let completionCount: Int
    let isCompleted: Bool
    let frequencyLabel: String
    let scheduleLabel: String
    let showsScheduleLabel: Bool
    let onToggle: () -> Void

    static let completionIndicatorSize: CGFloat = 34
    static let ringDiameter: CGFloat = 30
    static let ringLineWidth: CGFloat = 3

    private var isCounter: Bool { habit.timesToComplete > 1 }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(habit.name)
                        .font(.headline)
                        .foregroundStyle(isCompleted ? AppTheme.muted(for: colorScheme) : AppTheme.text(for: colorScheme))
                        .lineLimit(8)

                    metadata
                }

                Spacer()

                if isCounter && !isCompleted {
                    Text("\(completionCount)/\(habit.timesToComplete)")
                        .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.muted(for: colorScheme))
                        .monospacedDigit()
                }

                completionIndicator
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .softCard(
                colorScheme: colorScheme,
                in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("habit-row-\(habit.name)")
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            Text(frequencyLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.muted(for: colorScheme))

            if showsScheduleLabel {
                Text(scheduleLabel)
                    .font(.caption.weight(AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.muted(for: colorScheme))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var completedCheckColor: Color {
        colorScheme == .dark
            ? AppTheme.success(for: colorScheme)
            : AppTheme.accent(for: colorScheme)
    }

    @ViewBuilder
    private var completionIndicator: some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Self.completionIndicatorSize, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(completedCheckColor)
                .frame(width: Self.completionIndicatorSize, height: Self.completionIndicatorSize)
                .contentTransition(.symbolEffect(.replace))
        } else {
            ZStack {
                Circle()
                    .stroke(AppTheme.muted(for: colorScheme).opacity(colorScheme == .dark ? 0.75 : 0.85), lineWidth: Self.ringLineWidth)

                if isCounter {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(completedCheckColor, style: StrokeStyle(lineWidth: Self.ringLineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(width: Self.ringDiameter, height: Self.ringDiameter)
            .frame(width: Self.completionIndicatorSize, height: Self.completionIndicatorSize)
        }
    }

    private var progress: CGFloat {
        guard habit.timesToComplete > 0 else { return 0 }
        return min(1.0, CGFloat(completionCount) / CGFloat(habit.timesToComplete))
    }
}
