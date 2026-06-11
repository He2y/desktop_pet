import AppKit

@MainActor
final class PetController: NSObject {
    private static let baseDisplaySize = CGSize(width: 300, height: 300)
    private static let dockOverlap: CGFloat = 8
    private static let defaultScale: CGFloat = 1.0
    private static let minScale: CGFloat = 0.5
    private static let maxScale: CGFloat = 1.8
    private static let defaultOpacity: CGFloat = 1.0
    private static let minOpacity: CGFloat = 0.3
    private static let maxOpacity: CGFloat = 1.0
    private static let scaleDefaultsKey = "desktopPet.scale"
    private static let opacityDefaultsKey = "desktopPet.opacity"
    private static let modeDefaultsKey = "desktopPet.mode"
    private static let reminderCheckInterval: TimeInterval = 30
    private static let mealReminderWindow: TimeInterval = 90
    private static let restReminderInterval: TimeInterval = 50 * 60
    private static let idleInteractionInterval: TimeInterval = 12 * 60
    private static let minimumReminderGap: TimeInterval = 2 * 60
    private static let mealReminderMinutes = [8 * 60, 12 * 60 + 30, 18 * 60 + 30]

    private let spriteStore: SpriteStore
    private let petView: PetView
    private let window: NSWindow
    private let defaults: UserDefaults
    private var timer: Timer?
    private var hoverTimer: Timer?
    private var reminderTimer: Timer?
    private var action: PetAction = .walk
    private var frameIndex = 0
    private var loopCount = 0
    private var scale: CGFloat
    private var opacity: CGFloat
    private var mode: PetMode
    private var hoverActive = false
    private var hoverTeaserConsumed = false
    private var dragActive = false
    private var followsDock = true
    private var pendingDockEdgeAction: PetAction?
    private var automaticWalkLoopsRemaining = Int.random(in: 8...14)
    private var scratchLoopsRemaining = 0
    private var eatLoopsRemaining = 0
    private var sleepLoopsRemaining = 0
    private var petLoopsRemaining = 0
    private var lastInteractionDate = Date()
    private var lastRestReminderDate = Date()
    private var lastIdleReminderDate = Date.distantPast
    private var lastReminderDate = Date.distantPast
    private var triggeredMealReminderKeys: Set<String> = []
    private var sizeLabels: [NSTextField] = []
    private var sizeSliders: [NSSlider] = []
    private var opacityLabels: [NSTextField] = []
    private var opacitySliders: [NSSlider] = []
    private var modeMenuItems: [NSMenuItem] = []

    init(spriteStore: SpriteStore) {
        self.spriteStore = spriteStore

        let defaults = UserDefaults.standard
        self.defaults = defaults
        let savedScale = defaults.object(forKey: Self.scaleDefaultsKey) as? Double
        self.scale = Self.clampedScale(CGFloat(savedScale ?? Self.defaultScale))
        let savedOpacity = defaults.object(forKey: Self.opacityDefaultsKey) as? Double
        self.opacity = Self.clampedOpacity(CGFloat(savedOpacity ?? Self.defaultOpacity))
        let savedMode = defaults.string(forKey: Self.modeDefaultsKey)
        self.mode = PetMode(rawValue: savedMode ?? "") ?? .companion

        let displaySize = Self.displaySize(for: self.scale)
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
        applyModeInteractivity()
        applyAppearance(anchor: .bottomCenter, persist: false)
        show(action: mode.defaultAction)
    }

    func start() {
        snapWindowToDock(centered: mode == .companion)
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        action = mode.defaultAction
        window.orderFrontRegardless()
        scheduleTimer()
        scheduleReminderTimer()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func sizeSliderChanged(_ sender: NSSlider) {
        setScale(CGFloat(sender.doubleValue), persist: true)
    }

    @objc func opacitySliderChanged(_ sender: NSSlider) {
        setOpacity(CGFloat(sender.doubleValue), persist: true)
    }

    @objc func resetAppearance() {
        setScale(Self.defaultScale, persist: false)
        setOpacity(Self.defaultOpacity, persist: false)
        persistAppearance()
    }

    @objc func eatNow() {
        recordInteraction()
        clearHover()
        eatLoopsRemaining = 1
        switchTo(.eat)
    }

    @objc func scratchNow() {
        recordInteraction()
        clearHover()
        scratchLoopsRemaining = 1
        switchTo(.scratch)
    }

    @objc func teaserNow() {
        recordInteraction()
        clearHover()
        switchTo(.teaser)
    }

    @objc func sleepNow() {
        recordInteraction()
        clearHover()
        lastRestReminderDate = Date()
        sleepLoopsRemaining = 2
        switchTo(.sleep)
    }

    @objc func petNow() {
        recordInteraction()
        clearHover()
        petLoopsRemaining = 1
        switchTo(.pet)
    }

    @objc func walkRightNow() {
        recordInteraction()
        clearHover()
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        switchTo(.walk)
    }

    @objc func walkLeftNow() {
        recordInteraction()
        clearHover()
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        switchTo(.walkLeft)
    }

    @objc func dragPreviewNow() {
        recordInteraction()
        clearHover()
        switchTo(.drag)
    }

    @objc func modeMenuItemSelected(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let nextMode = PetMode(rawValue: rawValue)
        else {
            return
        }
        setMode(nextMode, persist: true)
    }

    @objc func returnToDock() {
        recordInteraction()
        followsDock = true
        clearHover()
        dragActive = false
        snapWindowToDock(centered: false)
        resumeForMode(preferred: .walk)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Return to Dock", action: #selector(returnToDock), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(makeModeMenuItem())
        menu.addItem(.separator())
        menu.addItem(makeSliderItem(
            title: "Size",
            value: scale,
            minValue: Self.minScale,
            maxValue: Self.maxScale,
            action: #selector(sizeSliderChanged(_:)),
            labels: &sizeLabels,
            sliders: &sizeSliders
        ))
        menu.addItem(makeSliderItem(
            title: "Opacity",
            value: opacity,
            minValue: Self.minOpacity,
            maxValue: Self.maxOpacity,
            action: #selector(opacitySliderChanged(_:)),
            labels: &opacityLabels,
            sliders: &opacitySliders
        ))
        menu.addItem(withTitle: "Reset Appearance", action: #selector(resetAppearance), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Eat", action: #selector(eatNow), keyEquivalent: "")
        menu.addItem(withTitle: "Drag Pose", action: #selector(dragPreviewNow), keyEquivalent: "")
        menu.addItem(withTitle: "Sleep", action: #selector(sleepNow), keyEquivalent: "")
        menu.addItem(withTitle: "Pet", action: #selector(petNow), keyEquivalent: "")
        menu.addItem(withTitle: "Scratch", action: #selector(scratchNow), keyEquivalent: "")
        menu.addItem(withTitle: "Teaser", action: #selector(teaserNow), keyEquivalent: "")
        menu.addItem(withTitle: "Walk Right", action: #selector(walkRightNow), keyEquivalent: "")
        menu.addItem(withTitle: "Walk Left", action: #selector(walkLeftNow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Desktop Pet", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil && item.target == nil && item.view == nil {
            item.target = self
        }
        updateAppearanceControls()
        updateModeControls()
        return menu
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
        petView.autoresizingMask = [.width, .height]
    }

    private func configureViewCallbacks() {
        petView.onMouseEntered = { [weak self] in
            guard let self else { return }
            recordInteraction()
            guard mode.allowsHoverTeaser else { return }
            hoverActive = true
            hoverTeaserConsumed = false
            scheduleHoverTeaser()
        }

        petView.onMouseExited = { [weak self] in
            guard let self else { return }
            recordInteraction()
            clearHover()
        }

        petView.onDragBegan = { [weak self] in
            guard let self else { return }
            recordInteraction()
            clearHover()
            dragActive = true
            followsDock = false
            pendingDockEdgeAction = nil
            switchTo(.drag)
        }

        petView.onDragged = { [weak self] origin in
            self?.recordInteraction()
            self?.window.setFrameOrigin(origin)
        }

        petView.onDragEnded = { [weak self] in
            guard let self else { return }
            recordInteraction()
            dragActive = false
            clearHover()
            resumeForMode(preferred: .walk)
        }

        petView.menu = makeMenu()
    }

    private func makeSliderItem(
        title: String,
        value: CGFloat,
        minValue: CGFloat,
        maxValue: CGFloat,
        action: Selector,
        labels: inout [NSTextField],
        sliders: inout [NSSlider]
    ) -> NSMenuItem {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 230, height: 48))

        let label = NSTextField(labelWithString: "\(title) \(Self.percentString(for: value))")
        label.frame = CGRect(x: 14, y: 27, width: 202, height: 16)
        label.font = .menuFont(ofSize: 12)
        label.textColor = .labelColor

        let slider = NSSlider(
            value: Double(value),
            minValue: Double(minValue),
            maxValue: Double(maxValue),
            target: self,
            action: action
        )
        slider.frame = CGRect(x: 12, y: 4, width: 206, height: 24)
        slider.isContinuous = true

        view.addSubview(label)
        view.addSubview(slider)
        labels.append(label)
        sliders.append(slider)

        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func makeModeMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Mode")

        for mode in PetMode.allCases {
            let item = NSMenuItem(
                title: mode.menuTitle,
                action: #selector(modeMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            submenu.addItem(item)
            modeMenuItems.append(item)
        }

        parent.submenu = submenu
        return parent
    }

    private func setScale(_ nextScale: CGFloat, persist: Bool) {
        let clamped = Self.clampedScale(nextScale)
        guard abs(clamped - scale) > 0.001 else {
            updateAppearanceControls()
            return
        }

        scale = clamped
        applyAppearance(anchor: followsDock && !dragActive ? .dock : .bottomCenter, persist: persist)
    }

    private func setOpacity(_ nextOpacity: CGFloat, persist: Bool) {
        let clamped = Self.clampedOpacity(nextOpacity)
        guard abs(clamped - opacity) > 0.001 else {
            updateAppearanceControls()
            return
        }

        opacity = clamped
        applyAppearance(anchor: .none, persist: persist)
    }

    private func applyAppearance(anchor: AppearanceAnchor, persist: Bool) {
        window.alphaValue = opacity

        let currentFrame = window.frame
        let nextSize = Self.displaySize(for: scale)
        var nextFrame = CGRect(origin: currentFrame.origin, size: nextSize)

        switch anchor {
        case .bottomCenter:
            nextFrame.origin.x = currentFrame.midX - nextSize.width / 2
            nextFrame.origin.y = currentFrame.minY
        case .dock:
            if let screen = window.screen ?? NSScreen.main {
                let track = Self.dockTrackFrame(for: screen)
                nextFrame.origin.x = Self.clampedX(
                    currentFrame.midX - nextSize.width / 2,
                    windowWidth: nextSize.width,
                    track: track
                )
                nextFrame.origin.y = Self.dockY(for: screen, windowHeight: nextSize.height)
            } else {
                nextFrame.origin.x = currentFrame.midX - nextSize.width / 2
            }
        case .none:
            break
        }

        window.setFrame(nextFrame, display: true)
        petView.frame = CGRect(origin: .zero, size: nextSize)
        updateAppearanceControls()

        if persist {
            persistAppearance()
        }
    }

    private func persistAppearance() {
        defaults.set(Double(scale), forKey: Self.scaleDefaultsKey)
        defaults.set(Double(opacity), forKey: Self.opacityDefaultsKey)
    }

    private func updateAppearanceControls() {
        let sizeText = "Size \(Self.percentString(for: scale))"
        let opacityText = "Opacity \(Self.percentString(for: opacity))"

        for label in sizeLabels {
            label.stringValue = sizeText
        }
        for slider in sizeSliders {
            slider.doubleValue = Double(scale)
        }
        for label in opacityLabels {
            label.stringValue = opacityText
        }
        for slider in opacitySliders {
            slider.doubleValue = Double(opacity)
        }
    }

    private func setMode(_ nextMode: PetMode, persist: Bool) {
        guard mode != nextMode else {
            updateModeControls()
            return
        }

        recordInteraction()
        mode = nextMode
        applyModeInteractivity()
        updateModeControls()

        if persist {
            defaults.set(mode.rawValue, forKey: Self.modeDefaultsKey)
        }

        clearHover()
        pendingDockEdgeAction = nil
        followsDock = true
        snapWindowToDock(centered: false)

        switch mode {
        case .quiet:
            lastRestReminderDate = Date()
            sleepLoopsRemaining = 0
            switchTo(.sleep)
        case .companion:
            if action == .sleep {
                resumeWalking(preferred: .walk)
            }
        case .work:
            if !action.isWalking {
                resumeWalking(preferred: .walk)
            }
        }
    }

    private func applyModeInteractivity() {
        window.ignoresMouseEvents = mode.ignoresMouseEvents
    }

    private func updateModeControls() {
        for item in modeMenuItems {
            let rawValue = item.representedObject as? String
            item.state = rawValue == mode.rawValue ? .on : .off
        }
    }

    private func recordInteraction() {
        lastInteractionDate = Date()
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

    private func scheduleReminderTimer() {
        reminderTimer?.invalidate()
        reminderTimer = Timer.scheduledTimer(withTimeInterval: Self.reminderCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkLifeReminders()
            }
        }
        RunLoop.main.add(reminderTimer!, forMode: .common)
    }

    private func checkLifeReminders() {
        let now = Date()

        if let mealKey = dueMealReminderKey(at: now), canStartAutomaticReminder(at: now) {
            triggeredMealReminderKeys.insert(mealKey)
            triggerMealReminder(at: now)
            return
        }

        if shouldTriggerRestReminder(at: now), canStartAutomaticReminder(at: now) {
            triggerRestReminder(at: now)
            return
        }

        if shouldTriggerIdleReminder(at: now), canStartAutomaticReminder(at: now) {
            triggerIdleReminder(at: now)
        }
    }

    private func dueMealReminderKey(at date: Date) -> String? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }

        let minuteOfDay = hour * 60 + minute
        for mealMinute in Self.mealReminderMinutes {
            guard abs(minuteOfDay - mealMinute) <= 1 else { continue }

            let scheduledHour = mealMinute / 60
            let scheduledMinute = mealMinute % 60
            guard
                let scheduledDate = calendar.date(
                    bySettingHour: scheduledHour,
                    minute: scheduledMinute,
                    second: 0,
                    of: date
                ),
                abs(date.timeIntervalSince(scheduledDate)) <= Self.mealReminderWindow
            else {
                continue
            }

            let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
            let key = "\(day)-\(mealMinute)"
            if !triggeredMealReminderKeys.contains(key) {
                return key
            }
        }

        return nil
    }

    private func shouldTriggerRestReminder(at date: Date) -> Bool {
        guard mode != .quiet else { return false }
        return date.timeIntervalSince(lastRestReminderDate) >= Self.restReminderInterval
    }

    private func shouldTriggerIdleReminder(at date: Date) -> Bool {
        guard mode == .companion else { return false }
        guard date.timeIntervalSince(lastInteractionDate) >= Self.idleInteractionInterval else { return false }
        return date.timeIntervalSince(lastIdleReminderDate) >= Self.idleInteractionInterval
    }

    private func canStartAutomaticReminder(at date: Date) -> Bool {
        guard !dragActive else { return false }
        guard date.timeIntervalSince(lastReminderDate) >= Self.minimumReminderGap else { return false }
        switch action {
        case .walk, .walkLeft, .sleep:
            return true
        case .eat, .scratch, .teaser, .drag, .pet:
            return false
        }
    }

    private func triggerMealReminder(at date: Date) {
        lastReminderDate = date
        eatLoopsRemaining = 2
        moveToDockEdgeThen(.eat)
    }

    private func triggerRestReminder(at date: Date) {
        lastReminderDate = date
        lastRestReminderDate = date
        clearHover()
        pendingDockEdgeAction = nil
        sleepLoopsRemaining = 3
        switchTo(.sleep)
    }

    private func triggerIdleReminder(at date: Date) {
        lastReminderDate = date
        lastIdleReminderDate = date
        clearHover()
        pendingDockEdgeAction = nil
        petLoopsRemaining = 1
        switchTo(.pet)
    }

    private func startHoverTeaserIfAllowed() {
        hoverTimer?.invalidate()
        hoverTimer = nil

        guard mode.allowsHoverTeaser, hoverActive, !hoverTeaserConsumed, !dragActive, action.isWalking else { return }
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
            resumeForMode(preferred: .walk)
        case .scratch:
            scratchLoopsRemaining -= 1
            if scratchLoopsRemaining <= 0 {
                resumeForMode(preferred: .walk)
            }
        case .eat:
            eatLoopsRemaining -= 1
            if eatLoopsRemaining <= 0 {
                resumeForMode(preferred: .walk)
            }
        case .sleep:
            if mode == .quiet {
                return
            }
            sleepLoopsRemaining -= 1
            if sleepLoopsRemaining <= 0 {
                resumeForMode(preferred: .walk)
            }
        case .pet:
            petLoopsRemaining -= 1
            if petLoopsRemaining <= 0 {
                resumeForMode(preferred: .walk)
            }
        case .walk, .walkLeft:
            if pendingDockEdgeAction != nil {
                return
            }

            automaticWalkLoopsRemaining -= 1
            guard automaticWalkLoopsRemaining <= 0 else { return }
            automaticWalkLoopsRemaining = Int.random(in: 8...18)

            guard mode.allowsRandomPlay else {
                if Int.random(in: 0..<100) < 36 {
                    switchTo(action == .walk ? .walkLeft : .walk)
                }
                return
            }

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

        if track.width <= frame.width {
            frame.origin.x = track.midX - frame.width / 2
            window.setFrameOrigin(frame.origin)
            completePendingDockEdgeAction()
            return
        }

        if let pendingDockEdgeAction {
            if action == .walkLeft && frame.minX <= track.minX {
                frame.origin.x = track.minX
                window.setFrameOrigin(frame.origin)
                completePendingDockEdgeAction(pendingDockEdgeAction)
                return
            }

            if action == .walk && frame.maxX >= track.maxX {
                frame.origin.x = track.maxX - frame.width
                window.setFrameOrigin(frame.origin)
                completePendingDockEdgeAction(pendingDockEdgeAction)
                return
            }
        }

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

    private func moveToDockEdgeThen(_ nextAction: PetAction) {
        guard let screen = window.screen ?? NSScreen.main else {
            switchTo(nextAction)
            return
        }

        followsDock = true
        clearHover()
        let track = Self.dockTrackFrame(for: screen)
        let midpoint = window.frame.midX
        let distanceToLeft = abs(midpoint - track.minX)
        let distanceToRight = abs(track.maxX - midpoint)
        pendingDockEdgeAction = nextAction
        automaticWalkLoopsRemaining = Int.max
        switchTo(distanceToLeft < distanceToRight ? .walkLeft : .walk)
    }

    private func completePendingDockEdgeAction(_ pending: PetAction? = nil) {
        guard let nextAction = pending ?? pendingDockEdgeAction else { return }
        pendingDockEdgeAction = nil

        switch nextAction {
        case .eat:
            eatLoopsRemaining = max(eatLoopsRemaining, 2)
        case .sleep:
            sleepLoopsRemaining = max(sleepLoopsRemaining, 2)
        case .pet:
            petLoopsRemaining = max(petLoopsRemaining, 1)
        case .scratch:
            scratchLoopsRemaining = max(scratchLoopsRemaining, 1)
        case .teaser, .drag, .walk, .walkLeft:
            break
        }

        switchTo(nextAction)
    }

    private func resumeWalking(preferred: PetAction) {
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        switchTo(preferred.isWalking ? preferred : .walk)
    }

    private func resumeForMode(preferred: PetAction) {
        pendingDockEdgeAction = nil

        switch mode {
        case .quiet:
            sleepLoopsRemaining = 0
            switchTo(.sleep)
        case .companion, .work:
            resumeWalking(preferred: preferred)
        }
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
            frame.origin.x = Self.clampedX(track.midX - frame.width / 2, windowWidth: frame.width, track: track)
        } else {
            frame.origin.x = Self.clampedX(frame.origin.x, windowWidth: frame.width, track: track)
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

    private static func displaySize(for scale: CGFloat) -> CGSize {
        CGSize(
            width: baseDisplaySize.width * scale,
            height: baseDisplaySize.height * scale
        )
    }

    private static func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private static func clampedOpacity(_ value: CGFloat) -> CGFloat {
        min(max(value, minOpacity), maxOpacity)
    }

    private static func percentString(for value: CGFloat) -> String {
        "\(Int(round(value * 100)))%"
    }

    private static func clampedX(_ value: CGFloat, windowWidth: CGFloat, track: CGRect) -> CGFloat {
        if track.width <= windowWidth {
            return track.midX - windowWidth / 2
        }
        return min(max(value, track.minX), track.maxX - windowWidth)
    }

    private enum AppearanceAnchor {
        case bottomCenter
        case dock
        case none
    }
}
