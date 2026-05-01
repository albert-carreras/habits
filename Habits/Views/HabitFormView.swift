import SwiftUI
import SwiftData

struct HabitFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let habit: Habit?

    @State private var name: String = ""
    @State private var frequency: HabitFrequency = .daily
    @State private var customIntervalValue: Int = 1
    @State private var customIntervalUnit: CustomIntervalUnit = .days
    @State private var timesToComplete: Int = 1
    @State private var startDate: Date = AppEnvironment.newItemDefaultDate
    @State private var notificationsEnabled: Bool = false
    @State private var notificationTime: Date = Self.makeNotificationTimeDate()
    @State private var isSaving = false
    @State private var notificationErrorMessage: String?
    @FocusState private var isNameFieldFocused: Bool

    init(habit: Habit? = nil) {
        self.habit = habit
    }

    var isEditing: Bool { habit != nil }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iOSBody
        #endif
    }

    private var iOSBody: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    formContent
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle(isEditing ? "Edit Habit" : "New Habit")
            .appInlineNavigationTitle()
            .appHiddenNavigationToolbarBackground()
            .tint(AppTheme.tag(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppHaptics.perform(.lightTap)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(AppTheme.FontWeight.semibold)
                        .accessibilityIdentifier("save-habit-button")
                }
            }
            .alert("Notifications Unavailable", isPresented: notificationAlertBinding) {
                Button("OK") {
                    AppHaptics.perform(.lightTap)
                    dismiss()
                }
            } message: {
                Text(notificationErrorMessage ?? "The habit was saved without reminders.")
            }
            .onAppear {
                loadHabitData()
                if !isEditing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isNameFieldFocused = true
                    }
                }
            }
        }
        .appPresentationBackground(AppTheme.background(for: colorScheme))
    }

    private var macBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit Habit" : "New Habit")
                .font(.title2.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.text(for: colorScheme))
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 8)

            ScrollView {
                formContent
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
            }

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    AppHaptics.perform(.lightTap)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("save-habit-button")
            }
            .padding(16)
        }
        .frame(width: 500)
        .frame(minHeight: 520)
        .background(AppTheme.background(for: colorScheme))
        .tint(AppTheme.tag(for: colorScheme))
        .alert("Notifications Unavailable", isPresented: notificationAlertBinding) {
            Button("OK") {
                AppHaptics.perform(.lightTap)
                dismiss()
            }
        } message: {
            Text(notificationErrorMessage ?? "The habit was saved without reminders.")
        }
        .onAppear {
            loadHabitData()
            if !isEditing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isNameFieldFocused = true
                }
            }
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            formSection {
                TextField("Habit name", text: $name)
                    .font(.body)
                    .foregroundStyle(AppTheme.text(for: colorScheme))
                    .submitLabel(.done)
                    .appTextInputAutocapitalizationSentences()
                    .focused($isNameFieldFocused)
                    .accessibilityIdentifier("habit-name-field")
                    .onSubmit {
                        isNameFieldFocused = false
                    }
                    .onChange(of: name) { _, newValue in
                        if newValue.count > 100 {
                            name = String(newValue.prefix(100))
                        }
                    }
            }

            formSection("Frequency") {
                VStack(spacing: 14) {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(HabitFrequency.allCases) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                    .pickerStyle(.menu)

                    if frequency == .custom {
                        divider

                        Stepper("Every \(customIntervalValue)", value: $customIntervalValue, in: 1...365)

                        Picker("Unit", selection: $customIntervalUnit) {
                            ForEach(CustomIntervalUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }

            formSection("Goal") {
                Stepper(
                    "Complete \(timesToComplete) time\(timesToComplete == 1 ? "" : "s")",
                    value: $timesToComplete,
                    in: 1...9999
                )
            }

            formSection("Schedule") {
                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    #if os(macOS)
                    .datePickerStyle(.graphical)
                    #endif
            }

            formSection("Reminders") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Notifications", isOn: $notificationsEnabled)

                    if notificationsEnabled {
                        DatePicker("Time", selection: $notificationTime, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("notification-time-picker")
                    }
                }
            }
        }
    }

    private var notificationAlertBinding: Binding<Bool> {
        Binding(
            get: { notificationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    notificationErrorMessage = nil
                }
            }
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.border(for: colorScheme))
            .frame(height: 1)
    }

    private func formSection<Content: View>(
        _ title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote.weight(AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.muted(for: colorScheme))
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .softCard(
                colorScheme: colorScheme,
                in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous),
                tint: AppTheme.formField(for: colorScheme)
            )
        }
    }

    private func loadHabitData() {
        guard let habit else { return }
        name = habit.name
        frequency = habit.frequency
        customIntervalValue = habit.customIntervalValue ?? 1
        customIntervalUnit = habit.customIntervalUnit ?? .days
        timesToComplete = habit.timesToComplete
        startDate = habit.startDate
        notificationsEnabled = habit.notificationsEnabled
        notificationTime = Self.makeNotificationTimeDate(
            hour: habit.resolvedNotificationHour,
            minute: habit.resolvedNotificationMinute
        )
    }

    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard !isSaving else { return }

        isSaving = true

        let savedHabit: Habit
        if let habit {
            habit.name = trimmedName
            habit.frequency = frequency
            habit.customIntervalValue = frequency == .custom ? customIntervalValue : nil
            habit.customIntervalUnit = frequency == .custom ? customIntervalUnit : nil
            habit.timesToComplete = timesToComplete
            habit.startDate = startDate
            habit.notificationsEnabled = notificationsEnabled
            habit.notificationHour = notificationTimeComponents.hour
            habit.notificationMinute = notificationTimeComponents.minute
            markDirty(habit)
            savedHabit = habit
        } else {
            let newHabit = Habit(
                name: trimmedName,
                frequency: frequency,
                customIntervalValue: frequency == .custom ? customIntervalValue : nil,
                customIntervalUnit: frequency == .custom ? customIntervalUnit : nil,
                timesToComplete: timesToComplete,
                startDate: startDate,
                notificationsEnabled: notificationsEnabled,
                notificationHour: notificationTimeComponents.hour,
                notificationMinute: notificationTimeComponents.minute
            )
            modelContext.insert(newHabit)
            savedHabit = newHabit
        }

        let notificationScheduled = await NotificationService.scheduleNotification(for: savedHabit)
        if savedHabit.notificationsEnabled && !notificationScheduled {
            savedHabit.notificationsEnabled = false
            notificationsEnabled = false
            guard saveContext() else {
                isSaving = false
                notificationErrorMessage = "The habit could not be saved. Try again."
                AppHaptics.perform(.warning)
                return
            }
            HabitWidgetSyncService.sync(context: modelContext)
            isSaving = false
            notificationErrorMessage = "The habit was saved, but reminders could not be enabled. Check notification permissions in Settings and try again."
            AppHaptics.perform(.warning)
            return
        }

        guard saveContext() else {
            isSaving = false
            AppHaptics.perform(.warning)
            return
        }
        HabitWidgetSyncService.sync(context: modelContext)

        isSaving = false
        AppHaptics.perform(.itemSaved)
        dismiss()
    }

    private func saveContext() -> Bool {
        do {
            try modelContext.save()
            SyncService.schedulePush(context: modelContext)
            return true
        } catch {
            #if DEBUG
            print("HabitFormView failed to save context: \(error)")
            #endif
            return false
        }
    }

    private var notificationTimeComponents: (hour: Int, minute: Int) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: notificationTime)
        return (
            components.hour ?? Habit.defaultNotificationHour,
            components.minute ?? Habit.defaultNotificationMinute
        )
    }

    private static func makeNotificationTimeDate(
        hour: Int = Habit.defaultNotificationHour,
        minute: Int = Habit.defaultNotificationMinute,
        calendar: Calendar = .current
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? .now
    }

    private func markDirty(_ habit: Habit) {
        habit.syncUpdatedAt = .now
        habit.syncDeletedAt = nil
        habit.syncNeedsPush = true
    }
}
