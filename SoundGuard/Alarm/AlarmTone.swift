import Foundation

/// Original alarm loops. These are simple synthesized tones, not copied ringtones.
enum AlarmTone: String, CaseIterable, Identifiable {
    case classic
    case pulse
    case siren
    case klaxon
    case rapid
    case horn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "CLASSIC"
        case .pulse: return "PULSE"
        case .siren: return "SIREN"
        case .klaxon: return "KLAXON"
        case .rapid: return "RAPID"
        case .horn: return "HORN"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "Bundled loop"
        case .pulse: return "Double beep"
        case .siren: return "Rising sweep"
        case .klaxon: return "Two-tone"
        case .rapid: return "Fast chirps"
        case .horn: return "Low horn"
        }
    }

    func fileURL() -> URL? {
        if self == .classic {
            return Bundle.main.url(forResource: "alarm_loop", withExtension: "wav")
        }
        let url = Self.cacheDirectory.appendingPathComponent("\(rawValue).wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let samples = Self.render(self)
        try? WaveFile.write(samples: samples, to: url)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AlarmTones", isDirectory: true)
    }

    static func render(_ tone: AlarmTone) -> [Float] {
        let rate = 16_000.0
        switch tone {
        case .classic:
            return []
        case .pulse:
            return stitch([
                toneburst(rate: rate, hz: 880, seconds: 0.1, amplitude: 0.75),
                silence(rate: rate, seconds: 0.08),
                toneburst(rate: rate, hz: 880, seconds: 0.1, amplitude: 0.75),
                silence(rate: rate, seconds: 0.42)
            ])
        case .siren:
            return stitch([
                sweep(rate: rate, from: 520, to: 1500, seconds: 0.75, amplitude: 0.72),
                sweep(rate: rate, from: 1500, to: 520, seconds: 0.75, amplitude: 0.72)
            ])
        case .klaxon:
            return stitch([
                toneburst(rate: rate, hz: 680, seconds: 0.16, amplitude: 0.75),
                toneburst(rate: rate, hz: 420, seconds: 0.16, amplitude: 0.75),
                toneburst(rate: rate, hz: 680, seconds: 0.16, amplitude: 0.75),
                toneburst(rate: rate, hz: 420, seconds: 0.16, amplitude: 0.75)
            ])
        case .rapid:
            var parts: [[Float]] = []
            for _ in 0..<8 {
                parts.append(toneburst(rate: rate, hz: 1760, seconds: 0.045, amplitude: 0.7))
                parts.append(silence(rate: rate, seconds: 0.045))
            }
            return stitch(parts)
        case .horn:
            return stitch([
                horn(rate: rate, seconds: 0.38, amplitude: 0.8),
                silence(rate: rate, seconds: 0.16),
                horn(rate: rate, seconds: 0.38, amplitude: 0.8),
                silence(rate: rate, seconds: 0.16)
            ])
        }
    }

    private static func silence(rate: Double, seconds: Double) -> [Float] {
        Array(repeating: 0, count: Int(rate * seconds))
    }

    private static func toneburst(rate: Double, hz: Double, seconds: Double, amplitude: Float) -> [Float] {
        let count = Int(rate * seconds)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / rate
            samples[index] = amplitude * Float(sin(2 * Double.pi * hz * t))
        }
        fade(&samples, rate: rate)
        return samples
    }

    private static func sweep(rate: Double, from: Double, to: Double, seconds: Double, amplitude: Float) -> [Float] {
        let count = Int(rate * seconds)
        var samples = [Float](repeating: 0, count: count)
        var phase = 0.0
        for index in 0..<count {
            let x = Double(index) / Double(max(count - 1, 1))
            let hz = from + (to - from) * x
            phase += 2 * Double.pi * hz / rate
            samples[index] = amplitude * Float(sin(phase))
        }
        fade(&samples, rate: rate)
        return samples
    }

    private static func horn(rate: Double, seconds: Double, amplitude: Float) -> [Float] {
        let count = Int(rate * seconds)
        var samples = [Float](repeating: 0, count: count)
        let fundamental = 196.0
        for index in 0..<count {
            let t = Double(index) / rate
            let body = sin(2 * Double.pi * fundamental * t)
            let edge = sin(2 * Double.pi * fundamental * 2 * t)
            samples[index] = amplitude * Float(0.72 * body + 0.28 * edge)
        }
        fade(&samples, rate: rate)
        return samples
    }

    private static func fade(_ samples: inout [Float], rate: Double) {
        let ramp = min(samples.count / 2, Int(rate * 0.008))
        guard ramp > 1 else { return }
        for index in 0..<ramp {
            let gain = Float(index) / Float(ramp)
            samples[index] *= gain
            samples[samples.count - 1 - index] *= gain
        }
    }

    private static func stitch(_ parts: [[Float]]) -> [Float] {
        parts.flatMap { $0 }
    }
}
