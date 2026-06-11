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
    private static let minimumReminderGap: TimeInterval = 2 * 60
    private static let restCornerInset: CGFloat = 8
    private static let bubbleScreenInset: CGFloat = 10
    private static let bubbleDuration: TimeInterval = 9

    private let spriteStore: SpriteStore
    private let petView: PetView
    private let window: NSWindow
    private let bubbleView: ReminderBubbleView
    private let bubbleWindow: NSWindow
    private let defaults: UserDefaults
    private var reminderSettingsWindowController: ReminderSettingsWindowController?
    private var timer: Timer?
    private var hoverTimer: Timer?
    private var reminderTimer: Timer?
    private var bubbleTimer: Timer?
    private var action: PetAction = .walk
    private var frameIndex = 0
    private var loopCount = 0
    private var finalFrameHoldTicksRemaining = 0
    private var scale: CGFloat
    private var opacity: CGFloat
    private var mode: PetMode
    private var reminderSettings: ReminderSettings
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
    private var pendingReminderBubbleMessage: String?
    private var sizeLabels: [NSTextField] = []
    private var sizeSliders: [NSSlider] = []
    private var opacityLabels: [NSTextField] = []
    private var opacitySliders: [NSSlider] = []
    private var modeMenuItems: [NSMenuItem] = []
    private var reminderSummaryItems: [NSMenuItem] = []
    private var mealReminderMenuItems: [NSMenuItem] = []
    private var restReminderMenuItems: [NSMenuItem] = []
    private var idleReminderMenuItems: [NSMenuItem] = []
    private var launchAtLoginMenuItems: [NSMenuItem] = []

    init(spriteStore: SpriteStore) {
        self.spriteStore = spriteStore

        let defaults = UserDefaults.standard
        self.defaults = defaults
        let savedScale = defaults.object(forKey: Self.scaleDefaultsKey) as? Double
        self.scale = Self.clampedScale(CGFloat(savedScale ?? Self.defaultScale))
        let savedOpacity = defaults.object(forKey: Self.opacityDefaultsKey) as? Double
        self.opacity = Self.clampedOpacity(CGFloat(savedOpacity ?? Self.defaultOpacity))
        self.mode = PetMode.savedValue(defaults.string(forKey: Self.modeDefaultsKey))
        self.reminderSettings = ReminderSettings.load(from: defaults)

        let displaySize = Self.displaySize(for: self.scale)
        let origin = Self.initialDockOrigin(windowSize: displaySize)

        self.petView = PetView(frame: CGRect(origin: .zero, size: displaySize))
        self.window = NSWindow(
            contentRect: CGRect(origin: origin, size: displaySize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.bubbleView = ReminderBubbleView(frame: CGRect(origin: .zero, size: CGSize(width: 220, height: 72)))
        self.bubbleWindow = NSWindow(
            contentRect: CGRect(origin: origin, size: CGSize(width: 220, height: 72)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        super.init()

        configureWindow()
        configureBubbleWindow()
        configureViewCallbacks()
        applyModeInteractivity()
        applyAppearance(anchor: .bottomCenter, persist: false)
        show(action: mode.defaultAction)
    }

    func start() {
        snapWindowForCurrentMode(centered: mode == .companion)
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
        if mode.usesRestCorner {
            startRestCornerAction(.eat)
            return
        }
        eatLoopsRemaining = 1
        switchTo(.eat)
    }

    @objc func scratchNow() {
        recordInteraction()
        clearHover()
        if mode.usesRestCorner {
            startRestCornerAction(.scratch)
            return
        }
        scratchLoopsRemaining = 1
        switchTo(.scratch)
    }

    @objc func teaserNow() {
        recordInteraction()
        clearHover()
        if mode.usesRestCorner {
            wakeRestCornerRandomly()
            return
        }
        switchTo(.teaser)
    }

    @objc func sleepNow() {
        recordInteraction()
        clearHover()
        lastRestReminderDate = Date()
        if mode.usesRestCorner {
            snapWindowToRestCorner()
        }
        sleepLoopsRemaining = 2
        switchTo(.sleep)
    }

    @objc func petNow() {
        recordInteraction()
        clearHover()
        if mode.usesRestCorner {
            wakeRestCornerRandomly()
            return
        }
        petLoopsRemaining = 1
        switchTo(.pet)
    }

    @objc func walkRightNow() {
        recordInteraction()
        clearHover()
        if mode.usesRestCorner {
            wakeRestCornerRandomly()
            return
        }
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        switchTo(.walk)
    }

    @objc func walkLeftNow() {
        recordInteraction()
        clearHover()
        if mode.usesRestCorner {
            wakeRestCornerRandomly()
            return
        }
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        switchTo(.walkLeft)
    }

    @objc func dragPreviewNow() {
        recordInteraction()
        clearHover()
        if mode.usesRestCorner {
            wakeRestCornerRandomly()
            return
        }
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

    @objc func openReminderSettings(_ sender: Any?) {
        let controller: ReminderSettingsWindowController
        if let existing = reminderSettingsWindowController {
            existing.update(settings: reminderSettings)
            controller = existing
        } else {
            controller = ReminderSettingsWindowController(settings: reminderSettings) { [weak self] settings in
                self?.setReminderSettings(settings, persist: true)
            }
            reminderSettingsWindowController = controller
        }
        controller.show()
    }

    @objc func toggleMealReminders(_ sender: NSMenuItem) {
        var next = reminderSettings
        next.mealRemindersEnabled.toggle()
        setReminderSettings(next, persist: true)
    }

    @objc func toggleRestReminders(_ sender: NSMenuItem) {
        var next = reminderSettings
        next.restRemindersEnabled.toggle()
        setReminderSettings(next, persist: true)
    }

    @objc func toggleIdleReminders(_ sender: NSMenuItem) {
        var next = reminderSettings
        next.idleRemindersEnabled.toggle()
        setReminderSettings(next, persist: true)
    }

    @objc func previewMealReminder(_ sender: Any?) {
        recordInteraction()
        clearHover()
        pendingReminderBubbleMessage = Self.randomMealReminderMessage()
        eatLoopsRemaining = 2
        moveToDockEdgeThen(.eat)
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let nextEnabled = !LoginItemManager.isEnabled
        do {
            try LoginItemManager.setEnabled(nextEnabled)
            updateLaunchAtLoginControls()
            if LoginItemManager.status == .requiresApproval {
                showLaunchAtLoginApprovalAlert()
            }
        } catch {
            showLaunchAtLoginError(error)
        }
    }

    @objc func openLoginItemsSettings(_ sender: Any?) {
        LoginItemManager.openSystemSettings()
    }

    @objc func returnToDock() {
        recordInteraction()
        followsDock = true
        clearHover()
        dragActive = false
        snapWindowForCurrentMode(centered: false)
        resumeForMode(preferred: .walk)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Return to Dock", action: #selector(returnToDock), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(makeModeMenuItem())
        menu.addItem(makeRemindersMenuItem())
        menu.addItem(makeLaunchAtLoginMenuItem())
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
        updateReminderControls()
        updateLaunchAtLoginControls()
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

    private func configureBubbleWindow() {
        bubbleWindow.isOpaque = false
        bubbleWindow.backgroundColor = .clear
        bubbleWindow.hasShadow = false
        bubbleWindow.level = .statusBar
        bubbleWindow.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        bubbleWindow.ignoresMouseEvents = true
        bubbleWindow.contentView = bubbleView
        bubbleWindow.isReleasedWhenClosed = false
        bubbleWindow.alphaValue = 0
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
            guard mode == .companion else { return }
            recordInteraction()
            clearHover()
            dragActive = true
            followsDock = false
            pendingDockEdgeAction = nil
            switchTo(.drag)
        }

        petView.onDragged = { [weak self] origin in
            guard let self, dragActive else { return }
            recordInteraction()
            window.setFrameOrigin(origin)
        }

        petView.onDragEnded = { [weak self] in
            guard let self else { return }
            guard dragActive else { return }
            recordInteraction()
            dragActive = false
            clearHover()
            resumeForMode(preferred: .walk)
        }

        petView.onClicked = { [weak self] in
            self?.handlePetClick()
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

    private func makeRemindersMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Reminders", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Reminders")

        let summaryItem = NSMenuItem(title: reminderSummaryTitle(), action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        reminderSummaryItems.append(summaryItem)
        submenu.addItem(summaryItem)
        submenu.addItem(.separator())

        let mealItem = NSMenuItem(title: "Meal Reminders", action: #selector(toggleMealReminders(_:)), keyEquivalent: "")
        mealItem.target = self
        mealReminderMenuItems.append(mealItem)
        submenu.addItem(mealItem)

        let restItem = NSMenuItem(title: "Rest Reminders", action: #selector(toggleRestReminders(_:)), keyEquivalent: "")
        restItem.target = self
        restReminderMenuItems.append(restItem)
        submenu.addItem(restItem)

        let idleItem = NSMenuItem(title: "Idle Check-ins", action: #selector(toggleIdleReminders(_:)), keyEquivalent: "")
        idleItem.target = self
        idleReminderMenuItems.append(idleItem)
        submenu.addItem(idleItem)

        submenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Reminder Settings...", action: #selector(openReminderSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        submenu.addItem(settingsItem)

        let previewItem = NSMenuItem(title: "Preview Meal Reminder", action: #selector(previewMealReminder(_:)), keyEquivalent: "")
        previewItem.target = self
        submenu.addItem(previewItem)

        parent.submenu = submenu
        return parent
    }

    private func makeLaunchAtLoginMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Launch at Login")

        let toggleItem = NSMenuItem(title: LoginItemManager.menuTitle, action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        toggleItem.target = self
        launchAtLoginMenuItems.append(toggleItem)
        submenu.addItem(toggleItem)

        let settingsItem = NSMenuItem(title: "Open Login Items Settings...", action: #selector(openLoginItemsSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        submenu.addItem(settingsItem)

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
        let anchor: AppearanceAnchor
        if mode.usesRestCorner && !dragActive {
            anchor = .restCorner
        } else if followsDock && !dragActive {
            anchor = .dock
        } else {
            anchor = .bottomCenter
        }
        applyAppearance(anchor: anchor, persist: persist)
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
        case .restCorner:
            if let screen = window.screen ?? NSScreen.main {
                nextFrame.origin = Self.restCornerOrigin(for: screen, windowSize: nextSize)
            } else {
                nextFrame.origin.x = currentFrame.midX - nextSize.width / 2
            }
        case .none:
            break
        }

        window.setFrame(nextFrame, display: true)
        petView.frame = CGRect(origin: .zero, size: nextSize)
        if bubbleWindow.isVisible {
            positionBubbleWindow()
        }
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
        snapWindowForCurrentMode(centered: false)

        switch mode {
        case .focus:
            lastRestReminderDate = Date()
            sleepLoopsRemaining = 0
            switchTo(.sleep)
        case .companion:
            if action == .sleep {
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

    private func setReminderSettings(_ nextSettings: ReminderSettings, persist: Bool) {
        reminderSettings = nextSettings.normalized()
        triggeredMealReminderKeys.removeAll()
        lastReminderDate = Date.distantPast
        lastRestReminderDate = Date()
        if persist {
            reminderSettings.save(to: defaults)
        }
        updateReminderControls()
        reminderSettingsWindowController?.update(settings: reminderSettings)
    }

    private func updateReminderControls() {
        for item in reminderSummaryItems {
            item.title = reminderSummaryTitle()
        }
        for item in mealReminderMenuItems {
            item.state = reminderSettings.mealRemindersEnabled ? .on : .off
        }
        for item in restReminderMenuItems {
            item.state = reminderSettings.restRemindersEnabled ? .on : .off
        }
        for item in idleReminderMenuItems {
            item.state = reminderSettings.idleRemindersEnabled ? .on : .off
        }
    }

    private func updateLaunchAtLoginControls() {
        for item in launchAtLoginMenuItems {
            item.title = LoginItemManager.menuTitle
            item.state = LoginItemManager.isEnabled ? .on : .off
            item.isEnabled = LoginItemManager.status != .notFound
        }
    }

    private func showLaunchAtLoginApprovalAlert() {
        let alert = NSAlert()
        alert.messageText = "Launch at Login needs approval"
        alert.informativeText = "macOS needs you to approve Desktop Pet in Login Items before it can start automatically."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            LoginItemManager.openSystemSettings()
        }
    }

    private func showLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not update Launch at Login"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            LoginItemManager.openSystemSettings()
        }
        updateLaunchAtLoginControls()
    }

    private func reminderSummaryTitle() -> String {
        "Meals \(reminderSettings.mealSummary) | Rest \(reminderSettings.restSummary) | Idle \(reminderSettings.idleSummary)"
    }

    private func recordInteraction() {
        lastInteractionDate = Date()
    }

    private func handlePetClick() {
        recordInteraction()
        clearHover()
        dragActive = false
        pendingDockEdgeAction = nil

        if mode.usesRestCorner {
            wakeRestCornerRandomly()
            return
        }

        if action == .sleep {
            resumeWalking(preferred: .walk)
        }
    }

    private func wakeRestCornerRandomly() {
        startRestCornerAction(Bool.random() ? .eat : .scratch)
    }

    private func startRestCornerAction(_ nextAction: PetAction) {
        snapWindowToRestCorner()
        switch nextAction {
        case .scratch:
            scratchLoopsRemaining = 1
            switchTo(.scratch)
        case .eat:
            eatLoopsRemaining = 1
            switchTo(.eat)
        case .sleep:
            sleepLoopsRemaining = 0
            switchTo(.sleep)
        case .teaser, .drag, .pet, .walk, .walkLeft:
            eatLoopsRemaining = 1
            switchTo(.eat)
        }
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
        guard reminderSettings.mealRemindersEnabled else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }

        let minuteOfDay = hour * 60 + minute
        for (mealIndex, mealMinute) in reminderSettings.mealMinutes.enumerated() {
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
            let key = "\(day)-\(mealIndex)-\(mealMinute)"
            if !triggeredMealReminderKeys.contains(key) {
                return key
            }
        }

        return nil
    }

    private func shouldTriggerRestReminder(at date: Date) -> Bool {
        guard reminderSettings.restRemindersEnabled else { return false }
        guard mode == .companion else { return false }
        return date.timeIntervalSince(lastRestReminderDate) >= TimeInterval(reminderSettings.restIntervalMinutes * 60)
    }

    private func shouldTriggerIdleReminder(at date: Date) -> Bool {
        guard reminderSettings.idleRemindersEnabled else { return false }
        guard mode == .companion else { return false }
        let interval = TimeInterval(reminderSettings.idleIntervalMinutes * 60)
        guard date.timeIntervalSince(lastInteractionDate) >= interval else { return false }
        return date.timeIntervalSince(lastIdleReminderDate) >= interval
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
        pendingReminderBubbleMessage = Self.randomMealReminderMessage()
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
        showReminderBubble(Self.randomRestReminderMessage())
    }

    private func triggerIdleReminder(at date: Date) {
        lastReminderDate = date
        lastIdleReminderDate = date
        clearHover()
        pendingDockEdgeAction = nil
        petLoopsRemaining = 1
        switchTo(.pet)
        showReminderBubble(Self.randomIdleReminderMessage())
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

    private func showPendingReminderBubbleIfNeeded() {
        guard let message = pendingReminderBubbleMessage else { return }
        pendingReminderBubbleMessage = nil
        showReminderBubble(message)
    }

    private func showReminderBubble(_ message: String) {
        bubbleTimer?.invalidate()
        let size = bubbleView.update(message: message)
        bubbleWindow.setFrame(CGRect(origin: bubbleWindow.frame.origin, size: size), display: true)
        positionBubbleWindow()
        bubbleWindow.alphaValue = 0
        bubbleWindow.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            bubbleWindow.animator().alphaValue = 1
        }

        bubbleTimer = Timer.scheduledTimer(withTimeInterval: Self.bubbleDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideReminderBubble()
            }
        }
        if let bubbleTimer {
            RunLoop.main.add(bubbleTimer, forMode: .common)
        }
    }

    private func hideReminderBubble() {
        bubbleTimer?.invalidate()
        bubbleTimer = nil

        guard bubbleWindow.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            bubbleWindow.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.bubbleWindow.orderOut(nil)
            }
        }
    }

    private func positionBubbleWindow() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let bubbleSize = bubbleWindow.frame.size
        let petFrame = window.frame

        var origin = CGPoint(
            x: petFrame.midX - bubbleSize.width / 2,
            y: petFrame.maxY - 8
        )

        if origin.y + bubbleSize.height > visible.maxY - Self.bubbleScreenInset {
            origin.y = petFrame.minY - bubbleSize.height + 18
        }

        origin.x = min(
            max(origin.x, visible.minX + Self.bubbleScreenInset),
            visible.maxX - bubbleSize.width - Self.bubbleScreenInset
        )
        origin.y = min(
            max(origin.y, visible.minY + Self.bubbleScreenInset),
            visible.maxY - bubbleSize.height - Self.bubbleScreenInset
        )

        bubbleWindow.setFrameOrigin(origin)
    }

    private func tick() {
        let frameCount = spriteStore.frameCount(for: action)
        guard frameCount > 0 else { return }

        if mode.usesRestCorner && !dragActive {
            snapWindowToRestCorner()
        } else if followsDock && !dragActive {
            snapWindowToDock(centered: false)
        }
        if bubbleWindow.isVisible {
            positionBubbleWindow()
        }

        if finalFrameHoldTicksRemaining > 0 {
            finalFrameHoldTicksRemaining -= 1
            if finalFrameHoldTicksRemaining <= 0 {
                finishActionLoop()
            }
            return
        }

        if let image = spriteStore.image(for: action, index: frameIndex) {
            petView.image = image
        }
        moveIfNeeded()

        frameIndex += 1
        if frameIndex >= frameCount {
            let holdTicks = finalFrameHoldTicks(for: action)
            if holdTicks > 0 {
                frameIndex = frameCount - 1
                finalFrameHoldTicksRemaining = holdTicks
            } else {
                finishActionLoop()
            }
        }
    }

    private func finishActionLoop() {
        finalFrameHoldTicksRemaining = 0
        frameIndex = 0
        loopCount += 1
        decideAfterLoop()
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
            if mode.usesRestCorner {
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
        if mode.usesRestCorner {
            snapWindowToRestCorner()
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
            showPendingReminderBubbleIfNeeded()
            return
        }

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
        showPendingReminderBubbleIfNeeded()
    }

    private func resumeWalking(preferred: PetAction) {
        automaticWalkLoopsRemaining = Int.random(in: 10...18)
        switchTo(preferred.isWalking ? preferred : .walk)
    }

    private func resumeForMode(preferred: PetAction) {
        pendingDockEdgeAction = nil

        switch mode {
        case .focus:
            sleepLoopsRemaining = 0
            snapWindowToRestCorner()
            switchTo(.sleep)
        case .companion:
            resumeWalking(preferred: preferred)
        }
    }

    private func switchTo(_ next: PetAction) {
        guard action != next else { return }
        action = next
        frameIndex = 0
        loopCount = 0
        finalFrameHoldTicksRemaining = 0
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

    private func snapWindowForCurrentMode(centered: Bool) {
        if mode.usesRestCorner {
            snapWindowToRestCorner()
        } else {
            snapWindowToDock(centered: centered)
        }
    }

    private func snapWindowToRestCorner() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        window.setFrameOrigin(Self.restCornerOrigin(for: screen, windowSize: window.frame.size))
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

    private static func restCornerOrigin(for screen: NSScreen, windowSize: CGSize) -> CGPoint {
        let visible = screen.visibleFrame
        return CGPoint(
            x: visible.maxX - windowSize.width - restCornerInset,
            y: visible.minY + restCornerInset
        )
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

    private func finalFrameHoldTicks(for action: PetAction) -> Int {
        Int(round(action.finalFrameHoldDuration * action.framesPerSecond))
    }

    private static func randomMealReminderMessage() -> String {
        [
            "到饭点啦，好好吃饭。",
            "猫猫开饭啦，你也要认真吃饭。",
            "先去吃点热乎的吧，别饿着自己。",
            "休息一下吃饭啦，身体也要被照顾。"
        ].randomElement() ?? "到饭点啦，好好吃饭。"
    }

    private static func randomRestReminderMessage() -> String {
        [
            "休息一下吧，眼睛也需要放松。",
            "猫猫先睡会儿，你也缓一缓。",
            "工作暂停一下，伸个懒腰。"
        ].randomElement() ?? "休息一下吧，眼睛也需要放松。"
    }

    private static func randomIdleReminderMessage() -> String {
        [
            "忙太久啦，摸摸猫猫放松一下。",
            "猫猫在看你，记得喝水休息。",
            "歇一小会儿，再继续也不迟。"
        ].randomElement() ?? "忙太久啦，摸摸猫猫放松一下。"
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
        case restCorner
        case none
    }
}
