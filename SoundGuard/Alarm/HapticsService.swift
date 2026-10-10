import CoreHaptics
import Foundation
import UIKit

final class HapticsService {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var enabled = true
    private var running = false

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled { stop() }
    }

    func startAlarmPattern() {
        guard enabled else { return }
        running = true
        if player != nil { return }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                engine?.resetHandler = { [weak self] in
                    try? self?.engine?.start()
                    self?.player = nil
                    if self?.running == true {
                        self?.startAlarmPattern()
                    }
                }
                engine?.stoppedHandler = { [weak self] _ in
                    self?.player = nil
                }
                engine?.notifyWhenPlayersFinished { [weak self] _ in
                    guard let self, self.running else { return .stopEngine }
                    self.player = nil
                    self.startAlarmPattern()
                    return .leaveEngineRunning
                }
            }
            try engine?.start()
            let pattern = try Self.makePattern()
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
            self.player = player
        } catch {
            let fallback = UINotificationFeedbackGenerator()
            fallback.notificationOccurred(.error)
        }
    }

    func stop() {
        running = false
        try? player?.stop(atTime: 0)
        player = nil
        engine?.stop(completionHandler: nil)
    }

    private static func makePattern() throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        var time: TimeInterval = 0
        for i in 0..<8 {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: i % 2 == 0 ? 1.0 : 0.7)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: i % 2 == 0 ? 0.9 : 0.4)
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: time
                )
            )
            time += 0.16
            events.append(
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: time,
                    duration: 0.12
                )
            )
            time += 0.18
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
