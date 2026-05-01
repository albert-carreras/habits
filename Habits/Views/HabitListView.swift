import SwiftUI
import SwiftData

#if os(iOS)
struct HabitListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppTheme.paletteStorageKey) private var selectedPaletteRaw = AppTheme.defaultPalette.rawValue
    @Query(sort: \Habit.name) private var habits: [Habit]
    @Query(sort: [SortDescriptor(\Thing.dueDate), SortDescriptor(\Thing.title)]) private var things: [Thing]
    @State private var viewModel = HabitListViewModel()
    @State private var thingViewModel = ThingListViewModel()
    @State private var selectedMode: MainListMode = .habits
    @State private var referenceDate = Date.now
    @State private var showingSettings = false
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topHeader
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 14)
                        .background(AppTheme.background(for: colorScheme))

                    if isCurrentModeEmpty {
                        emptyState
                    } else {
                        activeList
                    }
                }

                bottomControls

                toastOverlay
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $viewModel.activeSheet) { sheet in
                switch sheet {
                case .add:
                    HabitFormView()
                case .edit(let habit):
                    HabitFormView(habit: habit)
                case .addThing:
                    ThingFormView()
                case .editThing(let thing):
                    ThingFormView(thing: thing)
                }
            }
            .sheet(isPresented: $showingSettings) {
                settingsSheet
            }
            .alert(deleteAlertTitle, isPresented: $viewModel.showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteSelectedItem()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteAlertMessage)
            }
            .onAppear {
                refreshReferenceDate()
                HabitWidgetSyncService.sync(habits: activeHabits)
                ThingWidgetSyncService.sync(things: Array(things))
                Task { try? await SyncService.syncIfStale(context: modelContext) }
            }
            .onChange(of: DeepLinkRouter.shared.pendingAction) { _, action in
                guard let action else { return }
                DeepLinkRouter.shared.pendingAction = nil
                handleDeepLink(action)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    refreshReferenceDate()
                    Task { try? await SyncService.syncIfStale(context: modelContext) }
                } else if newPhase == .background {
                    Task { try? await SyncService.pushDirtyRows(context: modelContext) }
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    let now = Date.now
                    guard let nextMidnight = Calendar.current.nextDate(
                        after: now,
                        matching: DateComponents(hour: 0, minute: 0, second: 0),
                        matchingPolicy: .nextTime
                    ) else { return }
                    let nanos = UInt64(max(1, nextMidnight.timeIntervalSince(now)) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    if Task.isCancelled { return }
                    refreshReferenceDate()
                }
            }
            .animation(.easeInOut(duration: 0.22), value: selectedPaletteRaw)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: selectedMode == .habits ? "leaf" : "checklist")
        } description: {
            Text(emptyStateDescription)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(AppTheme.muted(for: colorScheme))
    }

    private var topHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headerDateText)
                    .font(.caption.weight(AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.muted(for: colorScheme))
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(selectedMode.title)
                    .font(.largeTitle.weight(AppTheme.FontWeight.bold))
                    .foregroundStyle(AppTheme.text(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            settingsButton
                .padding(.top, 2)
        }
    }

    private var headerDateText: String {
        referenceDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(MainListMode.allCases) { mode in
                let isSelected = selectedMode == mode

                Button {
                    if !isSelected {
                        AppHaptics.perform(.selectionChanged)
                    }

                    selectedMode = mode
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                        .foregroundStyle(isSelected ? selectedModeTextColor : unselectedModeTextColor)
                        .frame(width: 86, height: 56)
                        .background {
                            if isSelected {
                                Capsule()
                                    .liquidGlass(
                                        colorScheme: colorScheme,
                                        in: Capsule(),
                                        tint: completedCheckColor,
                                        fillOpacity: floatingActionFillOpacity,
                                        interactive: true
                                    )
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityIdentifier("mode-switcher-\(mode.rawValue)")
            }
        }
        .padding(4)
        .liquidGlass(
            colorScheme: colorScheme,
            in: Capsule(),
            tint: completedCheckColor,
            fillOpacity: modeSwitcherShellFillOpacity,
            interactive: true
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mode-switcher")
    }

    private var settingsButton: some View {
        Button {
            AppHaptics.perform(.lightTap)
            showingSettings = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.muted(for: colorScheme))
                .rotationEffect(.degrees(90))
                .frame(width: 44, height: 44)
        }
        .contentShape(Circle())
        .buttonStyle(BouncyPressStyle())
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("settings-button")
    }

    private var settingsSheet: some View {
        SettingsView()
    }

    private var completionSummary: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(completedCheckColor)
                .frame(width: 9, height: 9)

            Text(completionSummaryText)
                .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(completedCheckColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .softCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous),
            tint: completedCheckSoftColor
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: completedHabitCount)
        .accessibilityIdentifier("completion-summary")
    }

    private var thingSummary: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(completedCheckColor)
                .frame(width: 9, height: 9)

            Text(thingSummaryText)
                .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(completedCheckColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .softCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous),
            tint: completedCheckSoftColor
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: incompleteThingCount)
        .accessibilityIdentifier("thing-summary")
    }

    private var addButton: some View {
        Button {
            AppHaptics.perform(.lightTap)
            viewModel.presentAddSheet(for: selectedMode)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.tagForeground(for: colorScheme))
                .frame(width: 56, height: 56)
                .background(AppTheme.tag(for: colorScheme), in: Circle())
        }
        .contentShape(Circle())
        .buttonStyle(BouncyPressStyle())
        .accessibilityLabel(selectedMode == .habits ? "Add habit" : "Add thing")
        .accessibilityIdentifier(selectedMode == .habits ? "add-habit-button" : "add-thing-button")
    }

    private var completedCheckColor: Color {
        colorScheme == .dark
            ? AppTheme.success(for: colorScheme)
            : AppTheme.accent(for: colorScheme)
    }

    private var floatingActionFillOpacity: Double {
        colorScheme == .dark ? 0.78 : 0.92
    }

    private var modeSwitcherShellFillOpacity: Double {
        colorScheme == .dark ? 0.20 : 0.14
    }

    private var completedCheckSoftColor: Color {
        AppTheme.accentSoft(for: colorScheme)
    }

    private var selectedModeTextColor: Color {
        AppTheme.contrastingForeground(for: selectedModeBackgroundRGB)
    }

    private var unselectedModeTextColor: Color {
        AppTheme.contrastingForeground(for: modeSwitcherShellBackgroundRGB)
    }

    private var selectedModeBackgroundRGB: RGB {
        AppTheme.accentControlRGB(for: colorScheme).blended(
            over: AppTheme.backgroundRGB(for: colorScheme),
            opacity: floatingActionFillOpacity
        )
    }

    private var modeSwitcherShellBackgroundRGB: RGB {
        AppTheme.accentControlRGB(for: colorScheme).blended(
            over: AppTheme.backgroundRGB(for: colorScheme),
            opacity: modeSwitcherShellFillOpacity
        )
    }

    private var bottomControls: some View {
        HStack(alignment: .bottom) {
            modeSwitcher

            Spacer(minLength: 16)

            addButton
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private var activeList: some View {
        switch selectedMode {
        case .habits:
            habitList
        case .things:
            thingList
        }
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
                        .padding(.top, todaysHabits.isEmpty ? 0 : 4)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .contentMargins(.bottom, 130)
    }

    private var thingList: some View {
        List {
            Section {
                thingSummary
                    .listRowSeparator(.hidden)
                    .listRowBackground(AppTheme.background(for: colorScheme))
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
            }

            if !todaysThings.isEmpty {
                Section {
                    ForEach(todaysThings) { thing in
                        thingRow(
                            for: thing,
                            showsDueLabel: thingViewModel.isOverdue(thing, on: referenceDate)
                        )
                    }
                } header: {
                    sectionHeader("Today")
                }
            }

            if !laterThings.isEmpty {
                Section {
                    ForEach(laterThings) { thing in
                        thingRow(for: thing, showsDueLabel: true)
                    }
                } header: {
                    sectionHeader("Later")
                        .padding(.top, todaysThings.isEmpty ? 0 : 4)
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

    private var isCurrentModeEmpty: Bool {
        switch selectedMode {
        case .habits:
            return activeHabits.isEmpty
        case .things:
            return visibleThings.isEmpty
        }
    }

    private var emptyStateTitle: String {
        selectedMode == .habits ? "No Habits" : "No Things"
    }

    private var emptyStateDescription: String {
        selectedMode == .habits ? "Tap + to create your first habit" : "Tap + to create your first thing"
    }

    private var completedHabitCount: Int {
        todaysHabits.filter { viewModel.isCompleted(habit: $0, on: referenceDate) }.count
    }

    private var completionSummaryText: String {
        guard !todaysHabits.isEmpty else { return "No habits due today" }
        return "\(completedHabitCount) of \(todaysHabits.count) complete today"
    }

    private var incompleteThingCount: Int {
        thingViewModel.openTodayThingCount(from: things, on: referenceDate)
    }

    private var thingSummaryText: String {
        if incompleteThingCount == 0 {
            return "No things open today"
        }
        return "\(incompleteThingCount) thing\(incompleteThingCount == 1 ? "" : "s") open today"
    }

    private var todaysHabits: [Habit] {
        activeHabits.filter { viewModel.isDueToday($0, on: referenceDate) }
    }

    private var laterHabits: [Habit] {
        activeHabits.filter { !viewModel.isDueToday($0, on: referenceDate) }
    }

    private var activeHabits: [Habit] {
        habits.filter { $0.syncDeletedAt == nil }
    }

    private var visibleThings: [Thing] {
        thingViewModel.visibleThings(from: things, on: referenceDate)
    }

    private var todaysThings: [Thing] {
        thingViewModel.todaysThings(from: things, on: referenceDate)
    }

    private var laterThings: [Thing] {
        thingViewModel.laterThings(from: things, on: referenceDate)
    }

    private var deleteAlertTitle: String {
        viewModel.deleteTarget?.title ?? "Delete"
    }

    private var deleteAlertMessage: String {
        viewModel.deleteTarget?.message ?? "This cannot be undone."
    }

    private func habitRow(for habit: Habit, allowsLogging: Bool) -> some View {
        let rowDate = allowsLogging ? referenceDate : viewModel.nextDueDate(for: habit, on: referenceDate)

        return HabitRowView(
            habit: habit,
            completionCount: viewModel.completionCount(for: habit, on: rowDate),
            isCompleted: viewModel.isCompleted(habit: habit, on: rowDate),
            frequencyLabel: viewModel.frequencyLabel(for: habit),
            scheduleLabel: viewModel.scheduleLabel(for: habit, on: referenceDate),
            showsScheduleLabel: !allowsLogging,
            onToggle: {
                guard allowsLogging else {
                    showToast("You can complete this later")
                    AppHaptics.perform(.lightTap)
                    return
                }
                let wasComplete = viewModel.isCompleted(habit: habit, on: referenceDate)
                viewModel.logHabitTap(for: habit, context: modelContext)
                let isComplete = viewModel.isCompleted(habit: habit, on: referenceDate)
                if wasComplete != isComplete || !wasComplete {
                    AppHaptics.perform(.habitProgressed(isComplete: isComplete))
                }
            }
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                AppHaptics.perform(.deleteRequested)
                viewModel.deleteTarget = .habit(habit)
                viewModel.showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                AppHaptics.perform(.lightTap)
                viewModel.presentEditSheet(for: habit)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.tag(for: colorScheme))

            if allowsLogging && habit.timesToComplete > 1 && viewModel.completionCount(for: habit, on: referenceDate) > 0 {
                Button {
                    viewModel.clearCompletion(for: habit, context: modelContext)
                    AppHaptics.perform(.completionCleared)
                } label: {
                    Label("Clear", systemImage: "arrow.counterclockwise")
                }
                .tint(AppTheme.muted(for: colorScheme))
            }
        }
    }

    private func thingRow(for thing: Thing, showsDueLabel: Bool) -> some View {
        let movesToToday = thingViewModel.isLater(thing, on: referenceDate)

        return ThingRowView(
            thing: thing,
            dueLabel: thingViewModel.dueLabel(for: thing, on: referenceDate),
            isOverdue: thingViewModel.isOverdue(thing, on: referenceDate),
            allowsToggle: thingViewModel.allowsCompletionToggle(thing, on: referenceDate),
            showsDueLabel: showsDueLabel,
            onToggle: {
                guard thingViewModel.allowsCompletionToggle(thing, on: referenceDate) else {
                    showToast("You can complete this later")
                    AppHaptics.perform(.lightTap)
                    return
                }
                let wasComplete = thing.isCompleted
                thingViewModel.toggleCompletion(for: thing, context: modelContext, date: referenceDate)
                if wasComplete != thing.isCompleted {
                    AppHaptics.perform(.thingToggled(isComplete: thing.isCompleted))
                }
            }
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                AppHaptics.perform(.deleteRequested)
                viewModel.deleteTarget = .thing(thing)
                viewModel.showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                AppHaptics.perform(.lightTap)
                viewModel.activeSheet = .editThing(thing)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.tag(for: colorScheme))

            Button {
                AppHaptics.perform(.dateMoved)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation {
                        if movesToToday {
                            thingViewModel.moveToToday(thing, context: modelContext, date: referenceDate)
                        } else {
                            thingViewModel.moveToTomorrow(thing, context: modelContext, date: referenceDate)
                        }
                    }
                }
            } label: {
                Label(movesToToday ? "Today" : "Tomorrow", systemImage: "calendar")
            }
            .tint(AppTheme.accent(for: colorScheme))
        }
    }

    private func deleteSelectedItem() {
        guard let deleteTarget = viewModel.deleteTarget else { return }

        switch deleteTarget {
        case .habit(let habit):
            viewModel.deleteHabit(habit, context: modelContext)
        case .thing(let thing):
            thingViewModel.deleteThing(thing, context: modelContext)
        }
        AppHaptics.perform(.deleteConfirmed)

        viewModel.deleteTarget = nil
    }

    private func handleDeepLink(_ action: DeepLinkAction) {
        switch action {
        case .addThing:
            selectedMode = .things
            viewModel.activeSheet = .addThing
        }
    }

    private func refreshReferenceDate() {
        referenceDate = Date.now
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toastMessage {
            Text(message)
                .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.text(for: colorScheme))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .softCard(
                    colorScheme: colorScheme,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                    tint: AppTheme.tag(for: colorScheme)
                )
                .padding(.horizontal, 32)
                .padding(.bottom, 110)
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("later-toast")
                .allowsHitTesting(false)
        }
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            toastMessage = message
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                toastMessage = nil
            }
        }
    }
}
#endif
