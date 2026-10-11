import AVFoundation
import Foundation

final class ReferenceAudioService {
    private final class PreviewDelegate: NSObject, AVAudioPlayerDelegate {
        var onFinish: (() -> Void)?
        weak var player: AVAudioPlayer?

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            guard player === self.player else { return }
            let finish = onFinish
            onFinish = nil
            self.player = nil
            finish?()
        }

        func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
            audioPlayerDidFinishPlaying(player, successfully: false)
        }
    }

    private let fileManager = FileManager.default
    private var recorder: AVAudioRecorder?
    private var previewPlayer: AVAudioPlayer?
    private let previewDelegate = PreviewDelegate()
    private let extractor = AudioFeatureExtractor()

    var referencesDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("References", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func fileURL(for fileName: String) -> URL {
        referencesDirectory.appendingPathComponent(fileName)
    }

    func startRecording() throws -> URL {
        stopPreview()
        let temp = referencesDirectory.appendingPathComponent("recording-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: AudioDSP.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let recorder = try AVAudioRecorder(url: temp, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw NSError(domain: "SoundGuard", code: 30, userInfo: [NSLocalizedDescriptionKey: "Recorder failed to start"])
        }
        self.recorder = recorder
        return temp
    }

    func currentMeter() -> Float {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let linear = pow(10.0, Double(db / 20.0))
        return Float(min(1, max(0, linear * 4)))
    }

    func stopRecording() throws -> URL {
        guard let recorder else {
            throw NSError(domain: "SoundGuard", code: 31, userInfo: [NSLocalizedDescriptionKey: "No active recording"])
        }
        recorder.stop()
        let url = recorder.url
        self.recorder = nil
        return url
    }

    func cancelRecording() {
        recorder?.stop()
        if let url = recorder?.url {
            try? fileManager.removeItem(at: url)
        }
        recorder = nil
    }

    func importFile(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer {
            if scoped { source.stopAccessingSecurityScopedResource() }
        }
        let dest = referencesDirectory.appendingPathComponent("import-\(UUID().uuidString).\(source.pathExtension.isEmpty ? "m4a" : source.pathExtension)")
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try fileManager.copyItem(at: source, to: dest)
        return dest
    }

    func buildTemplate(from url: URL, profile: SoundProfile) throws -> (ReferenceTemplate, TimeInterval) {
        let (template, _, duration) = try extractor.extractTemplate(fromFile: url, profile: profile)
        guard duration >= 0.25 else {
            throw NSError(domain: "SoundGuard", code: 32, userInfo: [NSLocalizedDescriptionKey: "Reference is too short (need at least 0.25s)"])
        }
        guard duration <= 12 else {
            throw NSError(domain: "SoundGuard", code: 33, userInfo: [NSLocalizedDescriptionKey: "Reference is too long (max 12s)"])
        }
        guard !template.frames.isEmpty else {
            throw NSError(domain: "SoundGuard", code: 34, userInfo: [NSLocalizedDescriptionKey: "Could not extract features from this audio"])
        }
        return (template, duration)
    }

    func persistCopy(from url: URL, id: UUID) throws -> String {
        let name = "\(id.uuidString).caf"
        let dest = fileURL(for: name)
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }
        try writeNormalizedCAF(from: url, to: dest)
        return name
    }

    func deleteFile(_ fileName: String) {
        let url = fileURL(for: fileName)
        try? fileManager.removeItem(at: url)
    }

    func replaceStoredFile(_ fileName: String, with source: URL) throws {
        let dest = fileURL(for: fileName)
        let temp = fileURL(for: fileName + ".editing")
        let backup = fileURL(for: fileName + ".backup")
        if fileManager.fileExists(atPath: temp.path) {
            try fileManager.removeItem(at: temp)
        }
        try writeNormalizedCAF(from: source, to: temp)
        if fileManager.fileExists(atPath: backup.path) {
            try fileManager.removeItem(at: backup)
        }
        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.moveItem(at: dest, to: backup)
        }
        do {
            try fileManager.moveItem(at: temp, to: dest)
            if fileManager.fileExists(atPath: backup.path) {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            if fileManager.fileExists(atPath: backup.path), !fileManager.fileExists(atPath: dest.path) {
                try? fileManager.moveItem(at: backup, to: dest)
            }
            throw error
        }
    }

    func preview(_ url: URL, onFinish: @escaping () -> Void) throws {
        cancelPreview()
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = previewDelegate
        previewDelegate.player = player
        previewDelegate.onFinish = onFinish
        player.prepareToPlay()
        guard player.play() else {
            previewDelegate.onFinish = nil
            previewDelegate.player = nil
            throw NSError(domain: "SoundGuard", code: 36, userInfo: [NSLocalizedDescriptionKey: "Could not play this recording"])
        }
        previewPlayer = player
    }

    func stopPreview() {
        let finish = previewDelegate.onFinish
        cancelPreview()
        finish?()
    }

    private func cancelPreview() {
        previewDelegate.onFinish = nil
        previewDelegate.player = nil
        previewPlayer?.stop()
        previewPlayer = nil
    }

    func encode(_ template: ReferenceTemplate) throws -> Data {
        try JSONEncoder().encode(template)
    }

    func decodeTemplate(_ data: Data) throws -> ReferenceTemplate {
        try JSONDecoder().decode(ReferenceTemplate.self, from: data)
    }

    private func writeNormalizedCAF(from url: URL, to dest: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioDSP.sampleRate,
            channels: 1,
            interleaved: false
        )!
        let outFile = try AVAudioFile(forWriting: dest, settings: outFormat.settings)
        let remaining = AVAudioFrameCount(file.length)
        guard remaining > 0 else {
            throw NSError(domain: "SoundGuard", code: 35, userInfo: [NSLocalizedDescriptionKey: "Source audio is empty"])
        }
        let chunk: AVAudioFrameCount = 4096
        var left = remaining
        let converter = AVAudioConverter(from: inFormat, to: outFormat)
        while left > 0 {
            let frames = min(chunk, left)
            guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else { break }
            try file.read(into: inBuffer, frameCount: frames)
            left -= inBuffer.frameLength
            if inFormat == outFormat {
                try outFile.write(from: inBuffer)
                continue
            }
            guard let converter else { break }
            let outFrames = AVAudioFrameCount(Double(inBuffer.frameLength) * outFormat.sampleRate / inFormat.sampleRate) + 32
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: max(outFrames, 64)) else { break }
            var provided = false
            var error: NSError?
            converter.convert(to: outBuffer, error: &error) { _, status in
                if provided {
                    status.pointee = .noDataNow
                    return nil
                }
                provided = true
                status.pointee = .haveData
                return inBuffer
            }
            if let error { throw error }
            if outBuffer.frameLength > 0 {
                try outFile.write(from: outBuffer)
            }
        }
    }
}
