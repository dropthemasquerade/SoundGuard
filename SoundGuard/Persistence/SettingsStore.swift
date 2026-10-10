import Foundation
import Observation

@Observable
@MainActor
final class SettingsStore {
    var similarityThreshold: Double {
        didSet { defaults.set(similarityThreshold, forKey: Keys.threshold) }
    }
    var consecutiveHits: Int {
        didSet { defaults.set(consecutiveHits, forKey: Keys.hits) }
    }
    var resumeAfterReset: Bool {
        didSet { defaults.set(resumeAfterReset, forKey: Keys.resumeReset) }
    }
    var resumeAfterInterrupt: Bool {
        didSet { defaults.set(resumeAfterInterrupt, forKey: Keys.resumeInterrupt) }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    var alarmVolume: Double {
        didSet { defaults.set(alarmVolume, forKey: Keys.volume) }
    }
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }
    var scheduleEnabled: Bool {
        didSet { defaults.set(scheduleEnabled, forKey: Keys.scheduleEnabled) }
    }
    var windowStartMinutes: Int {
        didSet { defaults.set(windowStartMinutes, forKey: Keys.windowStart) }
    }
    var windowEndMinutes: Int {
        didSet { defaults.set(windowEndMinutes, forKey: Keys.windowEnd) }
    }
    var alarmToneRaw: String {
        didSet { defaults.set(alarmToneRaw, forKey: Keys.alarmTone) }
    }

    var alarmTone: AlarmTone {
        get { AlarmTone(rawValue: alarmToneRaw) ?? .classic }
        set { alarmToneRaw = newValue.rawValue }
    }

    var monitoringWindow: MonitoringWindow {
        MonitoringWindow(
            enabled: scheduleEnabled,
            startMinutes: windowStartMinutes,
            endMinutes: windowEndMinutes
        )
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let threshold = "sg.threshold"
        static let hits = "sg.hits"
        static let resumeReset = "sg.resumeReset"
        static let resumeInterrupt = "sg.resumeInterrupt"
        static let haptics = "sg.haptics"
        static let volume = "sg.volume"
        static let notifications = "sg.notifications"
        static let scheduleEnabled = "sg.scheduleEnabled"
        static let windowStart = "sg.windowStart"
        static let windowEnd = "sg.windowEnd"
        static let alarmTone = "sg.alarmTone"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        similarityThreshold = defaults.object(forKey: Keys.threshold) as? Double ?? 0.78
        consecutiveHits = defaults.object(forKey: Keys.hits) as? Int ?? 4
        resumeAfterReset = defaults.object(forKey: Keys.resumeReset) as? Bool ?? true
        resumeAfterInterrupt = defaults.object(forKey: Keys.resumeInterrupt) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        alarmVolume = defaults.object(forKey: Keys.volume) as? Double ?? 1.0
        notificationsEnabled = defaults.object(forKey: Keys.notifications) as? Bool ?? true
        scheduleEnabled = defaults.object(forKey: Keys.scheduleEnabled) as? Bool ?? false
        windowStartMinutes = defaults.object(forKey: Keys.windowStart) as? Int ?? 8 * 60
        windowEndMinutes = defaults.object(forKey: Keys.windowEnd) as? Int ?? 22 * 60
        alarmToneRaw = defaults.string(forKey: Keys.alarmTone) ?? AlarmTone.classic.rawValue
    }

    func apply(to parameters: inout DetectionParameters) {
        parameters.similarityThreshold = Float(similarityThreshold)
        parameters.consecutiveHits = max(2, consecutiveHits)
    }
}
