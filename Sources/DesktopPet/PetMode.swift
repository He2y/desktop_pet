import Foundation

enum PetMode: String, CaseIterable {
    case companion
    case quiet
    case work

    var menuTitle: String {
        switch self {
        case .companion:
            "Companion Mode"
        case .quiet:
            "Quiet Mode"
        case .work:
            "Work Mode"
        }
    }

    var defaultAction: PetAction {
        switch self {
        case .quiet:
            .sleep
        case .companion, .work:
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
        self == .work
    }
}
