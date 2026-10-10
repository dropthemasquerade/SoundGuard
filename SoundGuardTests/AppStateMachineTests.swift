import XCTest
@testable import SoundGuard

final class AppStateMachineTests: XCTestCase {
    func testArmRequiresPermissionThenMonitors() {
        var machine = AppStateMachine()
        XCTAssertEqual(machine.handle(.startTapped), [.requestPermission])
        XCTAssertEqual(machine.state.phase, .idle)
        XCTAssertEqual(machine.handle(.permissionGranted), [.startCapture])
        XCTAssertEqual(machine.state.phase, .monitoring)
    }

    func testDetectionLatchesAlarmAndIgnoresDuplicates() {
        var machine = AppStateMachine()
        _ = machine.handle(.permissionGranted)
        let snap = AlarmSnapshot(id: UUID(), soundName: "BEEP", detectedAt: Date(), confidence: 0.9)
        let first = machine.handle(.targetDetected(snap))
        XCTAssertEqual(machine.state.phase, .alarming)
        XCTAssertTrue(first.contains(.startAlarm(snap)))
        XCTAssertTrue(first.contains(.stopCapture))
        XCTAssertEqual(machine.handle(.targetDetected(snap)), [])
        XCTAssertEqual(machine.state.phase, .alarming)
    }

    func testAcknowledgeThenResetResumesWhenConfigured() {
        var machine = AppStateMachine()
        machine.setResumeFlags(afterReset: true, afterInterrupt: true)
        _ = machine.handle(.permissionGranted)
        let snap = AlarmSnapshot(id: UUID(), soundName: "BEEP", detectedAt: Date(), confidence: 0.91)
        _ = machine.handle(.targetDetected(snap))
        XCTAssertEqual(machine.handle(.acknowledgeTapped), [.stopAlarm, .persistAcknowledgement])
        XCTAssertEqual(machine.state.phase, .acknowledged)
        XCTAssertEqual(machine.handle(.resetTapped), [.persistReset])
        XCTAssertEqual(machine.state.phase, .resetting)
        XCTAssertEqual(machine.handle(.resetTapped), [])
        XCTAssertEqual(machine.handle(.resetCompleted), [.startCapture])
        XCTAssertEqual(machine.state.phase, .monitoring)
        XCTAssertNil(machine.state.activeAlarm)
    }

    func testResetFromAlarmingAcksAndStopsAudio() {
        var machine = AppStateMachine()
        _ = machine.handle(.permissionGranted)
        let snap = AlarmSnapshot(id: UUID(), soundName: "SIREN", detectedAt: Date(), confidence: 0.88)
        _ = machine.handle(.targetDetected(snap))
        let commands = machine.handle(.resetTapped)
        XCTAssertEqual(machine.state.phase, .resetting)
        XCTAssertTrue(commands.contains(.stopAlarm))
        XCTAssertTrue(commands.contains(.persistAcknowledgement))
        XCTAssertTrue(commands.contains(.persistReset))
    }

    func testDeniedPermissionStopsCapture() {
        var machine = AppStateMachine()
        _ = machine.handle(.startTapped)
        let commands = machine.handle(.permissionDenied)
        XCTAssertEqual(machine.state.phase, .permissionDenied)
        XCTAssertTrue(commands.contains(.stopCapture))
    }

    func testInterruptionPausesMonitoringAndCanResume() {
        var machine = AppStateMachine()
        machine.setResumeFlags(afterReset: true, afterInterrupt: true)
        _ = machine.handle(.permissionGranted)
        XCTAssertEqual(machine.handle(.interruptionBegan), [.stopCapture])
        XCTAssertEqual(machine.state.phase, .interrupted)
        XCTAssertEqual(machine.handle(.interruptionEnded), [.startCapture])
        XCTAssertEqual(machine.state.phase, .monitoring)
    }

    func testWindowCloseParksListeningUntilItReopens() {
        var machine = AppStateMachine()
        _ = machine.handle(.permissionGranted)
        XCTAssertEqual(machine.handle(.windowClosed), [.stopCapture, .enterStandby])
        XCTAssertEqual(machine.state.phase, .outsideWindow)
        XCTAssertEqual(machine.handle(.windowOpened), [.leaveStandby, .startCapture])
        XCTAssertEqual(machine.state.phase, .monitoring)
    }

    func testDisarmFromOutsideWindowReturnsIdle() {
        var machine = AppStateMachine()
        _ = machine.handle(.permissionGranted)
        _ = machine.handle(.windowClosed)
        XCTAssertEqual(machine.handle(.stopTapped), [.leaveStandby, .stopCapture])
        XCTAssertEqual(machine.state.phase, .idle)
    }

    func testOutsideWindowDoesNotAlarm() {
        var machine = AppStateMachine()
        _ = machine.handle(.permissionGranted)
        _ = machine.handle(.windowClosed)
        let snap = AlarmSnapshot(id: UUID(), soundName: "BEEP", detectedAt: Date(), confidence: 0.9)
        XCTAssertEqual(machine.handle(.targetDetected(snap)), [])
        XCTAssertEqual(machine.state.phase, .outsideWindow)
        XCTAssertNil(machine.state.activeAlarm)
    }

    func testWindowDoesNotClearALatchedAlarm() {
        var machine = AppStateMachine()
        _ = machine.handle(.permissionGranted)
        let snap = AlarmSnapshot(id: UUID(), soundName: "BEEP", detectedAt: Date(), confidence: 0.9)
        _ = machine.handle(.targetDetected(snap))
        XCTAssertEqual(machine.handle(.windowClosed), [])
        XCTAssertEqual(machine.handle(.windowOpened), [])
        XCTAssertEqual(machine.state.phase, .alarming)
        XCTAssertEqual(machine.state.activeAlarm, snap)
    }

    func testOutsideWindowInterruptionCanResume() {
        var machine = AppStateMachine()
        machine.setResumeFlags(afterReset: true, afterInterrupt: true)
        _ = machine.handle(.permissionGranted)
        _ = machine.handle(.windowClosed)
        XCTAssertEqual(machine.handle(.interruptionBegan), [.leaveStandby, .stopCapture])
        XCTAssertEqual(machine.state.phase, .interrupted)
        XCTAssertEqual(machine.handle(.interruptionEnded), [.startCapture])
        XCTAssertEqual(machine.state.phase, .monitoring)
    }

    func testRestoreUnackedReentersAlarming() {
        var machine = AppStateMachine()
        let snap = AlarmSnapshot(id: UUID(), soundName: "BEEP", detectedAt: Date(), confidence: 0.8)
        let commands = machine.handle(.restoreUnacked(snap))
        XCTAssertEqual(machine.state.phase, .alarming)
        XCTAssertTrue(commands.contains(.startAlarm(snap)))
    }
}
