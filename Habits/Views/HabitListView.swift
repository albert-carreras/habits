import SwiftUI
import SwiftData

struct HabitListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Habit.name) private var habits: [Habit]
    @State private var viewModel = HabitListViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    todayHeader
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .background(AppTheme.background(for: colorScheme))

                    if habits.isEmpty {
                        emptyState
                    } else {
                        habitList
                    }
                }

                addButton
                    .padding(.trailing, 22)
                    .padding(.bottom, 22)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $viewModel.showingAddSheet) {
                HabitFormView()
            }
            .sheet(item: $viewModel.habitToEdit) { habit in
                HabitFormView(habit: habit)
            }
            .alert("Delete Habit", isPresented: $viewModel.showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let habit = viewModel.habitToDelete {
                        withAnimation {
                            viewModel.deleteHabit(habit, context: modelContext)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let habit = viewModel.habitToDelete {
                    Text("Are you sure you want to delete \"\(habit.name)\"? This cannot be undone.")
                }
            }
            .onAppear {
                HabitWidgetSyncService.sync(habits: habits)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Habits", systemImage: "leaf")
        } description: {
            Text("Tap + to create your first habit")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(AppTheme.muted(for: colorScheme))
    }

    private var todayHeader: some View {
        let now = Date.now
        let weekday = now.formatted(.dateTime.weekday(.wide))
        let dayMonth = now.formatted(.dateTime.day().month(.wide))
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(weekday)
                .font(.title2.weight(.regular))
                .foregroundStyle(AppTheme.muted(for: colorScheme))
            Text(dayMonth)
                .font(.title.weight(AppTheme.FontWeight.bold))
                .foregroundStyle(AppTheme.text(for: colorScheme))
        }
    }

    private var completionSummary: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(AppTheme.accent(for: colorScheme))
                .frame(width: 9, height: 9)

            Text(completionSummaryText)
                .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.accent(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .softCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous),
            tint: AppTheme.accentSoft(for: colorScheme)
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: completedHabitCount)
        .accessibilityIdentifier("completion-summary")
    }

    private var addButton: some View {
        Button {
            viewModel.showingAddSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.accentForeground(for: colorScheme))
                .frame(width: 56, height: 56)
                .liquidGlass(
                    colorScheme: colorScheme,
                    in: Circle(),
                    tint: AppTheme.accent(for: colorScheme),
                    fillOpacity: colorScheme == .dark ? 0.68 : 0.82,
                    interactive: true
                )
        }
        .buttonStyle(BouncyPressStyle())
        .accessibilityLabel("Add habit")
        .accessibilityIdentifier("add-habit-button")
    }

    private var habitList: some View {
        List {
            Section {
                completionSummary
                    .listRowSeparator(.hidden)
                    .listRowBackground(AppTheme.background(for: colorScheme))
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
            }

            if !todaysHabits.isEmpty {
                Section {
                    ForEach(todaysHabits) { habit in
                        habitRow(for: habit, allowsLogging: true)
                    }
                } header: {
                    sectionHeader("Today")
                }
            }

            if !laterHabits.isEmpty {
                Section {
                    ForEach(laterHabits) { habit in
                        habitRow(for: habit, allowsLogging: false)
                    }
                } header: {
                    sectionHeader("Later")
                        .padding(.top, todaysHabits.isEmpty ? 0 : 12)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .contentMargins(.bottom, 130)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(AppTheme.FontWeight.semibold))
            .foregroundStyle(AppTheme.muted(for: colorScheme))
            .textCase(.uppercase)
    }

    private var completedHabitCount: Int {
        todaysHabits.filter { viewModel.isCompleted(habit: $0) }.count
    }

    private var completionSummaryText: String {
        guard !todaysHabits.isEmpty else { return "No habits due today" }
        return "\(completedHabitCount) of \(todaysHabits.count) complete today"
    }

    private var todaysHabits: [Habit] {
        habits.filter { viewModel.isDueToday($0) }
    }

    private var laterHabits: [Habit] {
        habits.filter { !viewModel.isDueToday($0) }
    }

    private func habitRow(for habit: Habit, allowsLogging: Bool) -> some View {
        let rowDate = allowsLogging ? Date.now : viewModel.nextDueDate(for: habit)

        return HabitRowView(
            habit: habit,
            completionCount: viewModel.completionCount(for: habit, on: rowDate),
            isCompleted: viewModel.isCompleted(habit: habit, on: rowDate),
            frequencyLabel: viewModel.frequencyLabel(for: habit),
            scheduleLabel: viewModel.scheduleLabel(for: habit),
            onToggle: {
                guard allowsLogging else { return }
                withAnimation {
                    viewModel.logHabitTap(for: habit, context: modelContext)
                }
            }
        )
        .listRowSeparator(.hidden)
        .listRowBackground(AppTheme.background(for: colorScheme))
        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.habitToDelete = habit
                viewModel.showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                viewModel.habitToEdit = habit
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.tag(for: colorScheme))

            if allowsLogging && habit.timesToComplete > 1 && viewModel.completionCount(for: habit) > 0 {
                Button {
                    withAnimation { viewModel.clearCompletion(for: habit, context: modelContext) }
                } label: {
                    Label("Clear", systemImage: "arrow.counterclockwise")
                }
                .tint(AppTheme.muted(for: colorScheme))
            }
        }
    }
}
