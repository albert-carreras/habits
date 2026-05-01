import SwiftData
import SwiftUI

struct CompletedThingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [SortDescriptor(\Thing.completedAt, order: .reverse), SortDescriptor(\Thing.title)]) private var things: [Thing]

    @State private var viewModel = ThingListViewModel()

    var body: some View {
        Group {
            if sections.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sections, id: \.day) { section in
                        Section(section.title) {
                            ForEach(section.things) { thing in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(thing.title)
                                        .font(.body)
                                        .foregroundStyle(AppTheme.text(for: colorScheme))
                                        .lineLimit(4)

                                    if let completedAt = thing.completedAt {
                                        Text(completedAt.formatted(date: .omitted, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.muted(for: colorScheme))
                                    }
                                }
                                .padding(.vertical, 4)
                                .accessibilityIdentifier("completed-thing-row-\(thing.id.uuidString)")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("Completed Things")
        .appInlineNavigationTitle()
        .accessibilityIdentifier("completed-things-view")
    }

    private var sections: [CompletedThingDaySection] {
        viewModel.completedThingSections(from: things)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 42, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.muted(for: colorScheme).opacity(0.72))

            Text("No Completed Things")
                .font(.headline.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.text(for: colorScheme))

            Text("Things you complete will appear here")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
