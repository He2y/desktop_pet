import Foundation

enum PetAction: String, CaseIterable {
    case eat
    case drag
    case scratch
    case teaser
    case walk
    case walkLeft = "walk_left"

    var framesPerSecond: TimeInterval {
        switch self {
        case .walk, .walkLeft, .teaser, .eat, .scratch, .drag:
            24
        }
    }

    var isWalking: Bool {
        self == .walk || self == .walkLeft
    }

    var stepDirection: CGFloat {
        self == .walk ? 1 : -1
    }
}
