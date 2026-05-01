import Foundation
import Supabase

enum SupabaseConfiguration {
    static let url = URL(string: "https://fzgoupebkrkjebogqmtb.supabase.co")!
    static let publishableKey = "sb_publishable_BUX0OwD7OQ5gn-WrgSE8pQ_wZOsj8DA"
    static let redirectURL = URL(string: "com.albertc.habit://auth-callback")!
    static let googleIOSClientID = "94500561889-nipnafo2ubg1td8icodvrnmltius33ud.apps.googleusercontent.com"
    static let googleWebClientID = "94500561889-2ebd5mafvuouuq84ko0k6irdu8nh2v37.apps.googleusercontent.com"
}

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfiguration.url,
    supabaseKey: SupabaseConfiguration.publishableKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            redirectToURL: SupabaseConfiguration.redirectURL,
            emitLocalSessionAsInitialSession: true
        )
    )
)

struct AccountDeletionResponse: Codable, Equatable {
    var deleted: Bool
}

enum AccountDeletionServiceError: LocalizedError, Equatable {
    case invalidResponse
    case deletionRejected(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The account deletion service returned an invalid response."
        case .deletionRejected(_, let message):
            return message
        }
    }
}

protocol AccountDeletionServicing {
    @MainActor
    func deleteAccount() async throws -> AccountDeletionResponse
}

struct SupabaseAccountDeletionService: AccountDeletionServicing {
    private struct ErrorResponse: Decodable {
        var error: String?
        var message: String?
    }

    @MainActor
    func deleteAccount() async throws -> AccountDeletionResponse {
        let session = try await supabase.auth.session
        let request = Self.makeRequest(accessToken: session.accessToken)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountDeletionServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AccountDeletionServiceError.deletionRejected(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: data) ?? "Account deletion failed."
            )
        }

        return try JSONDecoder().decode(AccountDeletionResponse.self, from: data)
    }

    static func makeRequest(accessToken: String) -> URLRequest {
        var request = URLRequest(url: SupabaseConfiguration.url.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) else {
            return nil
        }

        return response.message ?? response.error
    }
}
