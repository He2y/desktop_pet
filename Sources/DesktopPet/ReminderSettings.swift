import Foundation

struct ReminderSettings: Equatable {
    static let defaultMealMinutes = [8 * 60, 12 * 60 + 30, 18 * 60 + 30]
    static let defaultRestIntervalMinutes = 50
    static let defaultIdleIntervalMinutes = 12
    static let restIntervalRange = 5...240
    static let idleIntervalRange = 3...180

    private static let mealEnabledKey = "desktopPet.reminders.meal.enabled"
    private static let restEnabledKey = "desktopPet.reminders.rest.enabled"
    private static let idleEnabledKey = "desktopPet.reminders.idle.enabled"
    private static let mealMinutesKey = "desktopPet.reminders.meal.minutes"
    private static let restIntervalKey = "desktopPet.reminders.rest.minutes"
    private static let idleIntervalKey = "desktopPet.reminders.idle.minutes"

    var mealRemindersEnabled: Bool
    var restRemindersEnabled: Bool
    var idleRemindersEnabled: Bool
    var mealMinutes: [Int]
    var restIntervalMinutes: Int
    var idleIntervalMinutes: Int

    static var defaults: ReminderSettings {
        ReminderSettings(
            mealRemindersEnabled: true,
            restRemindersEnabled: true,
            idleRemindersEnabled: true,
            mealMinutes: defaultMealMinutes,
            restIntervalMinutes: defaultRestIntervalMinutes,
            idleIntervalMinutes: defaultIdleIntervalMinutes
        )
    }

    static func load(from defaults: UserDefaults) -> ReminderSettings {
        let fallback = Self.defaults
        let mealMinutes = defaults.array(forKey: mealMinutesKey) as? [Int] ?? fallback.mealMinutes
        let restInterval = defaults.object(forKey: restIntervalKey) as? Int ?? fallback.restIntervalMinutes
        let idleInterval = defaults.object(forKey: idleIntervalKey) as? Int ?? fallback.idleIntervalMinutes

        return ReminderSettings(
            mealRemindersEnabled: defaults.object(forKey: mealEnabledKey) as? Bool ?? fallback.mealRemindersEnabled,
            restRemindersEnabled: defaults.object(forKey: restEnabledKey) as? Bool ?? fallback.restRemindersEnabled,
            idleRemindersEnabled: defaults.object(forKey: idleEnabledKey) as? Bool ?? fallback.idleRemindersEnabled,
            mealMinutes: mealMinutes,
            restIntervalMinutes: restInterval,
            idleIntervalMinutes: idleInterval
        ).normalized()
    }

    func save(to defaults: UserDefaults) {
        let normalized = normalized()
        defaults.set(normalized.mealRemindersEnabled, forKey: Self.mealEnabledKey)
        defaults.set(normalized.restRemindersEnabled, forKey: Self.restEnabledKey)
        defaults.set(normalized.idleRemindersEnabled, forKey: Self.idleEnabledKey)
        defaults.set(normalized.mealMinutes, forKey: Self.mealMinutesKey)
        defaults.set(normalized.restIntervalMinutes, forKey: Self.restIntervalKey)
        defaults.set(normalized.idleIntervalMinutes, forKey: Self.idleIntervalKey)
    }

    func normalized() -> ReminderSettings {
        var next = self
        let fallbackMeals = Self.defaultMealMinutes
        let trimmedMeals = Array(mealMinutes.prefix(3))
        next.mealMinutes = (0..<3).map { index in
            let value = index < trimmedMeals.count ? trimmedMeals[index] : fallbackMeals[index]
            return min(max(value, 0), 23 * 60 + 59)
        }
        next.restIntervalMinutes = min(max(restIntervalMinutes, Self.restIntervalRange.lowerBound), Self.restIntervalRange.upperBound)
        next.idleIntervalMinutes = min(max(idleIntervalMinutes, Self.idleIntervalRange.lowerBound), Self.idleIntervalRange.upperBound)
        return next
    }

    var mealSummary: String {
        mealMinutes.map(Self.formatTime).joined(separator: " / ")
    }

    var restSummary: String {
        "\(restIntervalMinutes) min"
    }

    var idleSummary: String {
        "\(idleIntervalMinutes) min"
    }

    static func formatTime(_ minuteOfDay: Int) -> String {
        let clamped = min(max(minuteOfDay, 0), 23 * 60 + 59)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    static func parseTime(_ rawValue: String) -> Int? {
        let parts = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return nil
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }
}
