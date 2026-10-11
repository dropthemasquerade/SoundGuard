import XCTest
@testable import SoundGuard

final class CaptureProcessorTests: XCTestCase {
    func testFullRangeWithoutEffectsMatchesTheSource() {
        let samples = ramp(count: 4_000)
        let duration = CaptureProcessor.duration(of: samples)
        let edit = CaptureEdit(start: 0, end: duration, denoise: false, enhance: false)
        let output = CaptureProcessor.process(samples, edit: edit)
        XCTAssertEqual(output, samples)
    }

    func testCropKeepsTheInteriorAndFadesTheCuts() {
        let samples = ramp(count: 16_000)
        let cropped = CaptureProcessor.crop(samples, start: 0.25, end: 0.75)
        XCTAssertEqual(cropped.count, 8_000)
        XCTAssertEqual(cropped[4_000], Float(8_000), accuracy: 0.001)
        XCTAssertLessThan(abs(cropped[0]), 50)
        XCTAssertLessThan(abs(cropped[cropped.count - 1]), 50)
    }

    func testLimitMessageRejectsShortAndLongSelections() {
        XCTAssertEqual(CaptureProcessor.limitMessage(start: 0, end: 0.2), "Keep at least 0.25 seconds.")
        XCTAssertEqual(CaptureProcessor.limitMessage(start: 0, end: 12.2), "Crop to 12 seconds or less.")
        XCTAssertNil(CaptureProcessor.limitMessage(start: 0.1, end: 1.1))
    }

    func testDenoiseLowersNoiseAroundATone() {
        let sampleRate = AudioDSP.sampleRate
        let prefix = Int(0.45 * sampleRate)
        let tone = Int(0.6 * sampleRate)
        var noise = LCG(state: 0xC0FFEE)
        var samples: [Float] = []
        samples.reserveCapacity(prefix + tone + prefix)
        for _ in 0..<prefix {
            samples.append(noise.next() * 0.08)
        }
        for index in 0..<tone {
            let clean = sin(2 * Double.pi * 1_000 * Double(index) / sampleRate)
            samples.append(Float(clean) * 0.45 + noise.next() * 0.08)
        }
        for _ in 0..<prefix {
            samples.append(noise.next() * 0.08)
        }

        let edit = CaptureEdit(
            start: 0,
            end: CaptureProcessor.duration(of: samples),
            denoise: true,
            enhance: false
        )
        let output = CaptureProcessor.process(samples, edit: edit)
        let margin = Int(0.12 * sampleRate)
        let noiseIn = rms(Array(samples[margin..<(prefix - margin)]))
        let noiseOut = rms(Array(output[margin..<(prefix - margin)]))
        XCTAssertLessThan(noiseOut, noiseIn * 0.45)

        let pure = (0..<tone).map { index in
            Float(sin(2 * Double.pi * 1_000 * Double(index) / sampleRate))
        }
        let toneIn = Array(samples[prefix..<(prefix + tone)])
        let toneOut = Array(output[prefix..<(prefix + tone)])
        let before = correlation(toneIn, pure)
        let after = correlation(toneOut, pure)
        XCTAssertGreaterThan(after, before)
        XCTAssertGreaterThan(after, 0.9)
    }

    func testRoundTripKeepsATone() {
        let samples = tone(frequency: 1_000, seconds: 0.8, amplitude: 0.4)
        let output = CaptureProcessor.roundTrip(samples)
        let ratio = rms(Array(middle(output))) / rms(Array(middle(samples)))
        XCTAssertGreaterThan(correlation(Array(middle(output)), Array(middle(samples))), 0.98)
        XCTAssertEqual(ratio, 1, accuracy: 0.05)
        XCTAssertLessThanOrEqual(output.map { abs($0) }.max() ?? 0, Float(0.5))
    }

    func testDenoiseKeepsACleanTone() {
        let samples = tone(frequency: 1_000, seconds: 0.8, amplitude: 0.4)
        let edit = CaptureEdit(start: 0, end: CaptureProcessor.duration(of: samples), denoise: true, enhance: false)
        let output = CaptureProcessor.process(samples, edit: edit)
        let original = Array(middle(samples))
        let cleaned = Array(middle(output))
        XCTAssertGreaterThan(correlation(cleaned, original), 0.92)
        let ratio = rms(cleaned) / rms(original)
        XCTAssertGreaterThan(ratio, 0.55)
        XCTAssertLessThan(ratio, 1.2)
        XCTAssertTrue(output.allSatisfy(\.isFinite))
    }

    func testEnhanceRaisesAQuietToneWithoutClipping() {
        let samples = tone(frequency: 1_000, seconds: 0.6, amplitude: 0.02)
        let edit = CaptureEdit(start: 0, end: CaptureProcessor.duration(of: samples), denoise: false, enhance: true)
        let output = CaptureProcessor.process(samples, edit: edit)
        XCTAssertGreaterThan(rms(Array(middle(output))), rms(Array(middle(samples))) * 3)
        XCTAssertLessThanOrEqual(output.map { abs($0) }.max() ?? 0, Float(0.98))
        XCTAssertTrue(output.allSatisfy(\.isFinite))
    }

    func testEnhanceCutsRumbleAndKeepsTheTone() {
        let sampleRate = AudioDSP.sampleRate
        let count = Int(0.7 * sampleRate)
        let mixed = (0..<count).map { index in
            let time = Double(index) / sampleRate
            let rumble = sin(2 * Double.pi * 40 * time)
            let beep = sin(2 * Double.pi * 1_500 * time)
            return Float((rumble + beep) * 0.3)
        }
        let edit = CaptureEdit(start: 0, end: CaptureProcessor.duration(of: mixed), denoise: false, enhance: true)
        let output = CaptureProcessor.process(mixed, edit: edit)
        let keptIn = Array(middle(mixed, fraction: 0.7))
        let keptOut = Array(middle(output, fraction: 0.7))
        let rumbleIn = componentEnergy(keptIn, hz: 40)
        let rumbleOut = componentEnergy(keptOut, hz: 40)
        let toneIn = componentEnergy(keptIn, hz: 1_500)
        let toneOut = componentEnergy(keptOut, hz: 1_500)
        XCTAssertLessThan(rumbleOut / rumbleIn, 0.35)
        XCTAssertGreaterThan(toneOut / toneIn, 0.75)
    }

    func testCombinedEditStaysFiniteAndInsideTheCrop() {
        var noise = LCG(state: 7)
        let samples = (0..<20_000).map { index -> Float in
            let tone = sin(2 * Double.pi * 880 * Double(index) / AudioDSP.sampleRate)
            return Float(tone) * 0.2 + noise.next() * 0.05
        }
        let edit = CaptureEdit(start: 0.2, end: 0.9, denoise: true, enhance: true)
        let output = CaptureProcessor.process(samples, edit: edit)
        let duration = CaptureProcessor.duration(of: output)
        XCTAssertEqual(duration, 0.7, accuracy: 0.002)
        XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= Float(1) })
    }

    private func ramp(count: Int) -> [Float] {
        (0..<count).map { Float($0) }
    }

    private func tone(frequency: Double, seconds: Double, amplitude: Float) -> [Float] {
        let sampleRate = AudioDSP.sampleRate
        let count = Int(seconds * sampleRate)
        return (0..<count).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate)) * amplitude
        }
    }

    private func middle(_ samples: [Float], fraction: Double = 0.5) -> ArraySlice<Float> {
        let keep = max(1, Int(Double(samples.count) * fraction))
        let start = max(0, (samples.count - keep) / 2)
        return samples[start..<min(samples.count, start + keep)]
    }

    private func rms(_ samples: [Float]) -> Float {
        PCMConvert.rms(samples)
    }

    private func correlation(_ lhs: [Float], _ rhs: [Float]) -> Float {
        let count = min(lhs.count, rhs.count)
        guard count > 8 else { return 0 }
        var dot: Float = 0
        var leftEnergy: Float = 0
        var rightEnergy: Float = 0
        for index in 0..<count {
            dot += lhs[index] * rhs[index]
            leftEnergy += lhs[index] * lhs[index]
            rightEnergy += rhs[index] * rhs[index]
        }
        let denom = sqrt(leftEnergy) * sqrt(rightEnergy)
        guard denom > 1e-8 else { return 0 }
        return dot / denom
    }

    private func componentEnergy(_ samples: [Float], hz: Double) -> Float {
        let sampleRate = AudioDSP.sampleRate
        var sine: Float = 0
        var cosine: Float = 0
        for (index, sample) in samples.enumerated() {
            let angle = 2 * Double.pi * hz * Double(index) / sampleRate
            sine += sample * Float(sin(angle))
            cosine += sample * Float(cos(angle))
        }
        return (sine * sine + cosine * cosine) / Float(max(samples.count, 1))
    }
}

private struct LCG {
    var state: UInt64

    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        let unit = Float((state >> 40) & 0xFFFF) / 65_535
        return unit * 2 - 1
    }
}
