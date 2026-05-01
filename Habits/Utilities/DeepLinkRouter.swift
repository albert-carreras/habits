import SwiftUI

@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingAction: DeepLinkAction?

    private init() {}
}

enum DeepLinkAction {
    case addThing
}
