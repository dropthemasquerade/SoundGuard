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
    private(set) var quietPosture: QuietPosture = .off
    private(set) var presentsAlarm = false

    private var machine = AppStateMachine()
    private let capture = AudioCaptureService()
    private let session = AudioSessionController()
    private let standby = StandbyAudioService()
    private let alarmManager = AlarmManager()
    private let quietMode = HandheldQuietModeManager()
    private let matching = MatchingPipeline()
    private let events: EventStore
    private let settings: SettingsStore
    private let references: ReferenceAudioService

    private var observers: [NSObjectProtocol] = []
    private var boundaryTimer: Timer?
    private var suppressDetection = false
    private var suppressGeneration = 0
    private var suppressTask: Task<Void, Never>?

    init(events: EventStore, settings: SettingsStore, references: ReferenceAudioService) {
        self.events = events
        self.settings = settings
        self.references = references
        quietMode.onOutput = { [weak self] output in
            guard let self else { return }
            self.quietPosture = output.posture
            self.presentsAlarm = output.showFullAlarm
            guard self.phase == .alarming, self.alarmManager.isActive else { return }
            self.alarmManager.applyOutput(output, volume: self.settings.alarmVolume, tone: self.settings.alarmTone)
        }
        let pipeline = matching
        capture.onSamples = { [weak self] samples, time in
            pipeline.process(samples: samples, time: time) { result, level, confidence, clip in
                Task { @MainActor in
                    guard let coordinator = self else { return }
                    coordinator.liveLevel = level
                    if coordinator.suppressDetection {
                        coordinator.liveConfidence = 0
                        return
                    }
                    coordinator.liveConfidence = confidence
                    if let result {
                        coordinator.handleDetection(result, clip: clip ?? [])
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
                coordinator.dispatch(.captureFailed(AudioSessionController.message(for: error)))
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
            consecutiveHits: settings.consecutiveHits,
            mode: settings.listenMode
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

    func prepareForPreview() throws {
        if capture.isRunning || standby.isRunning {
            return
        }
        try session.keepCurrentSessionForPlayback()
    }

    func preparePlaybackSession() throws {
        try session.configureForPlayback()
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

    /// Ignore microphone matches while a saved recording is playing out of the speaker.
    func beginPlaybackGuard() {
        suppressGeneration += 1
        suppressDetection = true
        suppressTask?.cancel()
        suppressTask = nil
        matching.flushDetectionState()
    }

    /// Keep ignoring for a short tail after playback, then clear hits gathered from that tail.
    func cancelPlaybackGuard() {
        suppressGeneration += 1
        suppressTask?.cancel()
        suppressTask = nil
        let generation = suppressGeneration
        matching.flushDetectionState()
        matching.whenIdle { [weak self] in
            guard let self, generation == self.suppressGeneration else { return }
            self.suppressDetection = false
        }
    }

    func endPlaybackGuard() {
        let generation = suppressGeneration
        suppressTask?.cancel()
        suppressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, generation == self.suppressGeneration else { return }
            self.matching.flushDetectionState()
            self.matching.whenIdle { [weak self] in
                guard let self, generation == self.suppressGeneration else { return }
                self.suppressDetection = false
            }
        }
    }

    func handleSceneActive() {
        refreshSchedule()
        quietMode.evaluateNow()
        guard phase == .alarming else { return }
        try? session.configureForPlayback()
        alarmManager.applyOutput(quietMode.output, volume: settings.alarmVolume, tone: settings.alarmTone)
    }

    func refreshQuietMode() {
        quietMode.refresh(settings: settings, phase: phase)
        quietPosture = quietMode.output.posture
        presentsAlarm = quietMode.output.showFullAlarm
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

    private func handleDetection(_ result: DetectionResult, clip: [Float]) {
        let name = events.activeSound()?.name ?? "TARGET"
        let snapshot = AlarmSnapshot(
            id: UUID(),
            soundName: name,
            detectedAt: Date(),
            confidence: result.confidence
        )
        dispatch(.targetDetected(snapshot))
        // Ignored detections (already alarming, or outside the window) must not leave a clip.
        guard activeAlarm?.id == snapshot.id else { return }
        TriggerClipStore.save(samples: clip, id: snapshot.id)
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
        if event == .stopTapped, machine.state.phase == .idle, machine.state.activeAlarm != nil {
            matching.flushDetectionState()
            machine.clearActiveAlarm()
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
            // Stay on playAndRecord. A later switch back from `.playback` while locked
            // is rejected with OSStatus !int.
            try? session.configureForMonitoring()
            standby.start()
        case .leaveStandby:
            standby.stop()
        case .startAlarm(let snapshot):
            // The mic session is already active. If iOS refuses a mode change, still play.
            quietMode.refresh(settings: settings, phase: machine.state.phase)
            try? session.configureForPlayback()
            alarmManager.start(
                snapshot: snapshot,
                volume: settings.alarmVolume,
                notificationsEnabled: settings.notificationsEnabled,
                tone: settings.alarmTone,
                output: quietMode.output
            )
        case .stopAlarm:
            quietMode.userEndedAlarm()
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
            try beginCapture()
        } catch {
            capture.stop()
            do {
                try beginCapture()
            } catch {
                dispatch(.captureFailed(AudioSessionController.message(for: error)))
            }
        }
    }

    private func beginCapture() throws {
        try session.configureForMonitoring()
        matching.resetSession()
        matching.discardRecentAudio()
        reloadTarget()
        try capture.start()
        dispatch(.captureStarted)
    }

    private func syncPublishedState() {
        phase = machine.state.phase
        activeAlarm = machine.state.activeAlarm
        if let error = machine.state.lastError {
            lastError = error
        }
        quietMode.refresh(settings: settings, phase: phase)
        quietPosture = quietMode.output.posture
        presentsAlarm = quietMode.output.showFullAlarm
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
    private var listenMode: ListenMode = .sustained
    /// Last few seconds of microphone audio, copied only when a detection latches.
    private var recent: [Float] = []
    private let recentLimit = 16_000 * 5

    func load(template: ReferenceTemplate, threshold: Double, consecutiveHits: Int, mode: ListenMode) {
        queue.sync {
            listenMode = mode
            matcher.load(template)
            extractor.harmonicHz = template.harmonicHz
            var parameters = DetectionParameters.default(for: template.profile)
            parameters.similarityThreshold = Float(threshold)
            parameters.consecutiveHits = max(2, consecutiveHits)
            detection.parameters = parameters
            detection.mode = mode
            detection.referenceDuration = template.duration
            detection.templatePartials = template.partials
            detection.templateHarmonicity = template.harmonicity
            detection.resetLatch()
            detection.resetSession()
            extractor.reset()
        }
    }

    func clearTarget() {
        queue.sync {
            matcher.clear()
            extractor.harmonicHz = 0
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

    /// Drop buffered features and any consecutive hits. Queued ahead of `whenIdle`.
    /// The recent-audio ring is left intact so a preview flush does not erase the trigger clip.
    func flushDetectionState() {
        queue.async { [self] in
            extractor.reset()
            matcher.resetBuffer()
            detection.resetLatch()
            detection.resetSession()
        }
    }

    /// Forget audio from before this capture session so a clip starts at arm time.
    func discardRecentAudio() {
        queue.async { [self] in
            recent.removeAll(keepingCapacity: true)
        }
    }

    func whenIdle(_ body: @escaping @MainActor () -> Void) {
        queue.async {
            Task { @MainActor in
                body()
            }
        }
    }

    func process(samples: [Float], time: TimeInterval, completion: @escaping (DetectionResult?, Float, Float, [Float]?) -> Void) {
        queue.async { [self] in
            recent.append(contentsOf: samples)
            if recent.count > recentLimit {
                recent.removeFirst(recent.count - recentLimit)
            }
            let frames = extractor.append(samples, streamTime: time)
            var result: DetectionResult?
            var confidence: Float = 0
            var energy: Float = PCMConvert.rms(samples)
            for frame in frames {
                let score = matcher.score(frame: frame)
                let shown = listenMode == .harmonic ? max(score.similarity, score.partialMatch) : score.similarity
                confidence = max(confidence, shown)
                energy = max(energy, score.energy)
                if result == nil {
                    result = detection.process(score)
                }
            }
            lastLevel = energy
            let clip: [Float]? = result == nil ? nil : recent
            completion(result, min(1, energy * 8), confidence, clip)
        }
    }
}
