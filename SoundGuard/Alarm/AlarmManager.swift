import Foundation

@MainActor
final class AlarmManager {
    private let audio = AlertAudioService()
    private let haptics = HapticsService()
    private let notifications = NotificationService()
    private var isAlarming = false
    private var activeID: UUID?

    var isActive: Bool { isAlarming }

    func configure(volume: Double, hapticsEnabled: Bool, notificationsEnabled: Bool) {
        audio.setVolume(volume)
        haptics.setEnabled(hapticsEnabled)
        notifications.setEnabled(notificationsEnabled)
    }

    func prepareNotifications() {
        notifications.requestAuthorization()
    }

    func start(snapshot: AlarmSnapshot, volume: Double, hapticsEnabled: Bool, notificationsEnabled: Bool, tone: AlarmTone) {
        guard !isAlarming else {
            resumePlayback(volume: volume, hapticsEnabled: hapticsEnabled, tone: tone)
            return
        }
        isAlarming = true
        activeID = snapshot.id
        configure(volume: volume, hapticsEnabled: hapticsEnabled, notificationsEnabled: notificationsEnabled)
        audio.startLooping(tone: tone)
        haptics.startAlarmPattern()
        notifications.startRepeating(snapshot: snapshot)
    }

    /// Restarts alarm audio and haptics after the lock screen stalls them.
    /// Does not schedule another set of notifications.
    func resumePlayback(volume: Double, hapticsEnabled: Bool, tone: AlarmTone) {
        guard isAlarming else { return }
        audio.setVolume(volume)
        haptics.setEnabled(hapticsEnabled)
        audio.startLooping(tone: tone)
        haptics.startAlarmPattern()
    }

    func stop() {
        guard isAlarming else { return }
        isAlarming = false
        activeID = nil
        audio.stop()
        haptics.stop()
        notifications.cancelAll()
    }
}
