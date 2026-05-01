import SwiftUI
import SwiftData

struct ThingFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let thing: Thing?

    @State private var title: String
    @State private var dueDate: Date
    @State private var isSaving = false
    @FocusState private var isTitleFieldFocused: Bool

    init(thing: Thing? = nil) {
        self.thing = thing
        _title = State(initialValue: thing?.title ?? "")
        _dueDate = State(initialValue: thing.map { Calendar.current.startOfDay(for: $0.dueDate) }
                         ?? Calendar.current.startOfDay(for: AppEnvironment.newItemDefaultDate))
    }

    private var isEditing: Bool { thing != nil }

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
            .navigationTitle(isEditing ? "Edit Thing" : "New Thing")
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
                        save()
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(AppTheme.FontWeight.semibold)
                    .accessibilityIdentifier("save-thing-button")
                }
            }
            .onAppear {
                if !isEditing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isTitleFieldFocused = true
                    }
                }
            }
        }
        .appPresentationBackground(AppTheme.background(for: colorScheme))
    }

    private var macBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit Thing" : "New Thing")
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
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("save-thing-button")
            }
            .padding(16)
        }
        .frame(width: 420)
        .frame(minHeight: 440)
        .background(AppTheme.background(for: colorScheme))
        .tint(AppTheme.tag(for: colorScheme))
        .onAppear {
            if !isEditing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isTitleFieldFocused = true
                }
            }
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            formSection {
                TextField("Thing title", text: $title, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(AppTheme.text(for: colorScheme))
                    .submitLabel(.done)
                    .lineLimit(1...8)
                    .fixedSize(horizontal: false, vertical: true)
                    .appTextInputAutocapitalizationSentences()
                    .focused($isTitleFieldFocused)
                    .accessibilityIdentifier("thing-title-field")
                    .onSubmit {
                        save()
                    }
                    .onChange(of: title) { _, newValue in
                        let shouldSubmit = newValue.contains(where: \.isNewline)
                        let withoutNewlines = newValue
                            .components(separatedBy: .newlines)
                            .joined(separator: " ")
                        let constrainedTitle = String(withoutNewlines.prefix(Thing.maxTitleLength))

                        if constrainedTitle != newValue {
                            title = constrainedTitle
                        }

                        if shouldSubmit {
                            save(titleOverride: constrainedTitle)
                        }
                    }
            }

            formSection("Due") {
                DatePicker("Date", selection: $dueDate, in: datePickerLowerBound..., displayedComponents: .date)
                    .accessibilityIdentifier("thing-due-date-picker")
                    #if os(macOS)
                    .datePickerStyle(.graphical)
                    #endif
            }
        }
    }

    private func formSection<Content: View>(
        _ sectionTitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sectionTitle {
                Text(sectionTitle)
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

    private func save(titleOverride: String? = nil) {
        let trimmedTitle = (titleOverride ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard !isSaving else { return }

        isSaving = true

        let normalizedDueDate = Calendar.current.startOfDay(for: dueDate)
        if let thing {
            var dirtyFields: ThingDirtyFields = []
            if thing.title != trimmedTitle {
                dirtyFields.insert(.title)
            }
            if thing.dueDate != normalizedDueDate {
                dirtyFields.insert(.dueDate)
            }
            guard !dirtyFields.isEmpty else {
                dismiss()
                return
            }
            thing.title = trimmedTitle
            thing.dueDate = normalizedDueDate
            markDirty(thing, fields: dirtyFields)
        } else {
            modelContext.insert(Thing(title: trimmedTitle, dueDate: normalizedDueDate))
        }

        do {
            try modelContext.save()
            SyncService.schedulePush(context: modelContext)
            ThingWidgetSyncService.sync(context: modelContext)
            AppHaptics.perform(.itemSaved)
        } catch {
            #if DEBUG
            print("ThingFormView failed to save context: \(error)")
            #endif
            isSaving = false
            AppHaptics.perform(.warning)
            return
        }

        dismiss()
    }

    private var datePickerLowerBound: Date {
        let today = Calendar.current.startOfDay(for: .now)
        return min(dueDate, today)
    }

    private func markDirty(_ thing: Thing, fields: ThingDirtyFields) {
        let now = Date.now
        thing.syncUpdatedAt = now
        thing.syncDeletedAt = nil
        if fields.contains(.title) {
            thing.syncTitleUpdatedAt = now
        }
        if fields.contains(.dueDate) {
            thing.syncDueDateUpdatedAt = now
        }
        thing.syncNeedsPush = true
    }
}
