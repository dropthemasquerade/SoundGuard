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
    private var tapInstalled = false

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
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            self?.handle(buffer: buffer, time: time)
        }
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            if engine.isRunning { engine.stop() }
            converter = nil
            throw error
        }
        lock.lock()
        running = true
        lock.unlock()
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
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
