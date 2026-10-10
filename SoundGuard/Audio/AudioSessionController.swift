import AVFoundation
import Foundation

final class AudioSessionController {
    func configureForMonitoring() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
        try session.setActive(true, options: [])
    }

    func configureForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .mixWithOthers]
        )
        try session.setActive(true, options: [])
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
