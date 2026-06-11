import Foundation

enum PetMode: String, CaseIterable {
    case companion
    case focus

    var menuTitle: String {
        switch self {
        case .companion:
            "Companion Mode"
        case .focus:
            "Work / Quiet Mode"
        }
    }

    var defaultAction: PetAction {
        switch self {
        case .focus:
            .sleep
        case .companion:
            .walk
        }
    }

    var allowsHoverTeaser: Bool {
        self == .companion
    }

    var allowsRandomPlay: Bool {
        self == .companion
    }

    var ignoresMouseEvents: Bool {
        false
    }

    var usesRestCorner: Bool {
        self == .focus
    }

    static func savedValue(_ rawValue: String?) -> PetMode {
        switch rawValue {
        case PetMode.companion.rawValue:
            .companion
        case PetMode.focus.rawValue, "quiet", "work":
            .focus
        default:
            .companion
        }
    }
}
