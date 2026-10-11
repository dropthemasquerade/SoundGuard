import Foundation

enum AppEvent: Equatable {
    case startTapped
    case stopTapped
    case permissionGranted
    case permissionDenied
    case captureStarted
    case captureFailed(String)
    case targetDetected(AlarmSnapshot)
    case acknowledgeTapped
    case resetTapped
    case resetCompleted
    case interruptionBegan
    case interruptionEnded
    case windowClosed
    case windowOpened
    case restoreUnacked(AlarmSnapshot)
    case restoreAcked(AlarmSnapshot)
}

enum AppCommand: Equatable {
    case requestPermission
    case startCapture
    case stopCapture
    case enterStandby
    case leaveStandby
    case startAlarm(AlarmSnapshot)
    case stopAlarm
    case persistDetection(AlarmSnapshot)
    case persistAcknowledgement
    case persistReset
}

struct AppMachineState: Equatable {
    var phase: AppPhase = .idle
    var resumeAfterReset: Bool = true
    var resumeAfterInterrupt: Bool = true
    var activeAlarm: AlarmSnapshot?
    var lastError: String?
}

struct AppStateMachine {
    private(set) var state = AppMachineState()

    mutating func setResumeFlags(afterReset: Bool, afterInterrupt: Bool) {
        state.resumeAfterReset = afterReset
        state.resumeAfterInterrupt = afterInterrupt
    }

    mutating func clearError() {
        state.lastError = nil
    }

    mutating func clearActiveAlarm() {
        state.activeAlarm = nil
    }

    @discardableResult
    mutating func handle(_ event: AppEvent) -> [AppCommand] {
        switch (state.phase, event) {
        case (.idle, .startTapped), (.permissionDenied, .startTapped), (.interrupted, .startTapped):
            state.lastError = nil
            return [.requestPermission]

        case (.idle, .permissionGranted), (.permissionDenied, .permissionGranted), (.interrupted, .permissionGranted):
            state.phase = .monitoring
            state.lastError = nil
            return [.startCapture]

        case (_, .permissionDenied):
            state.phase = .permissionDenied
            state.activeAlarm = nil
            return [.stopCapture, .stopAlarm]

        case (.monitoring, .captureStarted):
            return []

        case (.monitoring, .captureFailed(let message)), (.idle, .captureFailed(let message)):
            state.phase = .idle
            state.lastError = message
            return [.stopCapture]

        case (.monitoring, .stopTapped), (.interrupted, .stopTapped), (.outsideWindow, .stopTapped):
            state.phase = .idle
            return [.leaveStandby, .stopCapture]

        case (.alarming, .stopTapped):
            // Stay disarmed. Reset would listen again and the sound still in the room
            // would latch another alarm before the user can change the target.
            state.phase = .idle
            return [.stopAlarm, .persistAcknowledgement, .persistReset, .leaveStandby, .stopCapture]

        case (.acknowledged, .stopTapped):
            state.phase = .idle
            return [.stopAlarm, .persistReset, .leaveStandby, .stopCapture]

        case (.monitoring, .windowClosed):
            state.phase = .outsideWindow
            return [.stopCapture, .enterStandby]

        case (.outsideWindow, .windowOpened):
            state.phase = .monitoring
            return [.leaveStandby, .startCapture]

        case (.outsideWindow, .interruptionBegan):
            state.phase = .interrupted
            return [.leaveStandby, .stopCapture]

        case (.monitoring, .targetDetected(let snapshot)):
            state.phase = .alarming
            state.activeAlarm = snapshot
            return [.stopCapture, .startAlarm(snapshot), .persistDetection(snapshot)]

        case (.alarming, .targetDetected), (.acknowledged, .targetDetected), (.resetting, .targetDetected):
            return []

        case (.alarming, .acknowledgeTapped):
            state.phase = .acknowledged
            return [.stopAlarm, .persistAcknowledgement]

        case (.acknowledged, .acknowledgeTapped):
            return []

        case (.alarming, .resetTapped):
            state.phase = .resetting
            return [.stopAlarm, .persistAcknowledgement, .persistReset]

        case (.acknowledged, .resetTapped):
            state.phase = .resetting
            return [.persistReset]

        case (.resetting, .resetTapped):
            return []

        case (.resetting, .resetCompleted):
            state.activeAlarm = nil
            if state.resumeAfterReset {
                state.phase = .monitoring
                return [.startCapture]
            }
            state.phase = .idle
            return [.leaveStandby, .stopCapture]

        case (.monitoring, .interruptionBegan):
            state.phase = .interrupted
            return [.stopCapture]

        case (.interrupted, .interruptionEnded):
            if state.resumeAfterInterrupt {
                state.phase = .monitoring
                return [.startCapture]
            }
            state.phase = .idle
            return [.leaveStandby, .stopCapture]

        case (.alarming, .interruptionBegan), (.alarming, .interruptionEnded),
             (.acknowledged, .interruptionBegan), (.acknowledged, .interruptionEnded):
            return []

        case (.idle, .restoreUnacked(let snapshot)),
             (.monitoring, .restoreUnacked(let snapshot)),
             (.permissionDenied, .restoreUnacked(let snapshot)),
             (.interrupted, .restoreUnacked(let snapshot)):
            state.phase = .alarming
            state.activeAlarm = snapshot
            return [.stopCapture, .startAlarm(snapshot)]

        case (.idle, .restoreAcked(let snapshot)),
             (.monitoring, .restoreAcked(let snapshot)),
             (.permissionDenied, .restoreAcked(let snapshot)),
             (.interrupted, .restoreAcked(let snapshot)):
            state.phase = .acknowledged
            state.activeAlarm = snapshot
            return [.stopCapture, .stopAlarm]

        default:
            return []
        }
    }
}
