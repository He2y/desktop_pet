import AppKit

@MainActor
final class PetController: NSObject {
    private static let displaySize = CGSize(width: 300, height: 300)
    private static let dockOverlap: CGFloat = 8

    private let spriteStore: SpriteStore
    private let petView: PetView
    private let window: NSWindow
    private var timer: Timer?
    private var hoverTimer: Timer?
    private var action: PetAction = .walk
    private var frameIndex = 0
    private var loopCount = 0
    private var hoverActive = false
    private var hoverTeaserConsumed = false
    private var dragActive = false
    private var followsDock = true
    private var automaticWalkLoopsRemaining = Int.random(in: 8...14)
    private var scratchLoopsRemaining = 0
    private var eatLoopsRemaining = 0

    init(spriteStore: SpriteStore) {
        self.spriteStore = spriteStore

        let displaySize = Self.displaySize
        let origin = Self.initialDockOrigin(windowSize: displaySize)

        self.petView = PetView(frame: CGRect(origin: .zero, size: displaySize))
        self.window = NSWindow(
            contentRect: CGRect(origin: origin, size: displaySize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        configureWindow()
        configureViewCallbacks()
        show(action: .walk)
    }

    func start() {
        snapWindowToDock(centered: true)
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        action = .walk
        window.orderFrontRegardless()
        scheduleTimer()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func eatNow() {
        clearHover()
        eatLoopsRemaining = 1
        switchTo(.eat)
    }

    @objc func scratchNow() {
        clearHover()
        scratchLoopsRemaining = 1
        switchTo(.scratch)
    }

    @objc func walkRightNow() {
        clearHover()
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        switchTo(.walk)
    }

    @objc func walkLeftNow() {
        clearHover()
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        switchTo(.walkLeft)
    }

    @objc func dragPreviewNow() {
        clearHover()
        switchTo(.drag)
    }

    @objc func returnToDock() {
        followsDock = true
        clearHover()
        dragActive = false
        snapWindowToDock(centered: false)
        resumeWalking(preferred: .walk)
    }

    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.contentView = petView
        window.isReleasedWhenClosed = false
    }

    private func configureViewCallbacks() {
        petView.onMouseEntered = { [weak self] in
            guard let self else { return }
            hoverActive = true
            hoverTeaserConsumed = false
            scheduleHoverTeaser()
        }

        petView.onMouseExited = { [weak self] in
            guard let self else { return }
            clearHover()
        }

        petView.onDragBegan = { [weak self] in
            guard let self else { return }
            clearHover()
            dragActive = true
            followsDock = false
            switchTo(.drag)
        }

        petView.onDragged = { [weak self] origin in
            self?.window.setFrameOrigin(origin)
        }

        petView.onDragEnded = { [weak self] in
            guard let self else { return }
            dragActive = false
            clearHover()
            resumeWalking(preferred: .walk)
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Return to Dock", action: #selector(returnToDock), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Eat", action: #selector(eatNow), keyEquivalent: "")
        menu.addItem(withTitle: "Drag Pose", action: #selector(dragPreviewNow), keyEquivalent: "")
        menu.addItem(withTitle: "Scratch", action: #selector(scratchNow), keyEquivalent: "")
        menu.addItem(withTitle: "Walk Right", action: #selector(walkRightNow), keyEquivalent: "")
        menu.addItem(withTitle: "Walk Left", action: #selector(walkLeftNow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Desktop Pet", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }
        petView.menu = menu
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = 1.0 / max(action.framesPerSecond, 1)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func scheduleHoverTeaser() {
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startHoverTeaserIfAllowed()
            }
        }
        RunLoop.main.add(hoverTimer!, forMode: .common)
    }

    private func startHoverTeaserIfAllowed() {
        hoverTimer?.invalidate()
        hoverTimer = nil

        guard hoverActive, !hoverTeaserConsumed, !dragActive, action.isWalking else { return }
        hoverTeaserConsumed = true
        switchTo(.teaser)
    }

    private func clearHover() {
        hoverActive = false
        hoverTeaserConsumed = false
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func tick() {
        let frameCount = spriteStore.frameCount(for: action)
        guard frameCount > 0 else { return }

        if followsDock && !dragActive {
            snapWindowToDock(centered: false)
        }

        if let image = spriteStore.image(for: action, index: frameIndex) {
            petView.image = image
        }
        moveIfNeeded()

        frameIndex += 1
        if frameIndex >= frameCount {
            frameIndex = 0
            loopCount += 1
            decideAfterLoop()
        }
    }

    private func decideAfterLoop() {
        if dragActive {
            return
        }

        switch action {
        case .teaser, .drag:
            resumeWalking(preferred: .walk)
        case .scratch:
            scratchLoopsRemaining -= 1
            if scratchLoopsRemaining <= 0 {
                resumeWalking(preferred: .walk)
            }
        case .eat:
            eatLoopsRemaining -= 1
            if eatLoopsRemaining <= 0 {
                resumeWalking(preferred: .walk)
            }
        case .walk, .walkLeft:
            automaticWalkLoopsRemaining -= 1
            guard automaticWalkLoopsRemaining <= 0 else { return }
            automaticWalkLoopsRemaining = Int.random(in: 8...18)

            let roll = Int.random(in: 0..<100)
            if roll < 12 {
                eatLoopsRemaining = 1
                switchTo(.eat)
            } else if roll < 24 {
                scratchLoopsRemaining = 1
                switchTo(.scratch)
            } else if roll < 46 {
                switchTo(action == .walk ? .walkLeft : .walk)
            }
        }
    }

    private func moveIfNeeded() {
        guard action.isWalking, !dragActive else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }

        var frame = window.frame
        if followsDock {
            frame.origin.y = Self.dockY(for: screen, windowHeight: frame.height)
        }
        let step = 2.1 * action.stepDirection
        frame.origin.x += step
        let track = Self.dockTrackFrame(for: screen)

        if frame.minX <= track.minX {
            frame.origin.x = track.minX
            automaticWalkLoopsRemaining = max(automaticWalkLoopsRemaining, 8)
            switchTo(.walk)
            return
        }

        if frame.maxX >= track.maxX {
            frame.origin.x = track.maxX - frame.width
            automaticWalkLoopsRemaining = max(automaticWalkLoopsRemaining, 8)
            switchTo(.walkLeft)
            return
        }

        window.setFrameOrigin(frame.origin)
    }

    private func resumeWalking(preferred: PetAction) {
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        switchTo(preferred.isWalking ? preferred : .walk)
    }

    private func switchTo(_ next: PetAction) {
        guard action != next else { return }
        action = next
        frameIndex = 0
        loopCount = 0
        scheduleTimer()
        show(action: next)
    }

    private func show(action: PetAction) {
        petView.image = spriteStore.image(for: action, index: 0)
    }

    private func snapWindowToDock(centered: Bool) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        var frame = window.frame
        let track = Self.dockTrackFrame(for: screen)
        frame.origin.y = Self.dockY(for: screen, windowHeight: frame.height)
        if centered {
            frame.origin.x = track.midX - frame.width / 2
        } else {
            frame.origin.x = min(max(frame.origin.x, track.minX), track.maxX - frame.width)
        }
        window.setFrameOrigin(frame.origin)
    }

    private static func initialDockOrigin(windowSize: CGSize) -> CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 420, y: 32)
        }
        let track = dockTrackFrame(for: screen)
        return CGPoint(
            x: track.midX - windowSize.width / 2,
            y: dockY(for: screen, windowHeight: windowSize.height)
        )
    }

    private static func dockTrackFrame(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let bottomDockHeight = visible.minY - frame.minY

        if bottomDockHeight > 20 {
            return CGRect(
                x: visible.minX,
                y: frame.minY,
                width: visible.width,
                height: max(1, bottomDockHeight)
            )
        }

        return visible.insetBy(dx: 8, dy: 0)
    }

    private static func dockY(for screen: NSScreen, windowHeight: CGFloat) -> CGFloat {
        let frame = screen.frame
        let visible = screen.visibleFrame
        let bottomDockHeight = visible.minY - frame.minY

        if bottomDockHeight > 20 {
            return visible.minY - dockOverlap
        }

        return max(frame.minY + 8, visible.minY + 8)
    }
}
