import Accelerate
import AVFoundation
import Foundation

final class AudioFeatureExtractor {
    private let fft = FFTProcessor()
    private let mel = MelFilterBank()
    /// Live frames measure overtones at the loaded target's fundamental.
    var harmonicHz: Float = 0
    private var pending: [Float] = []
    private var rawHistory: [Float] = []
    private var totalReceived = 0
    private var lastSample: Float = 0
    private var frameIndex: Int = 0
    private var streamTime: TimeInterval = 0

    func reset() {
        pending.removeAll(keepingCapacity: true)
        rawHistory.removeAll(keepingCapacity: true)
        totalReceived = 0
        lastSample = 0
        frameIndex = 0
        streamTime = 0
    }

    func append(_ samples: [Float], streamTime: TimeInterval? = nil) -> [AudioFrameFeatures] {
        if let streamTime {
            self.streamTime = streamTime
        }
        rawHistory.append(contentsOf: samples)
        totalReceived += samples.count
        var chunk = samples
        lastSample = PCMConvert.preEmphasis(&chunk, previous: lastSample)
        pending.append(contentsOf: chunk)

        var frames: [AudioFrameFeatures] = []
        while pending.count >= AudioDSP.frameLength {
            let frameSamples = Array(pending.prefix(AudioDSP.frameLength))
            pending.removeFirst(AudioDSP.hopLength)
            let end = frameIndex * AudioDSP.hopLength + AudioDSP.frameLength
            let pitchWindow = rawWindow(endingAt: end)
            frames.append(features(from: frameSamples, pitchWindow: pitchWindow, timestamp: timestampForCurrentFrame()))
            frameIndex += 1
        }
        trimRawHistory()
        return frames
    }

    func extractTemplate(from samples: [Float], profile: SoundProfile) -> ReferenceTemplate {
        reset()
        let frames = append(samples, streamTime: 0)
        reset()
        let voiced = frames.filter { $0.energy >= DetectionParameters.default(for: profile).minEnergy * 0.5 }
        let chosen = voiced.isEmpty ? frames : voiced
        let mfccs = chosen.map { MFCC.l2Normalize($0.mfcc) }
        let mean = meanVector(mfccs)
        let duration = Double(samples.count) / AudioDSP.sampleRate
        let identity = pitchIdentity(of: chosen)
        let harmonic = HarmonicProfile.fingerprint(samples: samples)
        return ReferenceTemplate(
            frames: mfccs,
            mean: mean,
            duration: duration,
            profile: profile,
            pitchHz: identity.hz,
            pitched: identity.pitched,
            partials: harmonic.partials,
            harmonicHz: harmonic.hz,
            harmonicity: harmonic.harmonicity
        )
    }

    func extractTemplate(fromFile url: URL, profile: SoundProfile) throws -> (ReferenceTemplate, [Float], TimeInterval) {
        let (samples, duration) = try Self.loadMono16k(url: url)
        let template = extractTemplate(from: samples, profile: profile)
        return (template, samples, duration)
    }

    static func loadMono16k(url: URL, maxSeconds: Double? = nil) throws -> ([Float], TimeInterval) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        var frameCount = AVAudioFrameCount(file.length)
        if let maxSeconds {
            let sourceLimit = AVAudioFrameCount((maxSeconds * format.sampleRate).rounded(.up)) + 64
            frameCount = min(frameCount, max(1, sourceLimit))
        }
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "SoundGuard", code: 10, userInfo: [NSLocalizedDescriptionKey: "Empty audio file"])
        }
        try file.read(into: buffer)
        var samples = try AudioBufferConvert.floatMono16k(buffer)
        if let maxSeconds {
            let limit = Int((maxSeconds * AudioDSP.sampleRate).rounded(.down))
            if limit >= 0, samples.count > limit {
                samples.removeSubrange(limit...)
            }
        }
        let duration = Double(samples.count) / AudioDSP.sampleRate
        return (samples, duration)
    }

    static func loadEditorAudio(url: URL, maxSeconds: Double = CaptureProcessor.editorLoadLimit) throws -> (samples: [Float], truncated: Bool) {
        let file = try AVAudioFile(forReading: url)
        let sourceRate = file.fileFormat.sampleRate
        let sourceDuration = sourceRate > 0 ? Double(file.length) / sourceRate : 0
        let (samples, _) = try loadMono16k(url: url, maxSeconds: maxSeconds)
        return (samples, sourceDuration > maxSeconds + 0.02)
    }

    private func features(from frame: [Float], pitchWindow: [Float], timestamp: TimeInterval) -> AudioFrameFeatures {
        let energy = PCMConvert.rms(frame)
        let power = frame.withUnsafeBufferPointer { fft.powerSpectrum(frame: $0.baseAddress!, count: $0.count) }
        let logMel = mel.logMel(power: power)
        let mfcc = MFCC.dct(logMel)
        let pitch = PitchEstimator.estimate(pitchWindow)
        let harmonic = HarmonicProfile.measure(power: power, fundamentalHz: harmonicHz)
        return AudioFrameFeatures(
            mfcc: mfcc,
            energy: energy,
            timestamp: timestamp,
            pitchHz: pitch.hz,
            pitchConfidence: pitch.confidence,
            harmonicity: harmonic.harmonicity,
            partials: harmonic.partials
        )
    }

    private func trimRawHistory() {
        let keep = 2048 + AudioDSP.frameLength
        if rawHistory.count > keep {
            rawHistory.removeFirst(rawHistory.count - keep)
        }
    }

    private func rawWindow(endingAt end: Int) -> [Float] {
        let historyStart = totalReceived - rawHistory.count
        let localEnd = end - historyStart
        guard localEnd > 0 else { return [] }
        let clampedEnd = min(localEnd, rawHistory.count)
        let localStart = max(0, clampedEnd - 2048)
        return Array(rawHistory[localStart..<clampedEnd])
    }

    private func pitchIdentity(of frames: [AudioFrameFeatures]) -> (hz: Float, pitched: Bool) {
        let voiced = frames.filter { $0.pitchHz > 1 && $0.pitchConfidence >= 0.6 }
        guard voiced.count >= 4, Double(voiced.count) >= 0.45 * Double(max(frames.count, 1)) else {
            return (0, false)
        }
        let pitches = voiced.map(\.pitchHz)
        let center = Self.median(pitches)
        let spread = Self.median(pitches.map { PitchMatch.semitoneDistance($0, center) })
        guard spread < 0.45 else { return (0, false) }
        return (center, true)
    }

    private static func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return 0.5 * (sorted[middle - 1] + sorted[middle])
        }
        return sorted[middle]
    }

    private func timestampForCurrentFrame() -> TimeInterval {
        streamTime + Double(frameIndex * AudioDSP.hopLength) / AudioDSP.sampleRate
    }

    private func meanVector(_ frames: [[Float]]) -> [Float] {
        guard let first = frames.first else {
            return [Float](repeating: 0, count: AudioDSP.numMFCC)
        }
        var acc = [Float](repeating: 0, count: first.count)
        for frame in frames {
            vDSP_vadd(acc, 1, frame, 1, &acc, 1, vDSP_Length(acc.count))
        }
        var scale = 1 / Float(frames.count)
        vDSP_vsmul(acc, 1, &scale, &acc, 1, vDSP_Length(acc.count))
        return MFCC.l2Normalize(acc)
    }
}

enum AudioBufferConvert {
    static func floatMono16k(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioDSP.sampleRate,
            channels: 1,
            interleaved: false
        )!
        if buffer.format.sampleRate == target.sampleRate,
           buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatFloat32,
           let channel = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: target) else {
            throw NSError(domain: "SoundGuard", code: 11, userInfo: [NSLocalizedDescriptionKey: "Audio conversion failed"])
        }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else {
            throw NSError(domain: "SoundGuard", code: 12, userInfo: [NSLocalizedDescriptionKey: "Could not allocate conversion buffer"])
        }

        var provided = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        guard status != .error, let channel = out.floatChannelData?[0] else {
            throw NSError(domain: "SoundGuard", code: 13, userInfo: [NSLocalizedDescriptionKey: "PCM conversion produced no data"])
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
    }
}
