import Foundation

enum AppPhase: Equatable {
    case idle
    case monitoring
    case outsideWindow
    case alarming
    case acknowledged
    case resetting
    case permissionDenied
    case interrupted

    var codeName: String {
        switch self {
        case .idle: return "IDLE"
        case .monitoring: return "MONITORING"
        case .outsideWindow: return "STANDBY"
        case .alarming: return "ALARMING"
        case .acknowledged: return "ACKNOWLEDGED"
        case .resetting: return "RESETTING"
        case .permissionDenied: return "NO MIC"
        case .interrupted: return "INTERRUPTED"
        }
    }

    var isAlarmSurface: Bool {
        self == .alarming || self == .acknowledged || self == .resetting
    }
}

struct AlarmSnapshot: Equatable, Identifiable {
    var id: UUID
    var soundName: String
    var detectedAt: Date
    var confidence: Double
}

enum SoundProfile: String, Codable, CaseIterable, Identifiable {
    case beep
    case alarm
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beep: return "BEEP"
        case .alarm: return "SIREN"
        case .custom: return "CUSTOM"
        }
    }

    var detail: String {
        switch self {
        case .beep: return "Short stable tones"
        case .alarm: return "Repeating alerts"
        case .custom: return "General reference"
        }
    }
}
