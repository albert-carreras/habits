import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var accountViewModel = SupabaseAccountViewModel()
    @State private var exportDocument = BackupDocument(data: Data())
    @State private var exportFileName = BackupService.makeExportFileName()
    @State private var isPresentingExporter = false
    @State private var isPresentingImporter = false
    @State private var pendingImportPreview: BackupImportPreview?
    @State private var showingImportConfirmation = false
    @State private var isImporting = false
    @State private var isRemoteSyncInProgress = false
    @State private var lastSyncedAt: Date?
    @State private var alertState: SettingsAlertState?
    @State private var showingSignOutConfirmation = false
    @State private var showingSignOutSyncFailure = false
    @State private var signOutSyncErrorMessage = ""
    @State private var showingSignInDataChoice = false
    @State private var pendingSignInLocalSummary: BackupSummary?
    @State private var showingDeleteAccountConfirmation = false
    @AppStorage(AppTheme.paletteStorageKey) private var selectedPaletteRaw = AppTheme.defaultPalette.rawValue

    static let settingsRowHorizontalPadding: CGFloat = 16
    static let settingsRowVerticalPadding: CGFloat = 14
    static let settingsDetailVerticalPadding: CGFloat = 12
    static let settingsDividerLeadingPadding: CGFloat = settingsRowHorizontalPadding + 34

    private let showsThingsSection: Bool
    private let usesNavigationStack: Bool

    init(showsThingsSection: Bool = true, usesNavigationStack: Bool = true) {
        self.showsThingsSection = showsThingsSection
        self.usesNavigationStack = usesNavigationStack
    }

    var body: some View {
        settingsContainer
            .tint(AppTheme.tag(for: colorScheme))
            .alert(item: $alertState) { state in
                Alert(
                    title: Text(state.title),
                    message: Text(state.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onChange(of: accountViewModel.alertMessage) { _, message in
                guard let message else { return }

                alertState = SettingsAlertState(title: "Account Error", message: message)
                accountViewModel.alertMessage = nil
            }
            .onChange(of: accountViewModel.userID) { _, _ in
                refreshLastSyncedAt()
            }
            .onAppear {
                refreshLastSyncedAt()
            }
            .alert(
                "Could Not Sync Before Signing Out",
                isPresented: $showingSignOutSyncFailure
            ) {
                Button("Stay Signed In", role: .cancel) {}
                Button("Sign Out, Keep Local Data") {
                    Task { await completeSignOut(removesLocalData: false, showsSuccessAlert: true) }
                }
                Button("Sign Out, Remove Local Data", role: .destructive) {
                    Task { await completeSignOut(removesLocalData: true, showsSuccessAlert: true) }
                }
            } message: {
                Text("Your latest changes may not be backed up yet. \(signOutSyncErrorMessage)")
            }
            .alert(
                "Local Data on This Device",
                isPresented: $showingSignInDataChoice,
                presenting: pendingSignInLocalSummary
            ) { _ in
                Button("Merge with Account") {
                    Task { await mergeLocalDataAfterSignIn() }
                }
                Button("Use Account Data", role: .destructive) {
                    Task { await replaceLocalDataAfterSignIn() }
                }
                Button("Cancel Sign In", role: .cancel) {
                    Task { await cancelSignInAndKeepLocalData() }
                }
            } message: { summary in
                Text("This device has \(localDataDescription(for: summary)). Merge uploads it to \(accountViewModel.email ?? "this account"). Use Account Data removes it from this device and downloads the account data.")
            }
            .accessibilityIdentifier("settings-sheet")
    }

    @ViewBuilder
    private var settingsContainer: some View {
        if usesNavigationStack {
            NavigationStack {
                settingsContent
                    .navigationTitle("Settings")
                    .appInlineNavigationTitle()
                    .appHiddenNavigationToolbarBackground()
            }
        } else {
            settingsContent
        }
    }

    private var settingsContent: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appearanceSection
                    accountSection
                    if showsThingsSection {
                        thingsSection
                    }
                    dataSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
        }
    }

    private var appearanceSection: some View {
        formSection("Theme") {
            VStack(spacing: 0) {
                ForEach(Array(AppPalette.allCases.enumerated()), id: \.element.id) { index, palette in
                    if index > 0 { divider }

                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedPaletteRaw = palette.rawValue
                        }
                        AppHaptics.perform(.selectionChanged)
                    } label: {
                        HStack(spacing: 12) {
                            palettePreview(palette)

                            Text(palette.rawValue)
                                .font(.body.weight(AppTheme.FontWeight.semibold))
                                .foregroundStyle(AppTheme.text(for: colorScheme))

                            Spacer(minLength: 12)

                            if selectedPalette == palette {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(AppTheme.FontWeight.semibold))
                                    .foregroundStyle(AppTheme.primary(for: colorScheme))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Self.settingsRowHorizontalPadding)
                        .padding(.vertical, Self.settingsRowVerticalPadding)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("theme-\(palette.rawValue.lowercased())")
                }
            }
        }
    }

    private var selectedPalette: AppPalette {
        AppTheme.palette(from: selectedPaletteRaw)
    }

    private var isAccountActionDisabled: Bool {
        accountViewModel.isWorking || isRemoteSyncInProgress
    }

    private func signInActionTitle(for provider: AccountSignInProvider) -> String {
        if accountViewModel.workState.activeSignInProvider == provider {
            return "Opening \(provider.displayName)..."
        }

        if accountViewModel.retryableSignInProvider == provider {
            return "Retry with \(provider.displayName)"
        }

        return "Continue with \(provider.displayName)"
    }

    private func palettePreview(_ palette: AppPalette) -> some View {
        let colors = palette.colors
        let scheme = colorScheme
        let bg = scheme == .dark ? colors.darkBackground : colors.lightBackground
        let primary = scheme == .dark ? colors.darkPrimary : colors.lightPrimary
        let accent = scheme == .dark ? colors.darkAccent : colors.lightAccent

        return HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(bg.color)
                .frame(width: 10, height: 22)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(primary.color)
                .frame(width: 10, height: 22)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent.color)
                .frame(width: 10, height: 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(AppTheme.border(for: colorScheme), lineWidth: 0.5))
    }

    private var accountSection: some View {
        formSection("Account") {
            VStack(spacing: 0) {
                settingsStatus(
                    title: accountViewModel.email ?? "Not signed in",
                    systemImage: accountViewModel.email == nil ? "person.crop.circle" : "person.crop.circle.fill"
                )
                .accessibilityIdentifier("account-status")

                if accountViewModel.email != nil {
                    divider

                    settingsDetail(
                        title: "Last synced at",
                        value: lastSyncedText,
                        systemImage: "clock.arrow.circlepath"
                    )
                    .accessibilityIdentifier("last-synced-status")
                }

                divider

                if accountViewModel.email == nil {
                    settingsAction(
                        title: signInActionTitle(for: .apple),
                        systemImage: "apple.logo",
                        isDisabled: isAccountActionDisabled,
                        showsProgress: accountViewModel.workState.activeSignInProvider == .apple
                    ) {
                        Task { await signInWithApple() }
                    }
                    .accessibilityIdentifier("sign-in-apple-button")

                    divider

                    settingsAction(
                        title: signInActionTitle(for: .google),
                        systemImage: "g.circle.fill",
                        isDisabled: isAccountActionDisabled,
                        showsProgress: accountViewModel.workState.activeSignInProvider == .google
                    ) {
                        Task { await signInWithGoogle() }
                    }
                    .accessibilityIdentifier("sign-in-google-button")
                } else {
                    settingsAction(
                        title: isAccountActionDisabled ? "Working..." : "Sign Out",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isDisabled: isAccountActionDisabled
                    ) {
                        showingSignOutConfirmation = true
                    }
                    .accessibilityIdentifier("sign-out-button")
                    .alert(
                        "Sign out of \(accountViewModel.email ?? "your account")?",
                        isPresented: $showingSignOutConfirmation
                    ) {
                        Button("Cancel", role: .cancel) {}
                        Button("Sign Out", role: .destructive) {
                            Task { await signOutWithFinalSync() }
                        }
                    } message: {
                        Text("The app will sync pending changes, remove local account data from this device, and restore it when you sign back in.")
                    }

                    divider

                    settingsAction(
                        title: accountViewModel.isWorking ? "Deleting..." : "Delete Account",
                        systemImage: "trash",
                        isDisabled: accountViewModel.isWorking,
                        isDestructive: true
                    ) {
                        showingDeleteAccountConfirmation = true
                    }
                    .accessibilityIdentifier("delete-account-button")
                    .confirmationDialog(
                        "Delete Account?",
                        isPresented: $showingDeleteAccountConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Account, Keep Data", role: .destructive) {
                            Task { await deleteAccount(removesLocalData: false) }
                        }
                        .disabled(accountViewModel.isWorking)

                        Button("Delete Account and Remove Local Data", role: .destructive) {
                            Task { await deleteAccount(removesLocalData: true) }
                        }
                        .disabled(accountViewModel.isWorking)

                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This permanently deletes your signed-in account and cloud data. Choose whether this device keeps its local habits and things.")
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        formSection("Data") {
            VStack(spacing: 0) {
                settingsAction(
                    title: "Export Backup",
                    systemImage: "square.and.arrow.up",
                    isDisabled: false
                ) {
                    exportBackup()
                }
                .accessibilityIdentifier("export-backup-button")
                .fileExporter(
                    isPresented: $isPresentingExporter,
                    document: exportDocument,
                    contentType: .json,
                    defaultFilename: exportFileName
                ) { result in
                    switch result {
                    case .success:
                        alertState = SettingsAlertState(
                            title: "Export Complete",
                            message: "Your backup file is ready."
                        )
                    case .failure(let error):
                        alertState = SettingsAlertState(
                            title: "Export Failed",
                            message: error.localizedDescription
                        )
                    }
                }

                divider

                settingsAction(
                    title: isImporting ? "Importing..." : "Import Backup",
                    systemImage: "square.and.arrow.down",
                    isDisabled: isImporting
                ) {
                    isPresentingImporter = true
                }
                .accessibilityIdentifier("import-backup-button")
                .fileImporter(
                    isPresented: $isPresentingImporter,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false
                ) { result in
                    handleImportSelection(result)
                }
                .confirmationDialog(
                    "Import Backup?",
                    isPresented: $showingImportConfirmation,
                    titleVisibility: .visible,
                    presenting: pendingImportPreview
                ) { preview in
                    Button("Merge") {
                        Task { await importBackup(preview, mode: .merge) }
                    }
                    .disabled(isImporting)

                    Button("Replace All Data", role: .destructive) {
                        Task { await importBackup(preview, mode: .replace) }
                    }
                    .disabled(isImporting)

                    Button("Cancel", role: .cancel) {
                        pendingImportPreview = nil
                    }
                } message: { preview in
                    Text(importConfirmationMessage(for: preview.summary))
                }

                if accountViewModel.email != nil {
                    divider

                    settingsAction(
                        title: isRemoteSyncInProgress ? "Syncing..." : "Force Sync",
                        systemImage: "arrow.triangle.2.circlepath",
                        isDisabled: isRemoteSyncInProgress
                    ) {
                        Task { await forceSync() }
                    }
                    .accessibilityIdentifier("force-sync-button")
                }
            }
        }
    }

    private var thingsSection: some View {
        formSection("Things") {
            VStack(spacing: 0) {
                NavigationLink {
                    CompletedThingsView()
                } label: {
                    settingsRowContent(
                        title: "Completed Things",
                        systemImage: "checkmark.circle"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("completed-things-button")
            }
        }
    }

    private func settingsStatus(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.tag(for: colorScheme))
                .frame(width: 22, height: 22)

            Text(title)
                .font(.body.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.text(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.settingsRowHorizontalPadding)
        .padding(.vertical, Self.settingsRowVerticalPadding)
    }

    private var lastSyncedText: String {
        guard let lastSyncedAt else { return "Never" }
        return lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func settingsDetail(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.tag(for: colorScheme))
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.text(for: colorScheme))

                Text(value)
                    .font(.footnote.weight(AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.muted(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.settingsRowHorizontalPadding)
        .padding(.vertical, Self.settingsDetailVerticalPadding)
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.border(for: colorScheme))
            .frame(height: 1)
            .padding(.leading, Self.settingsDividerLeadingPadding)
            .padding(.trailing, Self.settingsRowHorizontalPadding)
    }

    private func settingsAction(
        title: String,
        systemImage: String,
        isDisabled: Bool,
        isDestructive: Bool = false,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRowContent(
                title: title,
                systemImage: systemImage,
                isDestructive: isDestructive,
                showsProgress: showsProgress
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.62 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRowContent(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(isDestructive ? Color.red : AppTheme.tag(for: colorScheme))
                .frame(width: 22, height: 22)

            Text(title)
                .font(.body.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(isDestructive ? Color.red : AppTheme.text(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 12)

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.muted(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.settingsRowHorizontalPadding)
        .padding(.vertical, Self.settingsRowVerticalPadding)
        .contentShape(Rectangle())
    }

    private func formSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.muted(for: colorScheme))
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard(
                colorScheme: colorScheme,
                in: RoundedRectangle(cornerRadius: AppTheme.rowCornerRadius, style: .continuous),
                tint: AppTheme.formField(for: colorScheme)
            )
        }
    }

    private func exportBackup() {
        do {
            exportDocument = BackupDocument(data: try BackupService.makeExportData(context: modelContext))
            exportFileName = BackupService.makeExportFileName()
            isPresentingExporter = true
        } catch {
            alertState = SettingsAlertState(title: "Export Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func forceSync() async {
        guard !isRemoteSyncInProgress else { return }

        isRemoteSyncInProgress = true
        defer { isRemoteSyncInProgress = false }

        do {
            let result = try await SyncService.forceSync(context: modelContext)
            refreshLastSyncedAt()
            alertState = SettingsAlertState(
                title: "Sync Complete",
                message: "Pushed \(result.pushedCount) change\(result.pushedCount == 1 ? "" : "s") and pulled \(result.pulledCount) change\(result.pulledCount == 1 ? "" : "s")."
            )
        } catch {
            alertState = SettingsAlertState(title: "Sync Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func signInWithApple() async {
        await signIn {
            await accountViewModel.signInWithApple()
        }
    }

    @MainActor
    private func signInWithGoogle() async {
        await signIn {
            await accountViewModel.signInWithGoogle()
        }
    }

    @MainActor
    private func signIn(_ action: () async -> Void) async {
        guard !isRemoteSyncInProgress else { return }

        let localSummary: BackupSummary
        do {
            localSummary = try BackupService.localDataSummary(context: modelContext)
        } catch {
            alertState = SettingsAlertState(title: "Local Data Error", message: error.localizedDescription)
            return
        }

        await action()

        guard accountViewModel.userID != nil else { return }

        if localSummary.isEmpty {
            await replaceLocalDataAfterSignIn(showsSuccessAlert: false)
        } else {
            SyncService.requireLocalDataDecision()
            pendingSignInLocalSummary = localSummary
            showingSignInDataChoice = true
        }
    }

    @MainActor
    private func mergeLocalDataAfterSignIn() async {
        guard !isRemoteSyncInProgress else { return }

        isRemoteSyncInProgress = true
        defer {
            isRemoteSyncInProgress = false
            pendingSignInLocalSummary = nil
        }

        do {
            let result = try await SyncService.mergeLocalDataIntoRemoteAccount(context: modelContext)
            refreshLastSyncedAt()
            alertState = SettingsAlertState(
                title: "Data Merged",
                message: "Uploaded \(result.pushedCount) change\(result.pushedCount == 1 ? "" : "s") and downloaded \(result.pulledCount) change\(result.pulledCount == 1 ? "" : "s")."
            )
        } catch {
            alertState = SettingsAlertState(title: "Sync Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func replaceLocalDataAfterSignIn(showsSuccessAlert: Bool = true) async {
        guard !isRemoteSyncInProgress else { return }

        isRemoteSyncInProgress = true
        defer {
            isRemoteSyncInProgress = false
            pendingSignInLocalSummary = nil
        }

        do {
            let result = try await SyncService.replaceLocalDataWithRemote(context: modelContext)
            refreshLastSyncedAt()
            if showsSuccessAlert {
                alertState = SettingsAlertState(
                    title: "Account Data Restored",
                    message: "Downloaded \(result.pulledCount) change\(result.pulledCount == 1 ? "" : "s") from your account."
                )
            }
        } catch {
            alertState = SettingsAlertState(title: "Restore Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func cancelSignInAndKeepLocalData() async {
        pendingSignInLocalSummary = nil
        guard await accountViewModel.signOut() else { return }
        SyncService.clearLocalDataDecisionRequirement()
    }

    @MainActor
    private func signOutWithFinalSync() async {
        guard !isRemoteSyncInProgress else { return }

        isRemoteSyncInProgress = true
        do {
            _ = try await SyncService.forceSync(context: modelContext)
            isRemoteSyncInProgress = false
            await completeSignOut(removesLocalData: true, showsSuccessAlert: true)
        } catch {
            isRemoteSyncInProgress = false
            if SupabaseAccountViewModel.isMissingAuthSessionError(error) {
                await completeSignOut(removesLocalData: true, showsSuccessAlert: true)
                return
            }

            signOutSyncErrorMessage = error.localizedDescription
            showingSignOutSyncFailure = true
        }
    }

    @MainActor
    private func completeSignOut(removesLocalData: Bool, showsSuccessAlert: Bool) async {
        guard !isRemoteSyncInProgress else { return }

        isRemoteSyncInProgress = true
        defer { isRemoteSyncInProgress = false }

        guard await accountViewModel.signOut() else { return }
        SyncService.clearLocalDataDecisionRequirement()
        refreshLastSyncedAt()

        if removesLocalData {
            do {
                try BackupService.deleteAllLocalData(context: modelContext)
            } catch {
                alertState = SettingsAlertState(
                    title: "Signed Out",
                    message: "The account was signed out, but local data could not be removed from this device: \(error.localizedDescription)"
                )
                return
            }
        }

        if showsSuccessAlert {
            alertState = SettingsAlertState(
                title: "Signed Out",
                message: removesLocalData
                    ? "Local account data was removed from this device. Sign in again to restore it."
                    : "Local data remains on this device. You will choose how to handle it the next time you sign in."
            )
        }
    }

    @MainActor
    private func deleteAccount(removesLocalData: Bool) async {
        guard await accountViewModel.deleteAccount() else { return }

        if removesLocalData {
            do {
                try BackupService.deleteAllLocalData(context: modelContext)
            } catch {
                alertState = SettingsAlertState(
                    title: "Local Data Error",
                    message: error.localizedDescription
                )
                return
            }
        }

        AppHaptics.perform(.deleteConfirmed)
        alertState = SettingsAlertState(
            title: "Account Deleted",
            message: removesLocalData
                ? "Your account was deleted and local data was removed from this device."
                : "Your account was deleted. Local data remains on this device."
        )
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            do {
                pendingImportPreview = try BackupService.readBackupFile(at: url)
                showingImportConfirmation = true
            } catch {
                alertState = SettingsAlertState(title: "Import Failed", message: error.localizedDescription)
            }
        case .failure(let error):
            alertState = SettingsAlertState(title: "Import Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func importBackup(_ preview: BackupImportPreview, mode: BackupImportMode) async {
        guard !isImporting else { return }

        isImporting = true
        defer {
            isImporting = false
            pendingImportPreview = nil
        }

        do {
            let result = try await BackupService.importBackup(
                preview.backup,
                mode: mode,
                context: modelContext
            )
            alertState = SettingsAlertState(
                title: "Import Complete",
                message: importCompleteMessage(for: result)
            )
        } catch {
            alertState = SettingsAlertState(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func importConfirmationMessage(for summary: BackupSummary) -> String {
        "This backup contains \(summary.habitCount) habit\(summary.habitCount == 1 ? "" : "s"), \(summary.completionCount) completion\(summary.completionCount == 1 ? "" : "s"), and \(summary.thingCount) thing\(summary.thingCount == 1 ? "" : "s")."
    }

    private func importCompleteMessage(for result: BackupImportResult) -> String {
        var message = "Imported \(result.summary.habitCount) habit\(result.summary.habitCount == 1 ? "" : "s"), \(result.summary.completionCount) completion\(result.summary.completionCount == 1 ? "" : "s"), and \(result.summary.thingCount) thing\(result.summary.thingCount == 1 ? "" : "s")."

        if result.disabledReminderCount > 0 {
            message += " \(result.disabledReminderCount) reminder\(result.disabledReminderCount == 1 ? "" : "s") could not be enabled."
        }

        return message
    }

    private func localDataDescription(for summary: BackupSummary) -> String {
        var parts: [String] = []

        if summary.habitCount > 0 {
            parts.append("\(summary.habitCount) habit\(summary.habitCount == 1 ? "" : "s")")
        }
        if summary.completionCount > 0 {
            parts.append("\(summary.completionCount) completion\(summary.completionCount == 1 ? "" : "s")")
        }
        if summary.thingCount > 0 {
            parts.append("\(summary.thingCount) thing\(summary.thingCount == 1 ? "" : "s")")
        }

        guard !parts.isEmpty else { return "no local data" }
        guard parts.count > 1 else { return parts[0] }

        return parts.dropLast().joined(separator: ", ") + ", and " + parts[parts.count - 1]
    }

    @MainActor
    private func refreshLastSyncedAt() {
        lastSyncedAt = SyncService.lastSuccessfulSyncAt(userID: accountViewModel.userID)
    }
}

private struct SettingsAlertState: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}
