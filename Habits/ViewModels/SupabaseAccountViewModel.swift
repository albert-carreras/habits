import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Supabase
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class SupabaseAccountViewModel: ObservableObject {
    @Published private(set) var email: String?
    @Published private(set) var userID: UUID?
    @Published private(set) var workState: AccountWorkState = .idle
    @Published private(set) var retryableSignInProvider: AccountSignInProvider?
    @Published var alertMessage: String?

    private var authStateTask: Task<Void, Never>?
    private let signInService: AccountSignInServicing
    private let signInTimeout: Duration
    private let accountDeletionService: AccountDeletionServicing
    private let localSignOut: @MainActor () async throws -> Void

    var isWorking: Bool {
        workState != .idle
    }

    init(
        signInService: AccountSignInServicing? = nil,
        signInTimeout: Duration = .seconds(30),
        accountDeletionService: AccountDeletionServicing? = nil,
        initialEmail: String? = AppEnvironment.uiTestAccountEmail,
        initialUserID: UUID? = AppEnvironment.uiTestAccountUserID,
        observesAuthChanges: Bool = AppEnvironment.uiTestAccountEmail == nil,
        localSignOut: @escaping @MainActor () async throws -> Void = {
            try await supabase.auth.signOut()
        }
    ) {
        self.signInService = signInService ?? SupabaseAccountSignInService()
        self.signInTimeout = signInTimeout
        self.accountDeletionService = accountDeletionService ?? Self.makeAccountDeletionService()
        self.localSignOut = localSignOut
        email = initialEmail
        userID = initialUserID

        guard observesAuthChanges else { return }

        authStateTask = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                if event == .initialSession, session?.isExpired == true {
                    continue
                }
                if session == nil {
                    SyncService.cancelPendingPush()
                }
                self?.email = session?.user.email
                self?.userID = session?.user.id
            }
        }
    }

    private static func makeAccountDeletionService() -> AccountDeletionServicing {
        AppEnvironment.uiTestAccountDeletionSucceeds
            ? UITestAccountDeletionService()
            : SupabaseAccountDeletionService()
    }

    deinit {
        authStateTask?.cancel()
    }

    func signInWithApple() async {
        await signIn(with: .apple)
    }

    func signInWithGoogle() async {
        await signIn(with: .google)
    }

    private func signIn(with provider: AccountSignInProvider) async {
        guard !isWorking else { return }

        workState = .signingIn(provider)
        retryableSignInProvider = nil
        defer {
            workState = .idle
        }

        do {
            let account = try await withSignInTimeout(provider: provider) {
                try await self.signInService.signIn(with: provider)
            }

            email = account.email
            userID = account.userID
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        } catch let error as NSError where error.domain == "com.google.GIDSignIn" && error.code == GIDSignInError.canceled.rawValue {
            return
        } catch {
            if error is AccountSignInTimeoutError {
                retryableSignInProvider = provider
            }
            alertMessage = error.localizedDescription
        }
    }

    private func withSignInTimeout<T: Sendable>(
        provider: AccountSignInProvider,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let gate = SignInTimeoutGate<T>()
        let operationTask = Task { @MainActor in
            try await operation()
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let value = try await operationTask.value
                    gate.resume(.success(value), continuation: continuation)
                } catch {
                    gate.resume(.failure(error), continuation: continuation)
                }
            }

            Task {
                do {
                    try await Task.sleep(for: signInTimeout)
                } catch {
                    return
                }

                await MainActor.run {
                    gate.resume(
                        .failure(AccountSignInTimeoutError(provider: provider)),
                        continuation: continuation
                    )
                    operationTask.cancel()
                }
            }
        }
    }

    #if canImport(UIKit)
    @MainActor
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first,
              var top = window.rootViewController else {
            return nil
        }

        while let presented = top.presentedViewController {
            top = presented
        }

        return top
    }
    #elseif canImport(AppKit)
    @MainActor
    static func presentationWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first
    }
    #endif

    @discardableResult
    func signOut() async -> Bool {
        guard !isWorking else { return false }

        workState = .signingOut
        defer { workState = .idle }

        do {
            SyncService.cancelPendingPush()
            try await localSignOut()
            retryableSignInProvider = nil
            email = nil
            userID = nil
            return true
        } catch {
            guard !Self.isMissingAuthSessionError(error) else {
                retryableSignInProvider = nil
                email = nil
                userID = nil
                return true
            }

            alertMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard !isWorking else { return false }

        workState = .deletingAccount
        defer { workState = .idle }

        do {
            let response = try await accountDeletionService.deleteAccount()
            guard response.deleted else {
                throw AccountDeletionServiceError.invalidResponse
            }

            SyncService.cancelPendingPush()
            try? await localSignOut()
            retryableSignInProvider = nil
            email = nil
            userID = nil
            return true
        } catch {
            alertMessage = error.localizedDescription
            return false
        }
    }

    static func isMissingAuthSessionError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        guard message.contains("session") || message.contains("auth") else {
            return false
        }

        return message.contains("missing")
            || message.contains("not found")
            || message.contains("expired")
            || message.contains("no current")
            || message.contains("already")
    }
}

enum AccountSignInProvider: Equatable, Sendable {
    case apple
    case google

    var displayName: String {
        switch self {
        case .apple:
            return "Apple"
        case .google:
            return "Google"
        }
    }

    var supabaseProvider: OpenIDConnectCredentials.Provider {
        switch self {
        case .apple:
            return .apple
        case .google:
            return .google
        }
    }
}

enum AccountWorkState: Equatable {
    case idle
    case signingIn(AccountSignInProvider)
    case signingOut
    case deletingAccount

    var activeSignInProvider: AccountSignInProvider? {
        switch self {
        case .signingIn(let provider):
            return provider
        case .idle, .signingOut, .deletingAccount:
            return nil
        }
    }
}

struct AccountSession: Sendable {
    var email: String?
    var userID: UUID
}

protocol AccountSignInServicing {
    @MainActor
    func signIn(with provider: AccountSignInProvider) async throws -> AccountSession
}

@MainActor
private final class SupabaseAccountSignInService: AccountSignInServicing {
    private var appleSignInCoordinator: AppleSignInCoordinator?

    func signIn(with provider: AccountSignInProvider) async throws -> AccountSession {
        let token: AccountSignInToken

        switch provider {
        case .apple:
            token = try await appleToken()
        case .google:
            token = try await googleToken()
        }

        try Task.checkCancellation()

        let session = try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: provider.supabaseProvider,
                idToken: token.idToken,
                accessToken: token.accessToken,
                nonce: token.rawNonce
            )
        )

        appleSignInCoordinator = nil
        return AccountSession(email: session.user.email, userID: session.user.id)
    }

    private func appleToken() async throws -> AccountSignInToken {
        let coordinator = AppleSignInCoordinator()
        appleSignInCoordinator = coordinator
        let result = try await coordinator.signIn()

        return AccountSignInToken(
            idToken: result.idToken,
            accessToken: nil,
            rawNonce: result.rawNonce
        )
    }

    private func googleToken() async throws -> AccountSignInToken {
        #if canImport(UIKit)
        guard let presenter = SupabaseAccountViewModel.topViewController() else {
            throw GoogleSignInFlowError.missingPresentationAnchor
        }
        #elseif canImport(AppKit)
        guard let presenter = SupabaseAccountViewModel.presentationWindow() else {
            throw GoogleSignInFlowError.missingPresentationAnchor
        }
        #endif

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: SupabaseConfiguration.googleIOSClientID,
            serverClientID: SupabaseConfiguration.googleWebClientID
        )

        let rawNonce = try AppleSignInNonce.make()
        let hashedNonce = AppleSignInNonce.sha256(rawNonce)

        let tokens: GoogleSignInResultTokens = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            ) { signInResult, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let idToken = signInResult?.user.idToken?.tokenString else {
                    continuation.resume(throwing: GoogleSignInFlowError.missingIdentityToken)
                    return
                }

                let accessToken = signInResult?.user.accessToken.tokenString ?? ""

                continuation.resume(
                    returning: GoogleSignInResultTokens(
                        idToken: idToken,
                        accessToken: accessToken
                    )
                )
            }
        }

        return AccountSignInToken(
            idToken: tokens.idToken,
            accessToken: tokens.accessToken,
            rawNonce: rawNonce
        )
    }
}

private struct AccountSignInToken: Sendable {
    var idToken: String
    var accessToken: String?
    var rawNonce: String?
}

private struct AccountSignInTimeoutError: LocalizedError, Sendable {
    var provider: AccountSignInProvider

    var errorDescription: String? {
        "\(provider.displayName) sign-in took too long. Check your connection and try again."
    }
}

@MainActor
private final class SignInTimeoutGate<Value: Sendable> {
    private var didResume = false

    func resume(_ result: Result<Value, Error>, continuation: CheckedContinuation<Value, Error>) {
        guard !didResume else { return }

        didResume = true
        continuation.resume(with: result)
    }
}

private struct UITestAccountDeletionService: AccountDeletionServicing {
    @MainActor
    func deleteAccount() async throws -> AccountDeletionResponse {
        AccountDeletionResponse(deleted: true)
    }
}

private enum GoogleSignInFlowError: LocalizedError {
    case missingPresentationAnchor
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .missingPresentationAnchor:
            return "The app could not find a window for Google sign-in."
        case .missingIdentityToken:
            return "Google did not return an identity token."
        }
    }
}

private struct GoogleSignInResultTokens: Sendable {
    let idToken: String
    let accessToken: String
}

private struct AppleSignInResult {
    var idToken: String
    var rawNonce: String
}

private enum AppleSignInError: LocalizedError {
    case missingCredential
    case missingIdentityToken
    case invalidIdentityToken
    case missingPresentationAnchor
    case nonceGenerationFailed

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "Apple did not return a sign-in credential."
        case .missingIdentityToken:
            return "Apple did not return an identity token."
        case .invalidIdentityToken:
            return "Apple returned an identity token that could not be decoded."
        case .missingPresentationAnchor:
            return "The app could not find a window for Sign in with Apple."
        case .nonceGenerationFailed:
            return "The app could not create a secure Apple sign-in nonce."
        }
    }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var rawNonce: String?

    func signIn() async throws -> AppleSignInResult {
        let rawNonce = try AppleSignInNonce.make()
        self.rawNonce = rawNonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleSignInNonce.sha256(rawNonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else {
            return ASPresentationAnchor()
        }

        return window
        #elseif canImport(AppKit)
        return SupabaseAccountViewModel.presentationWindow() ?? ASPresentationAnchor()
        #endif
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(with: .failure(AppleSignInError.missingCredential))
            return
        }

        guard let identityToken = credential.identityToken else {
            finish(with: .failure(AppleSignInError.missingIdentityToken))
            return
        }

        guard let idToken = String(data: identityToken, encoding: .utf8) else {
            finish(with: .failure(AppleSignInError.invalidIdentityToken))
            return
        }

        guard let rawNonce else {
            finish(with: .failure(AppleSignInError.nonceGenerationFailed))
            return
        }

        finish(with: .success(AppleSignInResult(idToken: idToken, rawNonce: rawNonce)))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<AppleSignInResult, Error>) {
        guard let continuation else { return }

        self.continuation = nil

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private enum AppleSignInNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func make(length: Int = 32) throws -> String {
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)

            guard status == errSecSuccess else {
                throw AppleSignInError.nonceGenerationFailed
            }

            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }

        return result
    }

    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
