import SwiftUI

struct ThingRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let thing: Thing
    let dueLabel: String
    let isOverdue: Bool
    let allowsToggle: Bool
    let showsDueLabel: Bool
    let onToggle: () -> Void

    static let completionIndicatorSize: CGFloat = 34

    private var completedCheckColor: Color {
        colorScheme == .dark
            ? AppTheme.success(for: colorScheme)
            : AppTheme.accent(for: colorScheme)
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(thing.title)
                        .font(.headline)
                        .foregroundStyle(thing.isCompleted ? AppTheme.muted(for: colorScheme) : AppTheme.text(for: colorScheme))
                        .lineLimit(8)

                    if showsDueLabel {
                        Text(dueLabel)
                            .font(.caption.weight(AppTheme.FontWeight.semibold))
                            .foregroundStyle(isOverdue ? AppTheme.danger(for: colorScheme) : AppTheme.muted(for: colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer()

                Image(systemName: thing.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: Self.completionIndicatorSize, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(thing.isCompleted ? completedCheckColor : AppTheme.muted(for: colorScheme).opacity(colorScheme == .dark ? 0.75 : 0.85))
                    .frame(width: Self.completionIndicatorSize, height: Self.completionIndicatorSize)
                    .contentTransition(.symbolEffect(.replace))
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
        .accessibilityIdentifier("thing-row-\(thing.id.uuidString)")
    }
}
