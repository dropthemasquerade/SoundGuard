import AVFoundation
import Foundation

final class AudioCaptureService {
    var onSamples: (([Float], TimeInterval) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onError: ((Error) -> Void)?

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioDSP.sampleRate,
        channels: 1,
        interleaved: false
    )!
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var running = false

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    func start() throws {
        lock.lock()
        let already = running
        lock.unlock()
        if already { return }

        if AVAudioApplication.shared.recordPermission != .granted {
            throw NSError(domain: "SoundGuard", code: 20, userInfo: [NSLocalizedDescriptionKey: "Microphone permission is not granted"])
        }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "SoundGuard", code: 21, userInfo: [NSLocalizedDescriptionKey: "Audio input is not available"])
        }

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.handle(buffer: buffer, time: time)
        }

        engine.prepare()
        try engine.start()
        lock.lock()
        running = true
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        lock.unlock()
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
    }

    private func handle(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        do {
            let samples = try convert(buffer)
            guard !samples.isEmpty else { return }
            onLevel?(PCMConvert.rms(samples))
            let seconds = AVAudioTime.seconds(forHostTime: time.hostTime)
            onSamples?(samples, seconds)
        } catch {
            onError?(error)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        if buffer.format.sampleRate == targetFormat.sampleRate,
           buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatFloat32,
           let channel = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        return try AudioBufferConvert.floatMono16k(buffer)
    }
}
