import Accelerate
import Foundation

struct CaptureEdit: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var denoise: Bool
    var enhance: Bool

    static func full(duration: TimeInterval) -> CaptureEdit {
        CaptureEdit(start: 0, end: duration, denoise: false, enhance: false)
    }
}

enum CaptureProcessor {
    static let minimumDuration: TimeInterval = 0.25
    static let maximumDuration: TimeInterval = 12
    static let editorLoadLimit: TimeInterval = 60

    static func duration(of samples: [Float], sampleRate: Double = AudioDSP.sampleRate) -> TimeInterval {
        Double(samples.count) / sampleRate
    }

    /// Analysis/synthesis with no spectral change. Used to lock the STFT scale.
    static func roundTrip(_ samples: [Float]) -> [Float] {
        guard samples.count >= 64 else { return samples }
        let engine = SpectrumEngine()
        let frames = engine.analyze(samples)
        return engine.synthesize(
            realFrames: frames.map(\.real),
            imagFrames: frames.map(\.imag),
            length: samples.count
        )
    }

    static func limitMessage(start: TimeInterval, end: TimeInterval) -> String? {
        let length = end - start
        if length + 0.000_1 < minimumDuration {
            return "Keep at least 0.25 seconds."
        }
        if length - 0.000_1 > maximumDuration {
            return "Crop to 12 seconds or less."
        }
        return nil
    }

    static func process(
        _ samples: [Float],
        edit: CaptureEdit,
        sampleRate: Double = AudioDSP.sampleRate
    ) -> [Float] {
        var output = crop(samples, start: edit.start, end: edit.end, sampleRate: sampleRate)
        if edit.denoise {
            output = reduceNoise(output, sampleRate: sampleRate)
        }
        if edit.enhance {
            output = enhance(output, sampleRate: sampleRate)
        }
        return output
    }

    static func crop(
        _ samples: [Float],
        start: TimeInterval,
        end: TimeInterval,
        sampleRate: Double = AudioDSP.sampleRate
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let duration = Double(samples.count) / sampleRate
        var startTime = min(max(0, start), duration)
        var endTime = min(max(0, end), duration)
        if endTime < startTime {
            swap(&startTime, &endTime)
        }
        var startIndex = Int((startTime * sampleRate).rounded(.toNearestOrAwayFromZero))
        var endIndex = Int((endTime * sampleRate).rounded(.toNearestOrAwayFromZero))
        startIndex = min(max(0, startIndex), samples.count)
        endIndex = min(max(0, endIndex), samples.count)
        if endIndex <= startIndex {
            endIndex = min(samples.count, startIndex + 1)
        }
        var sliced = Array(samples[startIndex..<endIndex])
        fadeCuts(
            &sliced,
            fadeIn: startIndex > 0,
            fadeOut: endIndex < samples.count,
            sampleRate: sampleRate
        )
        return sliced
    }

    /// Spectral subtraction. Quiet frames supply the noise profile. A clip that is
    /// all tone only sheds a fraction of its own floor, so a clean beep stays intact.
    static func reduceNoise(_ samples: [Float], sampleRate: Double = AudioDSP.sampleRate) -> [Float] {
        guard samples.count >= 64 else { return samples }
        let engine = SpectrumEngine()
        let frames = engine.analyze(samples)
        guard !frames.isEmpty else { return samples }
        let noise = noiseProfile(frames: frames, engine: engine, samples: samples)
        var previous = rawGain(magnitudes: frames[0].magnitudes, noise: noise)
        var realFrames: [[Float]] = []
        var imagFrames: [[Float]] = []
        realFrames.reserveCapacity(frames.count)
        imagFrames.reserveCapacity(frames.count)

        for frame in frames {
            let gain = smoothedGain(magnitudes: frame.magnitudes, noise: noise, previous: &previous)
            var real = frame.real
            var imag = frame.imag
            let last = real.count - 1
            for bin in 0..<engine.binCount {
                let g = gain[bin]
                real[bin] *= g
                imag[bin] *= g
                if bin > 0, bin < engine.binCount - 1 {
                    let mirror = last - bin
                    real[mirror] *= g
                    imag[mirror] *= g
                }
            }
            realFrames.append(real)
            imagFrames.append(imag)
        }
        return limitPeak(engine.synthesize(realFrames: realFrames, imagFrames: imagFrames, length: samples.count))
    }

    /// High-pass rumble, a mild presence lift, then makeup gain that will not clip.
    static func enhance(_ samples: [Float], sampleRate: Double = AudioDSP.sampleRate) -> [Float] {
        guard samples.count >= 8 else { return samples }
        var highPass = Biquad.highPass(cutoff: 90, sampleRate: sampleRate)
        var presence = Biquad.peaking(frequency: 2_500, gainDB: 4, q: 0.9, sampleRate: sampleRate)
        var output = presence.process(highPass.process(samples))
        output = applyMakeupGain(output)
        return limitPeak(output, ceiling: 0.97)
    }

    private static func fadeCuts(
        _ samples: inout [Float],
        fadeIn: Bool,
        fadeOut: Bool,
        sampleRate: Double
    ) {
        let fade = min(Int(0.005 * sampleRate), samples.count / 4)
        guard fade > 1 else { return }
        if fadeIn {
            for index in 0..<fade {
                samples[index] *= Float(index) / Float(fade)
            }
        }
        if fadeOut {
            for index in 0..<fade {
                samples[samples.count - 1 - index] *= Float(index) / Float(fade)
            }
        }
    }

    private static func noiseProfile(
        frames: [SpectrumFrame],
        engine: SpectrumEngine,
        samples: [Float]
    ) -> [Float] {
        var energies = [Float](repeating: 0, count: frames.count)
        for index in frames.indices {
            let start = index * engine.hop
            let end = min(samples.count, start + engine.fftSize)
            let count = end - start
            guard count > 0 else { continue }
            var sum: Float = 0
            samples.withUnsafeBufferPointer { buffer in
                vDSP_svesq(buffer.baseAddress! + start, 1, &sum, vDSP_Length(count))
            }
            energies[index] = sum / Float(count)
        }
        let sorted = energies.sorted()
        let quiet = sorted[max(0, sorted.count / 5)]
        let loud = sorted[min(sorted.count - 1, sorted.count * 4 / 5)]
        // A clip with no quieter region is the target itself. Only shave its floor.
        let steady = loud < max(quiet, 1e-12) * 3

        var chosen: [Int] = []
        if steady {
            chosen = Array(frames.indices)
        } else {
            let cutoff = max(quiet * 1.25, 1e-12)
            chosen = energies.indices.filter { energies[$0] <= cutoff }
            if chosen.count < 2 {
                let keep = max(1, frames.count / 5)
                chosen = energies.enumerated().sorted { $0.element < $1.element }.prefix(keep).map(\.offset)
            }
        }

        var noise = [Float](repeating: 0, count: engine.binCount)
        for bin in 0..<engine.binCount {
            let values = chosen.map { frames[$0].magnitudes[bin] }.sorted()
            noise[bin] = values[values.count / 2]
        }
        if steady {
            var scale: Float = 0.12
            vDSP_vsmul(noise, 1, &scale, &noise, 1, vDSP_Length(noise.count))
        }
        return movingAverage(noise, radius: 2)
    }

    private static func rawGain(magnitudes: [Float], noise: [Float]) -> [Float] {
        let oversubtraction: Float = 1.8
        let floorGain: Float = 0.07
        var gain = [Float](repeating: 1, count: magnitudes.count)
        for bin in 0..<magnitudes.count {
            let ratio = noise[bin] / max(magnitudes[bin], 1e-8)
            var value = 1 - oversubtraction * ratio
            if value < floorGain { value = floorGain }
            if value > 1 { value = 1 }
            gain[bin] = value
        }
        return movingAverage(gain, radius: 1)
    }

    private static func smoothedGain(
        magnitudes: [Float],
        noise: [Float],
        previous: inout [Float]
    ) -> [Float] {
        let target = rawGain(magnitudes: magnitudes, noise: noise)
        var gain = target
        for bin in 0..<gain.count {
            let value = target[bin]
            if value > previous[bin] {
                previous[bin] = 0.40 * previous[bin] + 0.60 * value
            } else {
                previous[bin] = 0.82 * previous[bin] + 0.18 * value
            }
            gain[bin] = previous[bin]
        }
        return gain
    }

    private static func movingAverage(_ values: [Float], radius: Int) -> [Float] {
        guard radius > 0, values.count > 1 else { return values }
        var output = values
        for index in 0..<values.count {
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            var sum: Float = 0
            for cursor in lower...upper {
                sum += values[cursor]
            }
            output[index] = sum / Float(upper - lower + 1)
        }
        return output
    }

    private static func applyMakeupGain(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let rms = PCMConvert.rms(samples)
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        guard rms > 1e-6, peak > 1e-6 else { return samples }
        let targetRMS: Float = 0.10
        let ceiling: Float = 0.94
        var gain: Float = 1
        if rms < targetRMS {
            gain = min(targetRMS / rms, ceiling / peak)
        } else if peak > ceiling {
            gain = ceiling / peak
        }
        guard abs(gain - 1) > 0.001 else { return samples }
        var output = samples
        vDSP_vsmul(samples, 1, &gain, &output, 1, vDSP_Length(samples.count))
        return output
    }

    private static func limitPeak(_ samples: [Float], ceiling: Float = 0.99) -> [Float] {
        guard !samples.isEmpty else { return samples }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        var output = samples
        if peak > ceiling, peak.isFinite {
            var scale = ceiling / peak
            vDSP_vsmul(output, 1, &scale, &output, 1, vDSP_Length(output.count))
        }
        for index in 0..<output.count where !output[index].isFinite {
            output[index] = 0
        }
        return output
    }
}

private struct SpectrumFrame {
    var real: [Float]
    var imag: [Float]
    var magnitudes: [Float]
}

private final class SpectrumEngine {
    let fftSize = 512
    let hop = 128
    let binCount: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]

    init() {
        binCount = fftSize / 2 + 1
        log2n = vDSP_Length(log2(Double(fftSize)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        var built = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&built, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))
        window = built
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func analyze(_ samples: [Float]) -> [SpectrumFrame] {
        let frameCount = samples.count <= fftSize ? 1 : 1 + (samples.count - fftSize + hop - 1) / hop
        var frames: [SpectrumFrame] = []
        frames.reserveCapacity(frameCount)
        for index in 0..<frameCount {
            let start = index * hop
            let frame = windowedFrame(samples, start: start)
            let spectrum = forward(frame)
            frames.append(spectrum)
        }
        return frames
    }

    func synthesize(realFrames: [[Float]], imagFrames: [[Float]], length: Int) -> [Float] {
        guard length > 0 else { return [] }
        var output = [Float](repeating: 0, count: length)
        var weight = [Float](repeating: 0, count: length)
        for index in 0..<realFrames.count {
            let start = index * hop
            let time = inverse(real: realFrames[index], imag: imagFrames[index])
            let count = min(fftSize, length - start)
            guard count > 0 else { continue }
            for offset in 0..<count {
                let windowValue = window[offset]
                output[start + offset] += time[offset] * windowValue
                weight[start + offset] += windowValue * windowValue
            }
        }
        let maxWeight = weight.max() ?? 0
        // Spectral edits do not match the analysis window at the fade-in.
        // Dividing by a tiny weight there turns that mismatch into a spike.
        let floor = maxWeight * 0.25
        guard floor > 0 else { return output }
        for index in 0..<length {
            output[index] /= max(weight[index], floor)
        }
        return output
    }

    private func windowedFrame(_ samples: [Float], start: Int) -> [Float] {
        var frame = [Float](repeating: 0, count: fftSize)
        guard start < samples.count else { return frame }
        let available = min(fftSize, samples.count - start)
        for index in 0..<available {
            frame[index] = samples[start + index] * window[index]
        }
        return frame
    }

    private func forward(_ frame: [Float]) -> SpectrumFrame {
        var real = frame
        var imag = [Float](repeating: 0, count: fftSize)
        real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        var magnitudes = [Float](repeating: 0, count: binCount)
        for bin in 0..<binCount {
            magnitudes[bin] = hypot(real[bin], imag[bin])
        }
        return SpectrumFrame(real: real, imag: imag, magnitudes: magnitudes)
    }

    private func inverse(real: [Float], imag: [Float]) -> [Float] {
        var real = real
        var imag = imag
        real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
            }
        }
        var scale = 1 / Float(fftSize)
        vDSP_vsmul(real, 1, &scale, &real, 1, vDSP_Length(fftSize))
        return real
    }
}

private struct Biquad {
    var b0: Float
    var b1: Float
    var b2: Float
    var a1: Float
    var a2: Float
    private var x1: Float = 0
    private var x2: Float = 0
    private var y1: Float = 0
    private var y2: Float = 0

    static func highPass(cutoff: Double, sampleRate: Double, q: Double = 0.707) -> Biquad {
        let angular = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(angular) / (2 * q)
        let cosine = cos(angular)
        let b0 = (1 + cosine) / 2
        let b1 = -(1 + cosine)
        let b2 = (1 + cosine) / 2
        let a0 = 1 + alpha
        return Biquad(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(-2 * cosine / a0),
            a2: Float((1 - alpha) / a0)
        )
    }

    static func peaking(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> Biquad {
        let amplitude = pow(10, gainDB / 40)
        let angular = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(angular) / (2 * q)
        let cosine = cos(angular)
        let b0 = 1 + alpha * amplitude
        let b1 = -2 * cosine
        let b2 = 1 - alpha * amplitude
        let a0 = 1 + alpha / amplitude
        return Biquad(
            b0: Float(b0 / a0),
            b1: Float(b1 / a0),
            b2: Float(b2 / a0),
            a1: Float(-2 * cosine / a0),
            a2: Float((1 - alpha / amplitude) / a0)
        )
    }

    mutating func process(_ samples: [Float]) -> [Float] {
        var output = samples
        for index in 0..<output.count {
            let input = output[index]
            let value = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = input
            y2 = y1
            y1 = value
            output[index] = value
        }
        return output
    }
}
