import AVFoundation
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

@Observable
@MainActor
final class AppModel {
    let container: ModelContainer
    let events: EventStore
    let settings: SettingsStore
    let references: ReferenceAudioService
    let coordinator: MonitoringCoordinator

    var sounds: [ReferenceSound] = []
    var eventLog: [AlarmEvent] = []
    var banner: String?
    var isRecording = false
    var recordLevel: Float = 0
    var recordElapsed: TimeInterval = 0
    var previewingID: UUID?
    var previewingTone: AlarmTone?
    var isPreviewingEdit = false
    var capturedSamples: [Float]?
    var capturedTruncated = false
    var libraryDraft: AudioDraft?

    private var recordTimer: Timer?
    private var recordStartedAt: Date?
    private var recordURL: URL?
    private var capturedDisposableURL: URL?

    init(container: ModelContainer = PersistenceStack.makeContainer()) {
        self.container = container
        let events = EventStore(container: container)
        let settings = SettingsStore()
        let references = ReferenceAudioService()
        self.events = events
        self.settings = settings
        self.references = references
        self.coordinator = MonitoringCoordinator(events: events, settings: settings, references: references)
        refresh()
        coordinator.prepare()
    }

    var activeSound: ReferenceSound? {
        sounds.first(where: \.isActive)
    }

    func refresh() {
        sounds = events.sounds()
        eventLog = events.events()
        coordinator.reloadTarget()
    }

    func arm() {
        coordinator.startListening()
        refresh()
    }

    func disarm() {
        coordinator.stopListening()
    }

    func acknowledge() {
        coordinator.acknowledge()
        refresh()
    }

    func resetAlarm() {
        coordinator.reset()
        refresh()
    }

    /// Ends the alarm and leaves listening off so the target can be changed.
    func stopAlarm() {
        coordinator.stopListening()
        refresh()
    }

    func activate(_ sound: ReferenceSound) {
        try? events.setActive(id: sound.id)
        refresh()
    }

    func rename(_ sound: ReferenceSound, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? events.rename(id: sound.id, name: trimmed)
        refresh()
    }

    func delete(_ sound: ReferenceSound) {
        if let fileName = try? events.deleteSound(id: sound.id) {
            references.deleteFile(fileName)
        }
        refresh()
    }

    func preview(_ sound: ReferenceSound) {
        play(url: references.fileURL(for: sound.fileName), soundID: sound.id, tone: nil)
    }

    func playTrigger(id: UUID) {
        guard TriggerClipStore.exists(id) else { return }
        play(url: TriggerClipStore.url(for: id), soundID: id, tone: nil)
    }

    func previewAlarmTone(_ tone: AlarmTone) {
        if previewingTone == tone {
            stopPreview()
            return
        }
        guard !coordinator.phase.isAlarmSurface else { return }
        guard let url = tone.fileURL() else {
            banner = "Could not prepare this alarm tone."
            return
        }
        play(url: url, soundID: nil, tone: tone)
    }

    func stopPreview() {
        references.stopPreview()
    }

    func previewEditedSamples(_ samples: [Float]) {
        if isPreviewingEdit {
            stopPreview()
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("soundguard-edit-preview.wav")
        do {
            try WaveFile.write(samples: samples, to: url)
        } catch {
            banner = error.localizedDescription
            return
        }
        play(url: url, soundID: nil, tone: nil, editing: true)
    }

    private func play(url: URL, soundID: UUID?, tone: AlarmTone?, editing: Bool = false) {
        do {
            coordinator.beginPlaybackGuard()
            try coordinator.prepareForPreview()
            try references.preview(url) { [weak self] in
                Task { @MainActor in
                    self?.completePreview()
                }
            }
            previewingID = soundID
            previewingTone = tone
            isPreviewingEdit = editing
        } catch {
            coordinator.cancelPlaybackGuard()
            previewingID = nil
            previewingTone = nil
            isPreviewingEdit = false
            banner = AudioSessionController.message(for: error)
        }
    }

    private func completePreview() {
        previewingID = nil
        previewingTone = nil
        isPreviewingEdit = false
        coordinator.endPlaybackGuard()
    }

    func beginRecording() {
        discardCapturedAudio()
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.banner = "Microphone access is required to record a target."
                    return
                }
                self.startRecorder()
            }
        }
    }

    private func startRecorder() {
        do {
            coordinator.stopListening()
            try coordinator.preparePlaybackSession()
            recordURL = try references.startRecording()
            isRecording = true
            recordElapsed = 0
            recordStartedAt = Date()
            recordTimer?.invalidate()
            recordTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                guard let model = self else { return }
                Task { @MainActor in
                    model.tickRecording()
                }
            }
        } catch {
            banner = AudioSessionController.message(for: error)
        }
    }

    func stopRecordingForEdit() {
        guard isRecording else { return }
        recordTimer?.invalidate()
        recordTimer = nil
        isRecording = false
        recordLevel = 0
        do {
            let url = try references.stopRecording()
            do {
                try stageCapturedFile(url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        } catch {
            banner = error.localizedDescription
            references.cancelRecording()
        }
    }

    func cancelRecording() {
        recordTimer?.invalidate()
        recordTimer = nil
        isRecording = false
        references.cancelRecording()
        recordURL = nil
        discardCapturedAudio()
    }

    func discardCapturedAudio() {
        stopPreview()
        if let url = capturedDisposableURL {
            try? FileManager.default.removeItem(at: url)
        }
        capturedDisposableURL = nil
        capturedSamples = nil
        capturedTruncated = false
        recordElapsed = 0
        recordLevel = 0
    }

    func stageImport(from url: URL) {
        var copied: URL?
        do {
            let dest = try references.importFile(url)
            copied = dest
            let loaded = try AudioFeatureExtractor.loadEditorAudio(url: dest)
            guard !loaded.samples.isEmpty else {
                throw NSError(domain: "SoundGuard", code: 38, userInfo: [NSLocalizedDescriptionKey: "That audio file is empty"])
            }
            libraryDraft = AudioDraft(
                samples: loaded.samples,
                name: url.deletingPathExtension().lastPathComponent,
                profile: .custom,
                replacingID: nil,
                disposableURL: dest,
                truncated: loaded.truncated
            )
        } catch {
            if let copied {
                try? FileManager.default.removeItem(at: copied)
            }
            banner = error.localizedDescription
        }
    }

    func stageExisting(_ sound: ReferenceSound) {
        let url = references.fileURL(for: sound.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            banner = "This recording is no longer on the device."
            return
        }
        do {
            let loaded = try AudioFeatureExtractor.loadEditorAudio(url: url)
            guard !loaded.samples.isEmpty else {
                banner = "This recording is empty."
                return
            }
            libraryDraft = AudioDraft(
                samples: loaded.samples,
                name: sound.name,
                profile: sound.profile,
                replacingID: sound.id,
                disposableURL: nil,
                truncated: loaded.truncated
            )
        } catch {
            banner = error.localizedDescription
        }
    }

    func discardLibraryDraft() {
        stopPreview()
        guard let draft = libraryDraft else { return }
        if let url = draft.disposableURL {
            try? FileManager.default.removeItem(at: url)
        }
        libraryDraft = nil
    }

    @discardableResult
    func saveCaptured(name: String, profile: SoundProfile, edit: CaptureEdit) -> Bool {
        guard let samples = capturedSamples else { return false }
        return commitEditedSamples(
            samples,
            name: name,
            profile: profile,
            edit: edit,
            replacingID: nil,
            disposableURL: capturedDisposableURL
        ) {
            self.capturedDisposableURL = nil
            self.capturedSamples = nil
            self.capturedTruncated = false
        }
    }

    @discardableResult
    func saveLibraryDraft(name: String, profile: SoundProfile, edit: CaptureEdit) -> Bool {
        guard let draft = libraryDraft else { return false }
        return commitEditedSamples(
            draft.samples,
            name: name,
            profile: profile,
            edit: edit,
            replacingID: draft.replacingID,
            disposableURL: draft.disposableURL
        ) {
            self.libraryDraft = nil
        }
    }

    func clearHistory() {
        stopPreview()
        TriggerClipStore.deleteAll()
        try? events.clearEvents()
        refresh()
    }

    func applyDetectionSettings() {
        coordinator.reloadTarget()
    }

    func applySchedule() {
        coordinator.refreshSchedule()
    }

    func applyQuietSettings() {
        coordinator.refreshQuietMode()
    }

    private func tickRecording() {
        recordLevel = references.currentMeter()
        if let recordStartedAt {
            recordElapsed = Date().timeIntervalSince(recordStartedAt)
            if recordElapsed >= 8 {
                stopRecordingForEdit()
            }
        }
    }

    private func stageCapturedFile(_ url: URL) throws {
        let loaded = try AudioFeatureExtractor.loadEditorAudio(url: url)
        guard !loaded.samples.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            throw NSError(domain: "SoundGuard", code: 38, userInfo: [NSLocalizedDescriptionKey: "That recording is empty"])
        }
        capturedDisposableURL = url
        capturedTruncated = loaded.truncated
        capturedSamples = loaded.samples
    }

    private func commitEditedSamples(
        _ samples: [Float],
        name: String,
        profile: SoundProfile,
        edit: CaptureEdit,
        replacingID: UUID?,
        disposableURL: URL?,
        clear: () -> Void
    ) -> Bool {
        if let message = CaptureProcessor.limitMessage(start: edit.start, end: edit.end) {
            banner = message
            return false
        }
        let processed = CaptureProcessor.process(samples, edit: edit)
        let length = CaptureProcessor.duration(of: processed)
        guard length + 0.000_1 >= CaptureProcessor.minimumDuration, length - 0.000_1 <= CaptureProcessor.maximumDuration else {
            banner = "Keep at least 0.25 seconds and at most 12 seconds."
            return false
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("soundguard-edited-\(UUID().uuidString).wav")
        do {
            stopPreview()
            try WaveFile.write(samples: processed, to: temp)
            if let replacingID {
                try replaceReference(id: replacingID, from: temp, name: name, profile: profile)
                try? FileManager.default.removeItem(at: temp)
            } else {
                try saveReference(from: temp, name: name, profile: profile, cleanup: true)
            }
            if let disposableURL {
                try? FileManager.default.removeItem(at: disposableURL)
            }
            clear()
            return true
        } catch {
            try? FileManager.default.removeItem(at: temp)
            banner = error.localizedDescription
            return false
        }
    }

    private func replaceReference(id: UUID, from url: URL, name: String, profile: SoundProfile) throws {
        guard let sound = sounds.first(where: { $0.id == id }) else {
            throw NSError(domain: "SoundGuard", code: 37, userInfo: [NSLocalizedDescriptionKey: "That target no longer exists"])
        }
        let (template, duration) = try references.buildTemplate(from: url, profile: profile)
        let data = try references.encode(template)
        try references.replaceStoredFile(sound.fileName, with: url)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? sound.name : trimmed
        try events.updateSound(id: id, name: label, duration: duration, profile: profile, templateData: data)
        refresh()
    }

    private func saveReference(from url: URL, name: String, profile: SoundProfile, cleanup: Bool, makeActive: Bool = true) throws {
        let (template, duration) = try references.buildTemplate(from: url, profile: profile)
        let data = try references.encode(template)
        let id = UUID()
        let fileName = try references.persistCopy(from: url, id: id)
        if cleanup {
            try? FileManager.default.removeItem(at: url)
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "TARGET \(sounds.count + 1)" : trimmed
        _ = try events.insertSound(
            name: label,
            duration: duration,
            fileName: fileName,
            profile: profile,
            templateData: data,
            makeActive: makeActive
        )
        refresh()
    }

}

struct AudioDraft: Identifiable {
    let id = UUID()
    var samples: [Float]
    var name: String
    var profile: SoundProfile
    var replacingID: UUID?
    var disposableURL: URL?
    var truncated: Bool
}
