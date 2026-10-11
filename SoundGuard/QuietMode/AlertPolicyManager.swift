import Foundation

enum ResumeSignal: Equatable {
    case schedule(TimeInterval)
    case cancel
    case keep
}

/// Handheld transitions and the delay before a held alarm is allowed to sound again.
struct QuietSession: Equatable {
    private(set) var handheld: HandheldState = .unknown
    private(set) var holdingResume = false

    mutating func reset() {
        handheld = .unknown
        holdingResume = false
    }

    mutating func receive(_ next: HandheldState, resumeDelay: TimeInterval) -> ResumeSignal {
        let previous = handheld
        handheld = next
        if next == .unknown || next == .handheld {
            holdingResume = false
            return .cancel
        }
        if previous == .handheld && next == .placed {
            if resumeDelay <= 0 {
                holdingResume = false
                return .cancel
            }
            holdingResume = true
            return .schedule(resumeDelay)
        }
        return holdingResume ? .keep : .cancel
    }

    mutating func resumeFired() {
        holdingResume = false
    }

    mutating func userEndedAlarm() {
        holdingResume = false
    }
}

enum AlertPolicyManager {
    static func output(
        phase: AppPhase,
        quietEnabled: Bool,
        behavior: QuietModeBehavior,
        hapticsWhileQuiet: Bool,
        baseHapticsEnabled: Bool,
        handheld: HandheldState,
        holdingResume: Bool
    ) -> AlertOutput {
        let suppressAudio = quietEnabled
            && phase == .alarming
            && (handheld == .handheld || (holdingResume && handheld == .placed))

        let playAudio = phase == .alarming && !suppressAudio
        let playHaptics: Bool
        if phase != .alarming {
            playHaptics = false
        } else if suppressAudio {
            playHaptics = baseHapticsEnabled && hapticsWhileQuiet
        } else {
            playHaptics = baseHapticsEnabled
        }

        let showFullAlarm: Bool
        if phase == .acknowledged || phase == .resetting {
            showFullAlarm = true
        } else if phase != .alarming {
            showFullAlarm = false
        } else if suppressAudio {
            showFullAlarm = behavior == .screenHint
        } else {
            showFullAlarm = true
        }

        let posture: QuietPosture
        if !quietEnabled {
            posture = .off
        } else if suppressAudio || handheld == .handheld {
            posture = .handheldQuiet
        } else if handheld == .unknown {
            posture = .uncertain
        } else {
            posture = .alertsOn
        }

        return AlertOutput(
            playAudio: playAudio,
            playHaptics: playHaptics,
            showFullAlarm: showFullAlarm,
            posture: posture
        )
    }
}
