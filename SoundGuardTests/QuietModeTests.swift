import XCTest
@testable import SoundGuard

final class QuietModeTests: XCTestCase {
    func testHandheldDetectionStillRecordsAndHoldsAudio() {
        var machine = AppStateMachine()
        _ = machine.handle(.permissionGranted)
        let snap = AlarmSnapshot(id: UUID(), soundName: "BEEP", detectedAt: Date(), confidence: 0.99)
        let commands = machine.handle(.targetDetected(snap))
        XCTAssertTrue(commands.contains(.persistDetection(snap)))
        XCTAssertEqual(machine.state.phase, .alarming)

        for behavior in QuietModeBehavior.allCases {
            let output = AlertPolicyManager.output(
                phase: .alarming,
                quietEnabled: true,
                behavior: behavior,
                hapticsWhileQuiet: false,
                baseHapticsEnabled: true,
                handheld: .handheld,
                holdingResume: false
            )
            XCTAssertFalse(output.playAudio, behavior.rawValue)
            XCTAssertFalse(output.playHaptics, behavior.rawValue)
            XCTAssertEqual(output.posture, .handheldQuiet)
            XCTAssertEqual(output.showFullAlarm, behavior == .screenHint, behavior.rawValue)
        }
    }

    func testPlacedDetectionUsesNormalAlarm() {
        let output = AlertPolicyManager.output(
            phase: .alarming,
            quietEnabled: true,
            behavior: .recordOnly,
            hapticsWhileQuiet: false,
            baseHapticsEnabled: true,
            handheld: .placed,
            holdingResume: false
        )
        XCTAssertTrue(output.playAudio)
        XCTAssertTrue(output.playHaptics)
        XCTAssertTrue(output.showFullAlarm)
        XCTAssertEqual(output.posture, .alertsOn)
    }

    func testHandheldThenSetDownResumesAfterDelay() {
        var session = QuietSession()
        XCTAssertEqual(session.receive(.handheld, resumeDelay: 2), .cancel)
        var output = policy(session, behavior: .resumeWhenPlaced)
        XCTAssertFalse(output.playAudio)
        XCTAssertFalse(output.showFullAlarm)

        XCTAssertEqual(session.receive(.placed, resumeDelay: 2), .schedule(2))
        output = policy(session, behavior: .resumeWhenPlaced)
        XCTAssertTrue(session.holdingResume)
        XCTAssertFalse(output.playAudio)

        session.resumeFired()
        output = policy(session, behavior: .resumeWhenPlaced)
        XCTAssertTrue(output.playAudio)
        XCTAssertTrue(output.showFullAlarm)
    }

    func testBriefMovementDoesNotCountAsHandheld() {
        let detector = HandheldStateDetector()
        var state = feed(detector, from: 0, duration: 0.5, rotation: 2, accel: 0.8)
        XCTAssertNotEqual(state, .handheld)
        state = feed(detector, from: 0.5, duration: 1.0, rotation: 0.02, accel: 0.01)
        XCTAssertNotEqual(state, .handheld)
    }

    func testSustainedMotionThenStillness() {
        let detector = HandheldStateDetector()
        XCTAssertEqual(feed(detector, from: 0, duration: 2.0, rotation: 1.6, accel: 0.5), .handheld)
        XCTAssertEqual(feed(detector, from: 2.0, duration: 5.0, rotation: 0.02, accel: 0.01), .placed)
    }

    func testSensorErrorAndStaleSamplesFailOpen() {
        let detector = HandheldStateDetector()
        XCTAssertEqual(feed(detector, from: 0, duration: 2.0, rotation: 1.6, accel: 0.4), .handheld)
        XCTAssertEqual(detector.markUnavailable(), .unknown)
        let unavailable = AlertPolicyManager.output(
            phase: .alarming,
            quietEnabled: true,
            behavior: .recordOnly,
            hapticsWhileQuiet: true,
            baseHapticsEnabled: true,
            handheld: .unknown,
            holdingResume: false
        )
        XCTAssertTrue(unavailable.playAudio)
        XCTAssertEqual(unavailable.posture, .uncertain)

        let again = HandheldStateDetector()
        XCTAssertEqual(feed(again, from: 0, duration: 2.0, rotation: 1.6, accel: 0.4), .handheld)
        XCTAssertEqual(again.evaluate(at: 2.0 + 2.6), .unknown)
    }

    func testLockBackgroundAndInterruptionDoNotDropOrStaySilent() {
        var machine = AppStateMachine()
        _ = machine.handle(.permissionGranted)
        let snap = AlarmSnapshot(id: UUID(), soundName: "BEEP", detectedAt: Date(), confidence: 0.95)
        _ = machine.handle(.targetDetected(snap))
        XCTAssertEqual(machine.handle(.interruptionBegan), [])
        XCTAssertEqual(machine.state.phase, .alarming)
        XCTAssertEqual(machine.state.activeAlarm, snap)

        var session = QuietSession()
        _ = session.receive(.handheld, resumeDelay: 2)
        XCTAssertEqual(session.receive(.unknown, resumeDelay: 2), .cancel)
        XCTAssertFalse(session.holdingResume)
        let output = policy(session, behavior: .recordOnly)
        XCTAssertTrue(output.playAudio)
        XCTAssertEqual(output.posture, .uncertain)
    }

    func testManualResetCancelsPendingResume() {
        var machine = AppStateMachine()
        _ = machine.handle(.permissionGranted)
        let snap = AlarmSnapshot(id: UUID(), soundName: "BEEP", detectedAt: Date(), confidence: 0.95)
        _ = machine.handle(.targetDetected(snap))
        var session = QuietSession()
        _ = session.receive(.handheld, resumeDelay: 3)
        XCTAssertEqual(session.receive(.placed, resumeDelay: 3), .schedule(3))
        session.userEndedAlarm()
        XCTAssertFalse(session.holdingResume)
        XCTAssertEqual(machine.handle(.resetTapped), [.stopAlarm, .persistAcknowledgement, .persistReset])
        XCTAssertEqual(machine.state.phase, .resetting)
        let output = AlertPolicyManager.output(
            phase: .acknowledged,
            quietEnabled: true,
            behavior: .resumeWhenPlaced,
            hapticsWhileQuiet: false,
            baseHapticsEnabled: true,
            handheld: session.handheld,
            holdingResume: session.holdingResume
        )
        XCTAssertFalse(output.playAudio)
        XCTAssertTrue(output.showFullAlarm)
    }

    func testQuietModeOffKeepsOriginalAlarm() {
        let output = AlertPolicyManager.output(
            phase: .alarming,
            quietEnabled: false,
            behavior: .recordOnly,
            hapticsWhileQuiet: false,
            baseHapticsEnabled: true,
            handheld: .handheld,
            holdingResume: true
        )
        XCTAssertTrue(output.playAudio)
        XCTAssertTrue(output.playHaptics)
        XCTAssertTrue(output.showFullAlarm)
        XCTAssertEqual(output.posture, .off)
    }

    func testHapticsCanStayOnWhileAudioIsHeld() {
        let output = AlertPolicyManager.output(
            phase: .alarming,
            quietEnabled: true,
            behavior: .screenHint,
            hapticsWhileQuiet: true,
            baseHapticsEnabled: true,
            handheld: .handheld,
            holdingResume: false
        )
        XCTAssertFalse(output.playAudio)
        XCTAssertTrue(output.playHaptics)
        XCTAssertTrue(output.showFullAlarm)
    }

    private func policy(_ session: QuietSession, behavior: QuietModeBehavior) -> AlertOutput {
        AlertPolicyManager.output(
            phase: .alarming,
            quietEnabled: true,
            behavior: behavior,
            hapticsWhileQuiet: false,
            baseHapticsEnabled: true,
            handheld: session.handheld,
            holdingResume: session.holdingResume
        )
    }

    @discardableResult
    private func feed(
        _ detector: HandheldStateDetector,
        from start: Double,
        duration: Double,
        rotation: Double,
        accel: Double
    ) -> HandheldState {
        var time = start
        var state = detector.state
        while time < start + duration {
            state = detector.ingest(MotionSample(
                time: time,
                rotationRate: rotation,
                userAcceleration: accel,
                gravityX: 0,
                gravityY: 0,
                gravityZ: -1
            ))
            time += 0.05
        }
        return state
    }
}
