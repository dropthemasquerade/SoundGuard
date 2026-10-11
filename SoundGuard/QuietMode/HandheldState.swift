import Foundation

/// Estimate only. Motion cannot prove the phone is in a hand.
enum HandheldState: String, Equatable {
    case handheld
    case placed
    case unknown
}

/// What to do with alarm output while the phone seems handheld.
enum QuietModeBehavior: String, CaseIterable, Identifiable {
    case recordOnly
    case screenHint
    case resumeWhenPlaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recordOnly: return "RECORD ONLY"
        case .screenHint: return "SCREEN HINT"
        case .resumeWhenPlaced: return "RESUME WHEN SET DOWN"
        }
    }

    var detail: String {
        switch self {
        case .recordOnly: return "Log the event. Hide the alarm screen and sound."
        case .screenHint: return "Show the alarm screen and hold the sound."
        case .resumeWhenPlaced: return "Hold the alarm until the phone seems set down."
        }
    }
}

enum QuietPosture: Equatable {
    /// The quiet-mode switch is off. Alarm output follows the original path.
    case off
    case handheldQuiet
    case alertsOn
    case uncertain
}

struct AlertOutput: Equatable {
    var playAudio: Bool
    var playHaptics: Bool
    var showFullAlarm: Bool
    var posture: QuietPosture

    static let idle = AlertOutput(playAudio: false, playHaptics: false, showFullAlarm: false, posture: .off)
}
