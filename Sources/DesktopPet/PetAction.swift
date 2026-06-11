import Foundation

enum PetAction: String, CaseIterable {
    case eat
    case drag
    case scratch
    case teaser
    case sleep
    case pet
    case walk
    case walkLeft = "walk_left"

    var framesPerSecond: TimeInterval {
        switch self {
        case .walk, .walkLeft, .teaser, .eat, .scratch, .drag, .pet:
            24
        case .sleep:
            12
        }
    }

    var finalFrameHoldDuration: TimeInterval {
        switch self {
        case .sleep:
            4
        case .walk, .walkLeft, .teaser, .eat, .scratch, .drag, .pet:
            0
        }
    }

    var isWalking: Bool {
        self == .walk || self == .walkLeft
    }

    var stepDirection: CGFloat {
        self == .walk ? 1 : -1
    }
}
