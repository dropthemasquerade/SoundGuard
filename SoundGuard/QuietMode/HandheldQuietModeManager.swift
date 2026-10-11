import Foundation

/// Applies the handheld estimate to alarm output. Recognition and event rows stay untouched.
@MainActor
final class HandheldQuietModeManager {
    private let detector = HandheldStateDetector()
    private let motion = HandheldMotionMonitor()
    private var session = QuietSession()
    private var resumeTask: Task<Void, Never>?
    private var staleTimer: Timer?
    private var phase: AppPhase = .idle
    private var quietEnabled = false
    private var behavior: QuietModeBehavior = .resumeWhenPlaced
    private var hapticsWhileQuiet = false
    private var baseHapticsEnabled = true
    private var resumeDelay: TimeInterval = 2

    private(set) var output: AlertOutput = .idle
    var onOutput: ((AlertOutput) -> Void)?

    init() {
        motion.onSample = { [weak self] sample in
            Task { @MainActor in
                self?.ingest(sample)
            }
        }
        motion.onUnavailable = { [weak self] in
            Task { @MainActor in
                self?.sensorUnavailable()
            }
        }
    }

    func refresh(settings: SettingsStore, phase: AppPhase) {
        self.phase = phase
        quietEnabled = settings.handheldQuietEnabled
        behavior = settings.quietModeBehavior
        hapticsWhileQuiet = settings.handheldQuietHapticsEnabled
        baseHapticsEnabled = settings.hapticsEnabled
        resumeDelay = settings.resumeDelaySeconds
        if quietEnabled && Self.senses(phase) {
            motion.start()
            armStaleTimer()
        } else {
            stopSensing()
            if !quietEnabled {
                detector.reset()
                session.reset()
                cancelResume()
            }
        }
        recompute()
    }

    /// Foreground return, or the stale timer. Missing motion fails open.
    func evaluateNow() {
        let signal = session.receive(
            detector.evaluate(at: ProcessInfo.processInfo.systemUptime),
            resumeDelay: resumeDelay
        )
        handle(signal)
        recompute()
    }

    func userEndedAlarm() {
        session.userEndedAlarm()
        cancelResume()
    }

    private func ingest(_ sample: MotionSample) {
        let signal = session.receive(detector.ingest(sample), resumeDelay: resumeDelay)
        handle(signal)
        recompute()
    }

    private func sensorUnavailable() {
        let signal = session.receive(detector.markUnavailable(), resumeDelay: resumeDelay)
        handle(signal)
        recompute()
    }

    private func handle(_ signal: ResumeSignal) {
        switch signal {
        case .cancel:
            cancelResume()
        case .keep:
            break
        case .schedule(let delay):
            cancelResume()
            resumeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                session.resumeFired()
                recompute()
            }
        }
    }

    private func recompute() {
        let next = AlertPolicyManager.output(
            phase: phase,
            quietEnabled: quietEnabled,
            behavior: behavior,
            hapticsWhileQuiet: hapticsWhileQuiet,
            baseHapticsEnabled: baseHapticsEnabled,
            handheld: session.handheld,
            holdingResume: session.holdingResume
        )
        guard next != output else { return }
        output = next
        onOutput?(next)
    }

    private func cancelResume() {
        resumeTask?.cancel()
        resumeTask = nil
    }

    private func armStaleTimer() {
        guard staleTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        staleTimer = timer
    }

    private func stopSensing() {
        motion.stop()
        staleTimer?.invalidate()
        staleTimer = nil
    }

    /// Listening, an open alarm, or standby. Idle does not keep the sensor on.
    static func senses(_ phase: AppPhase) -> Bool {
        switch phase {
        case .monitoring, .outsideWindow, .alarming, .acknowledged, .interrupted:
            return true
        case .idle, .permissionDenied, .resetting:
            return false
        }
    }
}
