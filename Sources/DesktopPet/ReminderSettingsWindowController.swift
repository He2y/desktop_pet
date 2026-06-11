import AppKit

@MainActor
final class ReminderSettingsWindowController: NSWindowController {
    private let onSave: (ReminderSettings) -> Void
    private var settings: ReminderSettings

    private let mealCheckbox = NSButton(checkboxWithTitle: "Meal reminders", target: nil, action: nil)
    private let restCheckbox = NSButton(checkboxWithTitle: "Rest reminders", target: nil, action: nil)
    private let idleCheckbox = NSButton(checkboxWithTitle: "Idle check-ins", target: nil, action: nil)
    private let breakfastField = NSTextField()
    private let lunchField = NSTextField()
    private let dinnerField = NSTextField()
    private let restIntervalField = NSTextField()
    private let idleIntervalField = NSTextField()
    private let messageLabel = NSTextField(labelWithString: "")

    init(settings: ReminderSettings, onSave: @escaping (ReminderSettings) -> Void) {
        self.settings = settings.normalized()
        self.onSave = onSave

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 390, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Reminder Settings"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.center()

        super.init(window: panel)

        panel.contentView = makeContentView()
        populateFields()
        updateEnabledControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        populateFields()
        updateEnabledControls()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(settings: ReminderSettings) {
        self.settings = settings.normalized()
        populateFields()
        updateEnabledControls()
    }

    @objc private func enabledCheckboxChanged(_ sender: NSButton) {
        updateEnabledControls()
    }

    @objc private func saveButtonClicked(_ sender: NSButton) {
        guard let nextSettings = readSettingsFromFields() else { return }
        settings = nextSettings
        onSave(nextSettings)
        window?.close()
    }

    @objc private func resetButtonClicked(_ sender: NSButton) {
        settings = .defaults
        populateFields()
        updateEnabledControls()
        messageLabel.stringValue = ""
    }

    @objc private func cancelButtonClicked(_ sender: NSButton) {
        window?.close()
    }

    private func makeContentView() -> NSView {
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 390, height: 330))

        let title = NSTextField(labelWithString: "Life Reminders")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.frame = CGRect(x: 22, y: 292, width: 260, height: 22)
        content.addSubview(title)

        mealCheckbox.target = self
        mealCheckbox.action = #selector(enabledCheckboxChanged(_:))
        mealCheckbox.frame = CGRect(x: 22, y: 254, width: 180, height: 22)
        content.addSubview(mealCheckbox)

        addLabel("Breakfast", x: 40, y: 222, to: content)
        configureTimeField(breakfastField, x: 122, y: 218, in: content)
        addLabel("Lunch", x: 40, y: 190, to: content)
        configureTimeField(lunchField, x: 122, y: 186, in: content)
        addLabel("Dinner", x: 40, y: 158, to: content)
        configureTimeField(dinnerField, x: 122, y: 154, in: content)

        restCheckbox.target = self
        restCheckbox.action = #selector(enabledCheckboxChanged(_:))
        restCheckbox.frame = CGRect(x: 22, y: 116, width: 160, height: 22)
        content.addSubview(restCheckbox)
        configureMinuteField(restIntervalField, x: 194, y: 112, in: content)
        addLabel("minutes", x: 264, y: 116, width: 70, to: content)

        idleCheckbox.target = self
        idleCheckbox.action = #selector(enabledCheckboxChanged(_:))
        idleCheckbox.frame = CGRect(x: 22, y: 82, width: 160, height: 22)
        content.addSubview(idleCheckbox)
        configureMinuteField(idleIntervalField, x: 194, y: 78, in: content)
        addLabel("minutes", x: 264, y: 82, width: 70, to: content)

        messageLabel.textColor = .systemRed
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.frame = CGRect(x: 22, y: 51, width: 346, height: 18)
        content.addSubview(messageLabel)

        let resetButton = NSButton(title: "Reset Defaults", target: self, action: #selector(resetButtonClicked(_:)))
        resetButton.frame = CGRect(x: 22, y: 18, width: 118, height: 28)
        content.addSubview(resetButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelButtonClicked(_:)))
        cancelButton.frame = CGRect(x: 210, y: 18, width: 72, height: 28)
        content.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveButtonClicked(_:)))
        saveButton.keyEquivalent = "\r"
        saveButton.frame = CGRect(x: 292, y: 18, width: 76, height: 28)
        content.addSubview(saveButton)

        return content
    }

    private func populateFields() {
        let normalized = settings.normalized()
        mealCheckbox.state = normalized.mealRemindersEnabled ? .on : .off
        restCheckbox.state = normalized.restRemindersEnabled ? .on : .off
        idleCheckbox.state = normalized.idleRemindersEnabled ? .on : .off
        breakfastField.stringValue = ReminderSettings.formatTime(normalized.mealMinutes[0])
        lunchField.stringValue = ReminderSettings.formatTime(normalized.mealMinutes[1])
        dinnerField.stringValue = ReminderSettings.formatTime(normalized.mealMinutes[2])
        restIntervalField.stringValue = "\(normalized.restIntervalMinutes)"
        idleIntervalField.stringValue = "\(normalized.idleIntervalMinutes)"
        messageLabel.stringValue = ""
    }

    private func updateEnabledControls() {
        let mealEnabled = mealCheckbox.state == .on
        breakfastField.isEnabled = mealEnabled
        lunchField.isEnabled = mealEnabled
        dinnerField.isEnabled = mealEnabled
        restIntervalField.isEnabled = restCheckbox.state == .on
        idleIntervalField.isEnabled = idleCheckbox.state == .on
    }

    private func readSettingsFromFields() -> ReminderSettings? {
        guard
            let breakfast = ReminderSettings.parseTime(breakfastField.stringValue),
            let lunch = ReminderSettings.parseTime(lunchField.stringValue),
            let dinner = ReminderSettings.parseTime(dinnerField.stringValue)
        else {
            messageLabel.stringValue = "Use 24-hour time, for example 08:00 or 18:30."
            return nil
        }

        guard let restMinutes = Int(restIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            messageLabel.stringValue = "Rest reminder minutes must be a number."
            return nil
        }

        guard let idleMinutes = Int(idleIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            messageLabel.stringValue = "Idle check-in minutes must be a number."
            return nil
        }

        guard ReminderSettings.restIntervalRange.contains(restMinutes) else {
            messageLabel.stringValue = "Rest reminder must be 5-240 minutes."
            return nil
        }

        guard ReminderSettings.idleIntervalRange.contains(idleMinutes) else {
            messageLabel.stringValue = "Idle check-in must be 3-180 minutes."
            return nil
        }

        return ReminderSettings(
            mealRemindersEnabled: mealCheckbox.state == .on,
            restRemindersEnabled: restCheckbox.state == .on,
            idleRemindersEnabled: idleCheckbox.state == .on,
            mealMinutes: [breakfast, lunch, dinner],
            restIntervalMinutes: restMinutes,
            idleIntervalMinutes: idleMinutes
        ).normalized()
    }

    private func configureTimeField(_ field: NSTextField, x: CGFloat, y: CGFloat, in content: NSView) {
        field.frame = CGRect(x: x, y: y, width: 82, height: 24)
        field.placeholderString = "08:00"
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        content.addSubview(field)
    }

    private func configureMinuteField(_ field: NSTextField, x: CGFloat, y: CGFloat, in content: NSView) {
        field.frame = CGRect(x: x, y: y, width: 58, height: 24)
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        content.addSubview(field)
    }

    private func addLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 74, to content: NSView) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.frame = CGRect(x: x, y: y, width: width, height: 18)
        content.addSubview(label)
    }
}
