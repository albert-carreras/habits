#if os(macOS)
import SwiftData
import SwiftUI

struct MacHabitListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Habit.name) private var habits: [Habit]
    @Query(sort: [SortDescriptor(\Thing.dueDate), SortDescriptor(\Thing.title)]) private var things: [Thing]

    @State private var viewModel = HabitListViewModel()
    @State private var thingViewModel = ThingListViewModel()
    @State private var selectedMode: MainListMode = .habits
    @State private var referenceDate = Date.now
    @State private var showingSettings = false
    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @StateObject private var commandModel = MacHabitCommandModel()

    static let contentMaxWidth: CGFloat = 680
    static let contentHorizontalPadding: CGFloat = 34
    static let rowSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 22
    static let rowIndicatorFrame: CGFloat = HabitRowView.completionIndicatorSize
    static let rowRingDiameter: CGFloat = HabitRowView.ringDiameter
    static let rowRingLineWidth: CGFloat = HabitRowView.ringLineWidth

    static func showsContentHeader(isCurrentModeEmpty: Bool) -> Bool {
        !isCurrentModeEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if Self.showsContentHeader(isCurrentModeEmpty: isCurrentModeEmpty) {
                    contentHeader
                }

                if isCurrentModeEmpty {
                    emptyState
                } else {
                    activeList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            toastOverlay
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                modeSwitcher
            }

            ToolbarItemGroup {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityIdentifier("mac-settings-button")

                Button {
                    presentAddSheet()
                } label: {
                    Label(selectedMode == .habits ? "New Habit" : "New Thing", systemImage: "plus")
                }
                .accessibilityIdentifier(selectedMode == .habits ? "mac-add-habit-button" : "mac-add-thing-button")
            }
        }
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
            NavigationStack {
                SettingsView(showsThingsSection: true, usesNavigationStack: false)
                    .navigationTitle("Settings")
                    .appInlineNavigationTitle()
                    .appHiddenNavigationToolbarBackground()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingSettings = false
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                    }
            }
            .frame(width: 520, height: 600)
        }
        .alert(deleteAlertTitle, isPresented: $viewModel.showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedItem()
            }
            Button("Cancel", role: .cancel) {
                viewModel.deleteTarget = nil
            }
        } message: {
            Text(deleteAlertMessage)
        }
        .focusedSceneValue(\.macHabitCommands, commandModel)
        .onAppear {
            refreshReferenceDate()
            configureCommands()
            HabitWidgetSyncService.sync(habits: activeHabits)
            ThingWidgetSyncService.sync(things: Array(things))
            Task { try? await SyncService.syncIfStale(context: modelContext) }
        }
        .onChange(of: selectedMode) { _, _ in
            refreshCommandState()
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
    }

    // MARK: - Header

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(MainListMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedMode = mode
                    }
                    AppHaptics.perform(.selectionChanged)
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                        .foregroundStyle(selectedMode == mode ? AppTheme.text(for: colorScheme) : AppTheme.muted(for: colorScheme))
                        .lineLimit(1)
                        .frame(width: 92, height: 26)
                        .background {
                            if selectedMode == mode {
                                Capsule(style: .continuous)
                                    .fill(AppTheme.surface(for: colorScheme))
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mac-mode-\(mode.title.lowercased())-button")
            }
        }
        .padding(3)
        .background(Color.clear, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(AppTheme.border(for: colorScheme), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mac-mode-picker")
    }

    private var contentHeader: some View {
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
        }
        .contentColumn()
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private var headerDateText: String {
        referenceDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    // MARK: - List

    private var activeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch selectedMode {
                case .habits:
                    habitSections
                case .things:
                    thingSections
                }
            }
            .contentColumn()
            .padding(.bottom, 28)
        }
        .background(Color.clear)
        .accessibilityIdentifier("mac-main-list")
    }

    @ViewBuilder
    private var habitSections: some View {
        VStack(alignment: .leading, spacing: 0) {
            completionSummary

            if !todaysHabits.isEmpty {
                sectionBlock("Today", topSpacing: Self.sectionSpacing) {
                    ForEach(todaysHabits) { habit in
                        habitRow(for: habit, allowsLogging: true)
                    }
                }
            }

            if !laterHabits.isEmpty {
                sectionBlock("Later", topSpacing: Self.sectionSpacing) {
                    ForEach(laterHabits) { habit in
                        habitRow(for: habit, allowsLogging: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var thingSections: some View {
        VStack(alignment: .leading, spacing: 0) {
            thingSummary

            if !todaysThings.isEmpty {
                sectionBlock("Today", topSpacing: Self.sectionSpacing) {
                    ForEach(todaysThings) { thing in
                        thingRow(
                            for: thing,
                            showsDueLabel: true
                        )
                    }
                }
            }

            if !laterThings.isEmpty {
                sectionBlock("Later", topSpacing: Self.sectionSpacing) {
                    ForEach(laterThings) { thing in
                        thingRow(for: thing, showsDueLabel: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBlock<Content: View>(
        _ title: String,
        topSpacing: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader(title)

            LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
                content()
            }
        }
        .padding(.top, topSpacing)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(AppTheme.FontWeight.semibold))
            .foregroundStyle(AppTheme.muted(for: colorScheme))
            .textCase(.uppercase)
    }

    // MARK: - Summary Cards

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: completedHabitCount)
        .accessibilityIdentifier("mac-completion-summary")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: incompleteThingCount)
        .accessibilityIdentifier("mac-thing-summary")
    }

    // MARK: - Rows

    private func habitRow(for habit: Habit, allowsLogging: Bool) -> some View {
        let rowDate = allowsLogging ? referenceDate : viewModel.nextDueDate(for: habit, on: referenceDate)
        let completionCount = viewModel.completionCount(for: habit, on: rowDate)
        let isCompleted = viewModel.isCompleted(habit: habit, on: rowDate)

        return HStack(alignment: .center, spacing: 0) {
            Button {
                toggleHabit(habit, allowsLogging: allowsLogging)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(habit.name)
                            .font(.headline)
                            .foregroundStyle(isCompleted ? AppTheme.muted(for: colorScheme) : AppTheme.text(for: colorScheme))
                            .lineLimit(5)

                        HStack(spacing: 6) {
                            Text(viewModel.frequencyLabel(for: habit))

                            if !allowsLogging {
                                Text(viewModel.scheduleLabel(for: habit, on: referenceDate))
                                    .fontWeight(AppTheme.FontWeight.semibold)
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.muted(for: colorScheme))
                    }

                    Spacer(minLength: 12)

                    if habit.timesToComplete > 1 && !isCompleted {
                        Text("\(completionCount)/\(habit.timesToComplete)")
                            .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                            .foregroundStyle(AppTheme.muted(for: colorScheme))
                            .monospacedDigit()
                    }

                    MacCompletionSymbol(
                        isCompleted: isCompleted,
                        completionCount: completionCount,
                        timesToComplete: habit.timesToComplete
                    )
                }
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(habit.timesToComplete > 1 ? "Increment \(habit.name)" : "Complete \(habit.name)")

            rowMenu {
                habitMenuItems(for: habit, allowsLogging: allowsLogging)
            }
            .padding(.trailing, 14)
        }
        .softCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            habitMenuItems(for: habit, allowsLogging: allowsLogging)
        }
        .accessibilityIdentifier("mac-habit-row-\(habit.id.uuidString)")
    }

    private func thingRow(for thing: Thing, showsDueLabel: Bool) -> some View {
        let movesToToday = thingViewModel.isLater(thing, on: referenceDate)
        let allowsToggle = thingViewModel.allowsCompletionToggle(thing, on: referenceDate)

        return HStack(alignment: .center, spacing: 0) {
            Button {
                toggleThing(thing)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(thing.title)
                            .font(.headline)
                            .foregroundStyle(thing.isCompleted ? AppTheme.muted(for: colorScheme) : AppTheme.text(for: colorScheme))
                            .lineLimit(5)

                        if showsDueLabel {
                            Text(thingViewModel.dueLabel(for: thing, on: referenceDate))
                                .font(.caption.weight(AppTheme.FontWeight.semibold))
                                .foregroundStyle(thingViewModel.isOverdue(thing, on: referenceDate) ? AppTheme.danger(for: colorScheme) : AppTheme.muted(for: colorScheme))
                        }
                    }

                    Spacer(minLength: 12)

                    MacCompletionSymbol(
                        isCompleted: thing.isCompleted,
                        completionCount: thing.isCompleted ? 1 : 0,
                        timesToComplete: 1
                    )
                }
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(thing.isCompleted ? "Reopen \(thing.title)" : "Complete \(thing.title)")

            rowMenu {
                thingMenuItems(for: thing, movesToToday: movesToToday)
            }
            .padding(.trailing, 14)
        }
        .opacity(allowsToggle || thing.isCompleted ? 1 : 0.82)
        .softCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            thingMenuItems(for: thing, movesToToday: movesToToday)
        }
        .accessibilityIdentifier("mac-thing-row-\(thing.id.uuidString)")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(selectedMode == .habits ? "No Habits" : "No Things", systemImage: selectedMode == .habits ? "leaf" : "checklist")
        } description: {
            Text(selectedMode == .habits ? "Use New Habit to create your first habit" : "Use New Thing to create your first thing")
        } actions: {
            Button(selectedMode == .habits ? "New Habit" : "New Thing") {
                presentAddSheet()
            }
        }
        .foregroundStyle(AppTheme.muted(for: colorScheme))
    }

    // MARK: - Row Menus

    private func rowMenu<Items: View>(@ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.muted(for: colorScheme))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func habitMenuItems(for habit: Habit, allowsLogging: Bool) -> some View {
        Button("Edit") {
            viewModel.presentEditSheet(for: habit)
        }

        if allowsLogging {
            Button(habit.timesToComplete > 1 ? "Increment" : "Complete") {
                toggleHabit(habit, allowsLogging: true)
            }

            if habit.timesToComplete > 1 && viewModel.completionCount(for: habit, on: referenceDate) > 0 {
                Button("Clear Completion") {
                    clearHabitCompletion(habit)
                }
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            requestDelete(.habit(habit))
        }
    }

    @ViewBuilder
    private func thingMenuItems(for thing: Thing, movesToToday: Bool) -> some View {
        Button("Edit") {
            viewModel.activeSheet = .editThing(thing)
        }

        if thingViewModel.allowsCompletionToggle(thing, on: referenceDate) {
            Button(thing.isCompleted ? "Reopen" : "Complete") {
                toggleThing(thing)
            }
        }

        Button(movesToToday ? "Move to Today" : "Move to Tomorrow") {
            moveThingDate(thing, movesToToday: movesToToday)
        }

        Divider()

        Button("Delete", role: .destructive) {
            requestDelete(.thing(thing))
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toastMessage {
            Text(message)
                .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.text(for: colorScheme))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.border(for: colorScheme), lineWidth: 1))
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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

    // MARK: - Computed Properties

    private var completedCheckColor: Color {
        colorScheme == .dark
            ? AppTheme.success(for: colorScheme)
            : AppTheme.accent(for: colorScheme)
    }

    private var completedCheckSoftColor: Color {
        AppTheme.accentSoft(for: colorScheme)
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

    private var isCurrentModeEmpty: Bool {
        switch selectedMode {
        case .habits:
            return activeHabits.isEmpty
        case .things:
            return visibleThings.isEmpty
        }
    }

    private var activeHabits: [Habit] {
        habits.filter { $0.syncDeletedAt == nil }
    }

    private var todaysHabits: [Habit] {
        activeHabits.filter { viewModel.isDueToday($0, on: referenceDate) }
    }

    private var laterHabits: [Habit] {
        activeHabits.filter { !viewModel.isDueToday($0, on: referenceDate) }
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

    // MARK: - Actions

    private func configureCommands() {
        commandModel.onAdd = { presentAddSheet() }
        commandModel.onSelectHabits = {
            selectedMode = .habits
        }
        commandModel.onSelectThings = {
            selectedMode = .things
        }
        commandModel.onShowSettings = {
            showingSettings = true
        }
        refreshCommandState()
    }

    private func refreshCommandState() {
        commandModel.selectedMode = selectedMode
    }

    private func presentAddSheet() {
        AppHaptics.perform(.lightTap)
        viewModel.presentAddSheet(for: selectedMode)
    }

    private func toggleHabit(_ habit: Habit, allowsLogging: Bool) {
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
        refreshCommandState()
    }

    private func clearHabitCompletion(_ habit: Habit) {
        viewModel.clearCompletion(for: habit, context: modelContext)
        AppHaptics.perform(.completionCleared)
        refreshCommandState()
    }

    private func toggleThing(_ thing: Thing) {
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
        refreshCommandState()
    }

    private func moveThingDate(_ thing: Thing, movesToToday: Bool) {
        if movesToToday {
            thingViewModel.moveToToday(thing, context: modelContext, date: referenceDate)
        } else {
            thingViewModel.moveToTomorrow(thing, context: modelContext, date: referenceDate)
        }
        AppHaptics.perform(.dateMoved)
        refreshCommandState()
    }

    private func requestDelete(_ target: HabitListDeleteTarget) {
        AppHaptics.perform(.deleteRequested)
        viewModel.deleteTarget = target
        viewModel.showingDeleteConfirmation = true
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
        refreshCommandState()
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
        refreshCommandState()
    }
}

private struct MacCompletionSymbol: View {
    @Environment(\.colorScheme) private var colorScheme

    let isCompleted: Bool
    let completionCount: Int
    let timesToComplete: Int

    private var progress: CGFloat {
        guard timesToComplete > 0 else { return 0 }
        return min(1, CGFloat(completionCount) / CGFloat(timesToComplete))
    }

    private var color: Color {
        colorScheme == .dark ? AppTheme.success(for: colorScheme) : AppTheme.accent(for: colorScheme)
    }

    var body: some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: MacHabitListView.rowIndicatorFrame, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(color)
                .frame(width: MacHabitListView.rowIndicatorFrame, height: MacHabitListView.rowIndicatorFrame)
                .contentTransition(.symbolEffect(.replace))
        } else {
            ZStack {
                Circle()
                    .stroke(
                        AppTheme.muted(for: colorScheme).opacity(colorScheme == .dark ? 0.75 : 0.85),
                        lineWidth: MacHabitListView.rowRingLineWidth
                    )

                if timesToComplete > 1 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: MacHabitListView.rowRingLineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(width: MacHabitListView.rowRingDiameter, height: MacHabitListView.rowRingDiameter)
            .frame(width: MacHabitListView.rowIndicatorFrame, height: MacHabitListView.rowIndicatorFrame)
        }
    }
}

private extension View {
    func contentColumn() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MacHabitListView.contentHorizontalPadding)
            .frame(
                maxWidth: MacHabitListView.contentMaxWidth + MacHabitListView.contentHorizontalPadding * 2,
                alignment: .center
            )
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
#endif
