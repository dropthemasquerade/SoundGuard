import AVFoundation
import Foundation

final class AudioSessionController {
    private let session = AVAudioSession.sharedInstance()
    private let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]

    func configureForMonitoring() throws {
        try apply(mode: .measurement)
    }

    func configureForPlayback() throws {
        try apply(mode: .default)
    }

    /// Speaker playback while the microphone session is already active.
    /// Changing category under a running engine is what raises OSStatus !int (560557684).
    func keepCurrentSessionForPlayback() throws {
        if session.category == .playAndRecord {
            try ensureActive()
            return
        }
        try configureForPlayback()
    }

    func deactivate() {
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    static func message(for error: Error) -> String {
        if isCannotInterrupt(error) {
            return "Audio is busy. Stop other audio using the microphone or speaker, then try again."
        }
        let text = error.localizedDescription
        if text.contains("560557684") {
            return "Audio is busy. Stop other audio using the microphone or speaker, then try again."
        }
        return text
    }

    private func apply(mode: AVAudioSession.Mode) throws {
        if session.category == .playAndRecord, session.mode == mode {
            try ensureActive()
            return
        }
        do {
            try session.setCategory(.playAndRecord, mode: mode, options: options)
            try session.setActive(true)
        } catch {
            if Self.isCannotInterrupt(error), session.category == .playAndRecord {
                try? session.setActive(true)
                return
            }
            throw Self.wrapped(error)
        }
    }

    private func ensureActive() throws {
        do {
            try session.setActive(true)
        } catch {
            if Self.isCannotInterrupt(error) { return }
            throw Self.wrapped(error)
        }
    }

    private static func isCannotInterrupt(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.code == AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue
            || ns.code == 560557684
    }

    private static func wrapped(_ error: Error) -> Error {
        let text = message(for: error)
        if text == error.localizedDescription { return error }
        return NSError(domain: "SoundGuard", code: 560557684, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
