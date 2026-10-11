import Foundation

@MainActor
final class AlarmManager {
    private let audio = AlertAudioService()
    private let haptics = HapticsService()
    private let notifications = NotificationService()
    private var isAlarming = false
    private var activeID: UUID?

    var isActive: Bool { isAlarming }

    func prepareNotifications() {
        notifications.requestAuthorization()
    }

    func start(snapshot: AlarmSnapshot, volume: Double, notificationsEnabled: Bool, tone: AlarmTone, output: AlertOutput) {
        guard !isAlarming else {
            applyOutput(output, volume: volume, tone: tone)
            return
        }
        isAlarming = true
        activeID = snapshot.id
        notifications.setEnabled(notificationsEnabled)
        notifications.startRepeating(snapshot: snapshot)
        applyOutput(output, volume: volume, tone: tone)
    }

    /// Updates sound and haptics without dropping the event or its notifications.
    func applyOutput(_ output: AlertOutput, volume: Double, tone: AlarmTone) {
        guard isAlarming else { return }
        audio.setVolume(volume)
        if output.playAudio {
            audio.startLooping(tone: tone)
        } else {
            audio.stop()
        }
        haptics.setEnabled(output.playHaptics)
        if output.playHaptics {
            haptics.startAlarmPattern()
        }
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
