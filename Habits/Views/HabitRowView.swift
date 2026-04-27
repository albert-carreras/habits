import SwiftUI

struct HabitRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let habit: Habit
    let completionCount: Int
    let isCompleted: Bool
    let frequencyLabel: String
    let scheduleLabel: String
    let onToggle: () -> Void

    static let completionIndicatorSize: CGFloat = 34
    static let completionCheckmarkSize: CGFloat = 14

    private var isCounter: Bool { habit.timesToComplete > 1 }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(habit.name)
                        .font(.headline)
                        .strikethrough(isCompleted, color: AppTheme.muted(for: colorScheme))
                        .foregroundStyle(isCompleted ? AppTheme.muted(for: colorScheme) : AppTheme.text(for: colorScheme))
                        .lineLimit(2)

                    metadata
                }

                Spacer()

                HStack(alignment: .center, spacing: 12) {
                    if isCounter {
                        Text("\(completionCount)/\(habit.timesToComplete)")
                            .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                            .foregroundStyle(isCompleted ? AppTheme.accent(for: colorScheme) : AppTheme.muted(for: colorScheme))
                            .monospacedDigit()
                    }

                    completionIndicator
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .softCard(
                colorScheme: colorScheme,
                in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous))
        }
        .buttonStyle(BouncyPressStyle(pressedScale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("habit-row-\(habit.name)")
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            Text(frequencyLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.muted(for: colorScheme))

            Text(scheduleLabel)
                .font(.caption.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.accent(for: colorScheme))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var completionIndicator: some View {
        if !isCounter {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: Self.completionIndicatorSize, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(isCompleted ? AppTheme.accent(for: colorScheme) : AppTheme.muted(for: colorScheme))
                .frame(width: Self.completionIndicatorSize, height: Self.completionIndicatorSize)
                .contentTransition(.symbolEffect(.replace))
        } else {
            ZStack {
                Circle()
                    .stroke(AppTheme.border(for: colorScheme), lineWidth: 3)
                    .frame(width: Self.completionIndicatorSize, height: Self.completionIndicatorSize)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AppTheme.accent(for: colorScheme), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: Self.completionIndicatorSize, height: Self.completionIndicatorSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: Self.completionCheckmarkSize, weight: AppTheme.FontWeight.bold))
                        .foregroundStyle(AppTheme.accent(for: colorScheme))
                }
            }
            .frame(width: Self.completionIndicatorSize, height: Self.completionIndicatorSize)
        }
    }

    private var progress: CGFloat {
        guard habit.timesToComplete > 0 else { return 0 }
        return min(1.0, CGFloat(completionCount) / CGFloat(habit.timesToComplete))
    }
}
