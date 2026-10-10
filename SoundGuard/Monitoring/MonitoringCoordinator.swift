import AVFoundation
import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class MonitoringCoordinator {
    private(set) var phase: AppPhase = .idle
    private(set) var liveLevel: Float = 0
    private(set) var liveConfidence: Float = 0
    private(set) var activeAlarm: AlarmSnapshot?
    private(set) var lastError: String?
    private(set) var hasActiveTarget = false

    private var machine = AppStateMachine()
    private let capture = AudioCaptureService()
    private let session = AudioSessionController()
    private let standby = StandbyAudioService()
    private let alarmManager = AlarmManager()
    private let matching = MatchingPipeline()
    private let events: EventStore
    private let settings: SettingsStore
    private let references: ReferenceAudioService

    private var observers: [NSObjectProtocol] = []
    private var boundaryTimer: Timer?

    init(events: EventStore, settings: SettingsStore, references: ReferenceAudioService) {
        self.events = events
        self.settings = settings
        self.references = references
        let pipeline = matching
        capture.onSamples = { [weak self] samples, time in
            pipeline.process(samples: samples, time: time) { result, level, confidence in
                Task { @MainActor in
                    guard let coordinator = self else { return }
                    coordinator.liveLevel = level
                    coordinator.liveConfidence = confidence
                    if let result {
                        coordinator.handleDetection(result)
                    }
                }
            }
        }
        capture.onLevel = { [weak self] level in
            Task { @MainActor in
                guard let coordinator = self else { return }
                if coordinator.phase == .monitoring {
                    coordinator.liveLevel = max(coordinator.liveLevel, level)
                }
            }
        }
        capture.onError = { [weak self] error in
            Task { @MainActor in
                guard let coordinator = self else { return }
                coordinator.dispatch(.captureFailed(error.localizedDescription))
            }
        }
        listenForSessionEvents()
    }

    func prepare() {
        alarmManager.prepareNotifications()
        machine.setResumeFlags(afterReset: settings.resumeAfterReset, afterInterrupt: settings.resumeAfterInterrupt)
        reloadTarget()
        restoreOpenEventIfNeeded()
        syncPublishedState()
    }

    func reloadTarget() {
        matching.resetSession()
        guard let sound = events.activeSound(),
              let data = events.templateData(id: sound.id),
              let decoded = try? references.decodeTemplate(data) else {
            matching.clearTarget()
            hasActiveTarget = false
            return
        }
        let template = refreshedTemplate(decoded, for: sound)
        matching.load(
            template: template,
            threshold: settings.similarityThreshold,
            consecutiveHits: settings.consecutiveHits
        )
        hasActiveTarget = true
    }

    private func refreshedTemplate(_ template: ReferenceTemplate, for sound: ReferenceSound) -> ReferenceTemplate {
        guard template.featureVersion < ReferenceTemplate.currentFeatureVersion else { return template }
        let url = references.fileURL(for: sound.fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let rebuilt = try? references.buildTemplate(from: url, profile: sound.profile).0,
              let encoded = try? references.encode(rebuilt) else {
            return template
        }
        try? events.updateTemplate(id: sound.id, templateData: encoded)
        return rebuilt
    }

    func startListening() {
        guard hasActiveTarget else {
            lastError = "Save a reference sound before arming."
            return
        }
        dispatch(.startTapped)
    }

    func stopListening() {
        dispatch(.stopTapped)
    }

    func acknowledge() {
        dispatch(.acknowledgeTapped)
    }

    func reset() {
        dispatch(.resetTapped)
    }

    func consumeError() {
        lastError = nil
        machine.clearError()
    }

    func handleSceneActive() {
        refreshSchedule()
        guard phase == .alarming else { return }
        try? session.configureForPlayback()
        alarmManager.resumePlayback(volume: settings.alarmVolume, hapticsEnabled: settings.hapticsEnabled)
    }

    /// Starts or stops the microphone when the armed window opens or closes.
    /// An alarm that already fired is left latched.
    func refreshSchedule() {
        let open = settings.monitoringWindow.contains(Date())
        switch phase {
        case .monitoring where !open:
            dispatch(.windowClosed)
        case .outsideWindow where open:
            dispatch(.windowOpened)
        case .outsideWindow:
            if !standby.isRunning { standby.start() }
            armBoundaryTimer()
        default:
            armBoundaryTimer()
        }
    }

    private func restoreOpenEventIfNeeded() {
        guard let open = events.openEvent() else { return }
        let snapshot = AlarmSnapshot(
            id: open.id,
            soundName: open.soundName,
            detectedAt: open.detectedAt,
            confidence: open.confidence
        )
        if open.acknowledgedAt == nil {
            dispatch(.restoreUnacked(snapshot))
        } else {
            dispatch(.restoreAcked(snapshot))
        }
    }

    private func handleDetection(_ result: DetectionResult) {
        let name = events.activeSound()?.name ?? "TARGET"
        let snapshot = AlarmSnapshot(
            id: UUID(),
            soundName: name,
            detectedAt: Date(),
            confidence: result.confidence
        )
        dispatch(.targetDetected(snapshot))
    }

    private func dispatch(_ event: AppEvent) {
        machine.setResumeFlags(afterReset: settings.resumeAfterReset, afterInterrupt: settings.resumeAfterInterrupt)
        let commands = machine.handle(event)
        for command in commands {
            execute(command)
        }
        if machine.state.phase == .resetting {
            matching.resetLatch()
            matching.resetSession()
            machine.handle(.resetCompleted).forEach(execute)
        }
        syncPublishedState()
    }

    private func execute(_ command: AppCommand) {
        switch command {
        case .requestPermission:
            requestMic()
        case .startCapture:
            startCapture()
        case .stopCapture:
            capture.stop()
            liveLevel = 0
            liveConfidence = 0
            if machine.state.phase == .idle || machine.state.phase == .permissionDenied {
                standby.stop()
                session.deactivate()
            }
        case .enterStandby:
            capture.stop()
            liveLevel = 0
            liveConfidence = 0
            standby.start()
        case .leaveStandby:
            standby.stop()
        case .startAlarm(let snapshot):
            do { try session.configureForPlayback() } catch { lastError = error.localizedDescription }
            alarmManager.start(
                snapshot: snapshot,
                volume: settings.alarmVolume,
                hapticsEnabled: settings.hapticsEnabled,
                notificationsEnabled: settings.notificationsEnabled
            )
        case .stopAlarm:
            alarmManager.stop()
        case .persistDetection(let snapshot):
            try? events.insertDetection(snapshot)
        case .persistAcknowledgement:
            if let id = machine.state.activeAlarm?.id {
                try? events.markAcknowledged(id: id)
            }
        case .persistReset:
            if let id = machine.state.activeAlarm?.id {
                try? events.markReset(id: id)
            }
        }
    }

    private func requestMic() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let coordinator = self else { return }
            Task { @MainActor in
                coordinator.dispatch(granted ? .permissionGranted : .permissionDenied)
            }
        }
    }

    private func startCapture() {
        guard settings.monitoringWindow.contains(Date()) else {
            dispatch(.windowClosed)
            return
        }
        standby.stop()
        do {
            try session.configureForMonitoring()
            matching.resetSession()
            reloadTarget()
            try capture.start()
            dispatch(.captureStarted)
        } catch {
            dispatch(.captureFailed(error.localizedDescription))
        }
    }

    private func syncPublishedState() {
        phase = machine.state.phase
        activeAlarm = machine.state.activeAlarm
        if let error = machine.state.lastError {
            lastError = error
        }
        armBoundaryTimer()
    }

    private func armBoundaryTimer() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
        guard phase == .monitoring || phase == .outsideWindow else { return }
        guard let delay = settings.monitoringWindow.secondsUntilBoundary(from: Date()) else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSchedule()
            }
        }
        timer.tolerance = min(1, delay * 0.05)
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    private func listenForSessionEvents() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let type = typeValue.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                guard let coordinator = self else { return }
                Task { @MainActor in
                    if type == .began {
                        coordinator.dispatch(.interruptionBegan)
                    } else if type == .ended {
                        coordinator.dispatch(.interruptionEnded)
                    }
                }
            }
        )
        observers.append(
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let coordinator = self else { return }
                Task { @MainActor in
                    if coordinator.phase == .monitoring, !coordinator.capture.isRunning {
                        coordinator.startCapture()
                    } else if coordinator.phase == .outsideWindow, !coordinator.standby.isRunning {
                        coordinator.standby.start()
                    }
                }
            }
        )
        observers.append(
            center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let coordinator = self else { return }
                Task { @MainActor in
                    coordinator.refreshSchedule()
                }
            }
        )
    }
}

final class MatchingPipeline: @unchecked Sendable {
    private let extractor = AudioFeatureExtractor()
    private let matcher = SoundMatcher()
    private let detection = DetectionEngine()
    private let queue = DispatchQueue(label: "soundguard.dsp", qos: .userInitiated)
    private var lastLevel: Float = 0

    func load(template: ReferenceTemplate, threshold: Double, consecutiveHits: Int) {
        queue.sync {
            matcher.load(template)
            var parameters = DetectionParameters.default(for: template.profile)
            parameters.similarityThreshold = Float(threshold)
            parameters.consecutiveHits = max(2, consecutiveHits)
            detection.parameters = parameters
            detection.resetLatch()
            detection.resetSession()
            extractor.reset()
        }
    }

    func clearTarget() {
        queue.sync {
            matcher.clear()
            extractor.reset()
            detection.resetLatch()
        }
    }

    func resetSession() {
        queue.async { [self] in
            extractor.reset()
            matcher.resetBuffer()
            detection.resetSession()
        }
    }

    func resetLatch() {
        queue.async { [self] in
            detection.resetLatch()
            matcher.resetBuffer()
        }
    }

    func process(samples: [Float], time: TimeInterval, completion: @escaping (DetectionResult?, Float, Float) -> Void) {
        queue.async { [self] in
            let frames = extractor.append(samples, streamTime: time)
            var result: DetectionResult?
            var confidence: Float = 0
            var energy: Float = PCMConvert.rms(samples)
            for frame in frames {
                let score = matcher.score(frame: frame)
                confidence = max(confidence, score.similarity)
                energy = max(energy, score.energy)
                if result == nil {
                    result = detection.process(score)
                }
            }
            lastLevel = energy
            completion(result, min(1, energy * 8), confidence)
        }
    }
}
