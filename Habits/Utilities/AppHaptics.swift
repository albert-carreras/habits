#if canImport(UIKit)
import UIKit
#endif

enum AppHapticEvent: Equatable {
    case selectionChanged
    case lightTap
    case habitProgressed(isComplete: Bool)
    case completionCleared
    case thingToggled(isComplete: Bool)
    case itemSaved
    case deleteRequested
    case deleteConfirmed
    case dateMoved
    case warning

    var feedback: AppHapticFeedback {
        switch self {
        case .selectionChanged, .dateMoved:
            return .selection
        case .lightTap, .completionCleared:
            return .impact(.soft)
        case .habitProgressed(let isComplete), .thingToggled(let isComplete):
            return isComplete ? .notification(.success) : .impact(.light)
        case .itemSaved:
            return .notification(.success)
        case .deleteRequested:
            return .impact(.medium)
        case .deleteConfirmed, .warning:
            return .notification(.warning)
        }
    }
}

enum AppHapticFeedback: Equatable {
    case selection
    case impact(AppHapticImpact)
    case notification(AppHapticNotification)
}

enum AppHapticImpact: Equatable {
    case light
    case medium
    case soft

    #if canImport(UIKit)
    var style: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light:
            return .light
        case .medium:
            return .medium
        case .soft:
            return .soft
        }
    }
    #endif
}

enum AppHapticNotification: Equatable {
    case success
    case warning

    #if canImport(UIKit)
    var type: UINotificationFeedbackGenerator.FeedbackType {
        switch self {
        case .success:
            return .success
        case .warning:
            return .warning
        }
    }
    #endif
}

@MainActor
enum AppHaptics {
    #if canImport(UIKit)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let impactLightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let impactMediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let impactSoftGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    #endif

    static func prepare() {
        #if canImport(UIKit)
        selectionGenerator.prepare()
        impactLightGenerator.prepare()
        impactMediumGenerator.prepare()
        impactSoftGenerator.prepare()
        notificationGenerator.prepare()
        #endif
    }

    static func perform(_ event: AppHapticEvent) {
        #if canImport(UIKit)
        guard !AppEnvironment.disablesHaptics else { return }

        switch event.feedback {
        case .selection:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        case .impact(let impact):
            let generator = impactGenerator(for: impact)
            generator.impactOccurred()
            generator.prepare()
        case .notification(let notification):
            notificationGenerator.notificationOccurred(notification.type)
            notificationGenerator.prepare()
        }
        #else
        _ = event
        #endif
    }

    #if canImport(UIKit)
    private static func impactGenerator(for impact: AppHapticImpact) -> UIImpactFeedbackGenerator {
        switch impact {
        case .light: return impactLightGenerator
        case .medium: return impactMediumGenerator
        case .soft: return impactSoftGenerator
        }
    }
    #endif
}
