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

    private var recordTimer: Timer?
    private var recordStartedAt: Date?
    private var recordURL: URL?
    private var captureName: String?
    private var captureProfile: SoundProfile?

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
        let url = references.fileURL(for: sound.fileName)
        do {
            try coordinator.preparePlaybackSession()
            try references.preview(url)
            previewingID = sound.id
        } catch {
            banner = error.localizedDescription
        }
    }

    func stopPreview() {
        references.stopPreview()
        previewingID = nil
    }

    func beginRecording(defaultName: String? = nil, defaultProfile: SoundProfile? = nil) {
        captureName = defaultName
        captureProfile = defaultProfile
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.captureName = nil
                    self.captureProfile = nil
                    self.banner = "Microphone access is required to record a target."
                    return
                }
                self.startRecorder()
            }
        }
    }

    private func startRecorder() {
        do {
            try coordinator.preparePlaybackSession()
            coordinator.stopListening()
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
            banner = error.localizedDescription
        }
    }

    func stopAndSaveRecording(name: String, profile: SoundProfile) {
        recordTimer?.invalidate()
        recordTimer = nil
        isRecording = false
        captureName = nil
        captureProfile = nil
        do {
            let url = try references.stopRecording()
            try saveReference(from: url, name: name, profile: profile, cleanup: true)
        } catch {
            banner = error.localizedDescription
            references.cancelRecording()
        }
    }

    func cancelRecording() {
        recordTimer?.invalidate()
        recordTimer = nil
        isRecording = false
        captureName = nil
        captureProfile = nil
        references.cancelRecording()
        recordURL = nil
    }

    func importAudio(from url: URL, name: String, profile: SoundProfile) {
        do {
            let copied = try references.importFile(url)
            try saveReference(from: copied, name: name, profile: profile, cleanup: true)
        } catch {
            banner = error.localizedDescription
        }
    }

    func clearHistory() {
        try? events.clearEvents()
        refresh()
    }

    func applyDetectionSettings() {
        coordinator.reloadTarget()
    }

    func applySchedule() {
        coordinator.refreshSchedule()
    }

    private func tickRecording() {
        recordLevel = references.currentMeter()
        if let recordStartedAt {
            recordElapsed = Date().timeIntervalSince(recordStartedAt)
            if recordElapsed >= 8 {
                // Auto-stop at the maximum capture window.
                recordTimer?.invalidate()
                recordTimer = nil
                isRecording = false
                if let url = try? references.stopRecording() {
                    let name = captureName ?? "Capture \(formattedClock())"
                    let profile = captureProfile ?? .custom
                    captureName = nil
                    captureProfile = nil
                    try? saveReference(from: url, name: name, profile: profile, cleanup: true)
                }
            }
        }
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

    private func formattedClock() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

extension MonitoringCoordinator {
    func preparePlaybackSession() throws {
        try AudioSessionController().configureForPlayback()
    }
}
