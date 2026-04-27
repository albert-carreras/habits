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
    @State private var startDate: Date = .now
    @State private var notificationsEnabled: Bool = false
    @State private var isSaving = false
    @State private var notificationErrorMessage: String?

    init(habit: Habit? = nil) {
        self.habit = habit
    }

    var isEditing: Bool { habit != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        formSection {
                            TextField("Habit name", text: $name)
                                .font(.body)
                                .foregroundStyle(AppTheme.text(for: colorScheme))
                                .submitLabel(.done)
                                .textInputAutocapitalization(.sentences)
                                .accessibilityIdentifier("habit-name-field")
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
                        }

                        formSection("Reminders") {
                            Toggle("Notifications", isOn: $notificationsEnabled)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle(isEditing ? "Edit Habit" : "New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(AppTheme.accent(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
                Button("OK") { dismiss() }
            } message: {
                Text(notificationErrorMessage ?? "The habit was saved without reminders.")
            }
            .onAppear { loadHabitData() }
        }
        .presentationBackground(AppTheme.background(for: colorScheme))
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
            savedHabit = habit
        } else {
            let newHabit = Habit(
                name: trimmedName,
                frequency: frequency,
                customIntervalValue: frequency == .custom ? customIntervalValue : nil,
                customIntervalUnit: frequency == .custom ? customIntervalUnit : nil,
                timesToComplete: timesToComplete,
                startDate: startDate,
                notificationsEnabled: notificationsEnabled
            )
            modelContext.insert(newHabit)
            savedHabit = newHabit
        }

        let notificationScheduled = await NotificationService.scheduleNotification(for: savedHabit)
        if savedHabit.notificationsEnabled && !notificationScheduled {
            savedHabit.notificationsEnabled = false
            notificationsEnabled = false
            saveContext()
            HabitWidgetSyncService.sync(context: modelContext)
            isSaving = false
            notificationErrorMessage = "The habit was saved, but reminders could not be enabled. Check notification permissions in Settings and try again."
            return
        }

        saveContext()
        HabitWidgetSyncService.sync(context: modelContext)

        isSaving = false
        dismiss()
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("HabitFormView failed to save context: \(error)")
            #endif
        }
    }
}
