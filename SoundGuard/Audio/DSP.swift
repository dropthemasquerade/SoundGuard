import Accelerate
import Foundation

enum AudioDSP {
    static let sampleRate: Double = 16_000
    static let frameLength = 400
    static let hopLength = 160
    static let fftSize = 512
    static let numMel = 26
    static let numMFCC = 13
    static let preEmphasis: Float = 0.97
    static let eps: Float = 1e-10
}

final class FFTProcessor {
    let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var packed: [Float]
    private var magnitudes: [Float]

    var binCount: Int { fftSize / 2 }

    init(fftSize: Int = AudioDSP.fftSize, windowLength: Int = AudioDSP.frameLength) {
        self.fftSize = fftSize
        log2n = vDSP_Length(log2(Double(fftSize)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: windowLength)
        vDSP_hamm_window(&window, vDSP_Length(windowLength), 0)
        realp = [Float](repeating: 0, count: fftSize / 2)
        imagp = [Float](repeating: 0, count: fftSize / 2)
        packed = [Float](repeating: 0, count: fftSize)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func powerSpectrum(frame: UnsafePointer<Float>, count: Int) -> [Float] {
        packed = [Float](repeating: 0, count: fftSize)
        let n = min(count, window.count)
        packed.withUnsafeMutableBufferPointer { dst in
            vDSP_vmul(frame, 1, window, 1, dst.baseAddress!, 1, vDSP_Length(n))
        }

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                packed.withUnsafeMutableBufferPointer { src in
                    src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        var scale: Float = 1.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))
        return magnitudes
    }
}

struct MelFilterBank {
    let weights: [[Float]]
    let numMel: Int
    let numBins: Int

    init(
        sampleRate: Double = AudioDSP.sampleRate,
        fftSize: Int = AudioDSP.fftSize,
        numMel: Int = AudioDSP.numMel,
        minHz: Double = 80,
        maxHz: Double = 8_000
    ) {
        self.numMel = numMel
        let bins = fftSize / 2
        numBins = bins
        let nyquist = sampleRate / 2
        let high = min(maxHz, nyquist)
        let melMin = Self.hzToMel(minHz)
        let melMax = Self.hzToMel(high)
        var points = [Double](repeating: 0, count: numMel + 2)
        for i in 0..<points.count {
            let mel = melMin + (melMax - melMin) * Double(i) / Double(numMel + 1)
            points[i] = Self.melToHz(mel)
        }
        let binPoints = points.map { hz -> Int in
            let bin = Int(floor((Double(fftSize) + 1) * hz / sampleRate))
            return min(max(bin, 0), bins - 1)
        }

        var matrix = Array(repeating: [Float](repeating: 0, count: bins), count: numMel)
        for m in 1...numMel {
            let left = binPoints[m - 1]
            let center = binPoints[m]
            let right = binPoints[m + 1]
            if center > left {
                for k in left..<center {
                    matrix[m - 1][k] = Float(k - left) / Float(center - left)
                }
            }
            if right > center {
                for k in center..<right {
                    matrix[m - 1][k] = Float(right - k) / Float(right - center)
                }
            }
            matrix[m - 1][center] = 1
        }
        weights = matrix
    }

    func logMel(power: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: numMel)
        for m in 0..<numMel {
            var sum: Float = 0
            let row = weights[m]
            let n = min(row.count, power.count)
            vDSP_dotpr(row, 1, power, 1, &sum, vDSP_Length(n))
            result[m] = log(max(sum, AudioDSP.eps))
        }
        return result
    }

    private static func hzToMel(_ hz: Double) -> Double {
        2595.0 * log10(1.0 + hz / 700.0)
    }

    private static func melToHz(_ mel: Double) -> Double {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }
}

enum MFCC {
    static func dct(_ logMel: [Float], numCoefficients: Int = AudioDSP.numMFCC) -> [Float] {
        let n = logMel.count
        guard n > 0 else { return [Float](repeating: 0, count: numCoefficients) }
        var out = [Float](repeating: 0, count: numCoefficients)
        let scale0 = sqrt(1.0 / Float(n))
        let scale = sqrt(2.0 / Float(n))
        for k in 0..<numCoefficients {
            var sum: Float = 0
            for i in 0..<n {
                sum += logMel[i] * cos(.pi * Float(k) * (2 * Float(i) + 1) / (2 * Float(n)))
            }
            out[k] = sum * (k == 0 ? scale0 : scale)
        }
        return out
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(n))
        vDSP_svesq(a, 1, &na, vDSP_Length(n))
        vDSP_svesq(b, 1, &nb, vDSP_Length(n))
        let denom = sqrt(na) * sqrt(nb)
        guard denom > AudioDSP.eps else { return 0 }
        let value = dot / denom
        if value.isNaN || value.isInfinite { return 0 }
        return max(-1, min(1, value))
    }

    static func l2Normalize(_ vector: [Float]) -> [Float] {
        var sumsq: Float = 0
        vDSP_svesq(vector, 1, &sumsq, vDSP_Length(vector.count))
        let norm = sqrt(sumsq)
        guard norm > AudioDSP.eps else { return vector }
        var scale = 1 / norm
        var out = vector
        vDSP_vsmul(vector, 1, &scale, &out, 1, vDSP_Length(vector.count))
        return out
    }
}

enum PitchMatch {
    /// About ±35 cents still matches. The next semitone, 100 cents away, does not.
    static let sigmaSemitones: Float = 0.70

    static func semitoneDistance(_ a: Float, _ b: Float) -> Float {
        guard a > 1, b > 1 else { return 99 }
        return abs(12 * log2(a / b))
    }

    static func similarity(semitones: Float) -> Float {
        let x = semitones / sigmaSemitones
        return exp(-0.5 * x * x)
    }

    static func score(pitchHz: Float, confidence: Float, referenceHz: Float, timbre: Float) -> Float {
        guard confidence >= 0.55, pitchHz > 1, referenceHz > 1 else { return 0 }
        let pitchSim = similarity(semitones: semitoneDistance(pitchHz, referenceHz))
        let tone = max(0, min(1, timbre))
        return pitchSim * (0.62 + 0.38 * tone)
    }
}

enum PitchEstimator {
    /// YIN fundamental estimate. Returns 0 Hz when the frame is unpitched or too short.
    static func estimate(_ samples: [Float], sampleRate: Double = AudioDSP.sampleRate) -> (hz: Float, confidence: Float) {
        let count = samples.count
        guard count >= 800 else { return (0, 0) }
        var energy: Float = 0
        vDSP_svesq(samples, 1, &energy, vDSP_Length(count))
        if energy / Float(count) < 1e-7 { return (0, 0) }

        let maxFrequency = 4200.0
        let minFrequency = 27.5
        let tauMin = max(2, Int(sampleRate / maxFrequency))
        let tauMax = min(count / 2 - 1, Int(sampleRate / minFrequency))
        guard tauMax > tauMin + 4 else { return (0, 0) }
        let window = count - tauMax
        guard window >= 256 else { return (0, 0) }

        var difference = [Float](repeating: 0, count: tauMax + 1)
        var scratch = [Float](repeating: 0, count: window)
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for tau in 1...tauMax {
                vDSP_vsub(base + tau, 1, base, 1, &scratch, 1, vDSP_Length(window))
                var sum: Float = 0
                vDSP_svesq(scratch, 1, &sum, vDSP_Length(window))
                difference[tau] = sum
            }
        }

        var cmnd = [Float](repeating: 1, count: tauMax + 1)
        var running: Float = 0
        for tau in 1...tauMax {
            running += difference[tau]
            cmnd[tau] = difference[tau] * Float(tau) / max(running, 1e-8)
        }

        let threshold: Float = 0.15
        var tau = tauMin
        var chosen = -1
        while tau <= tauMax {
            if cmnd[tau] < threshold {
                while tau + 1 <= tauMax, cmnd[tau + 1] < cmnd[tau] {
                    tau += 1
                }
                chosen = tau
                break
            }
            tau += 1
        }
        if chosen < 0 {
            var best = tauMin
            var bestValue = cmnd[tauMin]
            for candidate in (tauMin + 1)...tauMax where cmnd[candidate] < bestValue {
                best = candidate
                bestValue = cmnd[candidate]
            }
            if bestValue > 0.45 { return (0, 0) }
            chosen = best
        }

        chosen = preferFundamental(
            chosen,
            cmnd: cmnd,
            samples: samples,
            sampleRate: sampleRate,
            tauMax: tauMax,
            minFrequency: minFrequency
        )

        var refined = Float(chosen)
        if chosen > 0, chosen < tauMax {
            let left = cmnd[chosen - 1]
            let center = cmnd[chosen]
            let right = cmnd[chosen + 1]
            let denom = left - 2 * center + right
            if abs(denom) > 1e-8 {
                refined = Float(chosen) + 0.5 * (left - right) / denom
            }
        }
        guard refined > 1 else { return (0, 0) }
        let hz = Float(sampleRate / Double(refined))
        let confidence = max(0, min(1, 1 - cmnd[min(chosen, cmnd.count - 1)]))
        return (hz, confidence)
    }

    /// Move an octave down only when that lower partial is actually present.
    private static func preferFundamental(
        _ tau: Int,
        cmnd: [Float],
        samples: [Float],
        sampleRate: Double,
        tauMax: Int,
        minFrequency: Double
    ) -> Int {
        var chosen = tau
        for _ in 0..<2 {
            let doubled = chosen * 2
            guard doubled + 1 <= tauMax else { break }
            var neighbor = doubled
            if cmnd[doubled - 1] < cmnd[neighbor] { neighbor = doubled - 1 }
            if doubled + 1 <= tauMax, cmnd[doubled + 1] < cmnd[neighbor] { neighbor = doubled + 1 }
            let higherHz = sampleRate / Double(chosen)
            let lowerHz = sampleRate / Double(neighbor)
            guard lowerHz >= minFrequency, cmnd[neighbor] < 0.3 else { break }
            var signal: Float = 0
            vDSP_svesq(samples, 1, &signal, vDSP_Length(samples.count))
            let floor = signal * 0.02
            let higherEnergy = partialEnergy(samples, hz: higherHz, sampleRate: sampleRate)
            let lowerEnergy = partialEnergy(samples, hz: lowerHz, sampleRate: sampleRate)
            if higherEnergy > floor, lowerEnergy > floor, lowerEnergy > higherEnergy * 0.35 {
                chosen = neighbor
            } else {
                break
            }
        }
        return chosen
    }

    private static func partialEnergy(_ samples: [Float], hz: Double, sampleRate: Double) -> Float {
        guard hz > 1, !samples.isEmpty else { return 0 }
        let omega = 2 * Double.pi * hz / sampleRate
        var sine: Double = 0
        var cosine: Double = 0
        for (index, sample) in samples.enumerated() {
            let angle = omega * Double(index)
            let value = Double(sample)
            sine += value * sin(angle)
            cosine += value * cos(angle)
        }
        return Float(sine * sine + cosine * cosine)
    }
}

enum PCMConvert {
    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
        return sqrt(meanSquare)
    }

    static func preEmphasis(_ samples: inout [Float], previous: Float) -> Float {
        guard !samples.isEmpty else { return previous }
        var prev = previous
        for i in 0..<samples.count {
            let current = samples[i]
            samples[i] = current - AudioDSP.preEmphasis * prev
            prev = current
        }
        return prev
    }
}
