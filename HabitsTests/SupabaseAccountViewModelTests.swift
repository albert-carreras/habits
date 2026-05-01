import Foundation
import Testing
@testable import Habits

@Suite("SupabaseAccountViewModel")
@MainActor
struct SupabaseAccountViewModelTests {
    @Test("Sign-in timeout exposes retry state and clears working state")
    func signInTimeoutExposesRetryStateAndClearsWorkingState() async {
        let viewModel = SupabaseAccountViewModel(
            signInService: FakeAccountSignInService { _ in
                try await Task.sleep(for: .seconds(5))
                return AccountSession(
                    email: "person@example.com",
                    userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
                )
            },
            signInTimeout: .milliseconds(10),
            initialEmail: nil,
            initialUserID: nil,
            observesAuthChanges: false
        )

        await viewModel.signInWithGoogle()

        #expect(viewModel.workState == .idle)
        #expect(!viewModel.isWorking)
        #expect(viewModel.email == nil)
        #expect(viewModel.userID == nil)
        #expect(viewModel.retryableSignInProvider == .google)
        #expect(viewModel.alertMessage == "Google sign-in took too long. Check your connection and try again.")
    }

    @Test("Sign out success clears signed-in state")
    func signOutSuccessClearsSignedInState() async {
        var didSignOut = false
        let viewModel = SupabaseAccountViewModel(
            initialEmail: "person@example.com",
            initialUserID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            observesAuthChanges: false,
            localSignOut: {
                didSignOut = true
            }
        )

        let didComplete = await viewModel.signOut()

        #expect(didComplete)
        #expect(didSignOut)
        #expect(viewModel.email == nil)
        #expect(viewModel.userID == nil)
        #expect(viewModel.alertMessage == nil)
    }

    @Test("Sign out failure keeps signed-in state and exposes error")
    func signOutFailureKeepsSignedInState() async {
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let viewModel = SupabaseAccountViewModel(
            initialEmail: "person@example.com",
            initialUserID: userID,
            observesAuthChanges: false,
            localSignOut: {
                throw FakeAccountDeletionError.failed
            }
        )

        let didComplete = await viewModel.signOut()

        #expect(!didComplete)
        #expect(viewModel.email == "person@example.com")
        #expect(viewModel.userID == userID)
        #expect(viewModel.alertMessage == "Delete failed.")
    }

    @Test("Missing auth session during sign out is treated as signed out")
    func signOutMissingSessionClearsStateWithoutError() async {
        let viewModel = SupabaseAccountViewModel(
            initialEmail: "person@example.com",
            initialUserID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            observesAuthChanges: false,
            localSignOut: {
                throw FakeAuthSessionError.missing
            }
        )

        let didComplete = await viewModel.signOut()

        #expect(didComplete)
        #expect(viewModel.email == nil)
        #expect(viewModel.userID == nil)
        #expect(viewModel.alertMessage == nil)
    }

    @Test("Account deletion success clears signed-in state")
    func deleteAccountSuccessClearsSignedInState() async {
        var didSignOut = false
        let viewModel = SupabaseAccountViewModel(
            accountDeletionService: FakeAccountDeletionService(result: .success(AccountDeletionResponse(deleted: true))),
            initialEmail: "person@example.com",
            initialUserID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            observesAuthChanges: false,
            localSignOut: {
                didSignOut = true
            }
        )

        let didDelete = await viewModel.deleteAccount()

        #expect(didDelete)
        #expect(didSignOut)
        #expect(viewModel.email == nil)
        #expect(viewModel.userID == nil)
        #expect(viewModel.alertMessage == nil)
    }

    @Test("Account deletion failure keeps signed-in state and exposes error")
    func deleteAccountFailureKeepsSignedInState() async {
        var didSignOut = false
        let userID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let viewModel = SupabaseAccountViewModel(
            accountDeletionService: FakeAccountDeletionService(result: .failure(FakeAccountDeletionError.failed)),
            initialEmail: "person@example.com",
            initialUserID: userID,
            observesAuthChanges: false,
            localSignOut: {
                didSignOut = true
            }
        )

        let didDelete = await viewModel.deleteAccount()

        #expect(!didDelete)
        #expect(!didSignOut)
        #expect(viewModel.email == "person@example.com")
        #expect(viewModel.userID == userID)
        #expect(viewModel.alertMessage == "Delete failed.")
    }
}

private struct FakeAccountSignInService: AccountSignInServicing {
    var operation: @MainActor (AccountSignInProvider) async throws -> AccountSession

    @MainActor
    func signIn(with provider: AccountSignInProvider) async throws -> AccountSession {
        try await operation(provider)
    }
}

private struct FakeAccountDeletionService: AccountDeletionServicing {
    var result: Result<AccountDeletionResponse, Error>

    @MainActor
    func deleteAccount() async throws -> AccountDeletionResponse {
        try result.get()
    }
}

private enum FakeAccountDeletionError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Delete failed."
    }
}

private enum FakeAuthSessionError: LocalizedError {
    case missing

    var errorDescription: String? {
        "Auth session missing."
    }
}
