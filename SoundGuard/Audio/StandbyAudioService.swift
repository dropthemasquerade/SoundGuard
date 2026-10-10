import AVFoundation
import Foundation

/// Keeps the process awake between active hours so the microphone can start
/// while the phone is locked. Playback is effectively silent. Force-quit still stops it.
final class StandbyAudioService {
    private var player: AVAudioPlayer?
    private let session = AVAudioSession.sharedInstance()

    var isRunning: Bool { player?.isPlaying == true }

    func start() {
        if isRunning { return }
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: Self.toneURL())
            player.numberOfLoops = -1
            player.volume = 1
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            self.player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private static func toneURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("soundguard-standby.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sampleRate = 16_000
        let frameCount = sampleRate
        var pcm = Data(count: frameCount * MemoryLayout<Int16>.size)
        pcm.withUnsafeMutableBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for index in stride(from: 0, to: frameCount, by: 80) {
                samples[index] = 1
            }
        }
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: string.utf8) }
        func appendU32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func appendU16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let dataSize = UInt32(pcm.count)
        append("RIFF")
        appendU32(36 + dataSize)
        append("WAVE")
        append("fmt ")
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate) * 2)
        appendU16(2)
        appendU16(16)
        append("data")
        appendU32(dataSize)
        data.append(pcm)
        try data.write(to: url)
        return url
    }
}
