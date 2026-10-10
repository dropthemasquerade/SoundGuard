import XCTest
@testable import SoundGuard

final class SoundMatcherTests: XCTestCase {
    func testIdenticalVectorsHaveCosineOne() {
        let vector: [Float] = [0.2, 0.4, 0.6, 0.1, -0.3]
        XCTAssertEqual(MFCC.cosine(vector, vector), 1, accuracy: 0.0001)
    }

    func testSameSineMatchesBetterThanDifferentSine() {
        let extractor = AudioFeatureExtractor()
        let a = sine(freq: 1000, seconds: 0.6)
        let b = sine(freq: 1000, seconds: 0.6, phase: 0.4)
        let c = sine(freq: 3200, seconds: 0.6)
        let templateA = extractor.extractTemplate(from: a, profile: .beep)
        let templateB = extractor.extractTemplate(from: b, profile: .beep)
        let templateC = extractor.extractTemplate(from: c, profile: .beep)
        let same = SoundMatcher.similarity(between: templateA, and: templateB)
        let different = SoundMatcher.similarity(between: templateA, and: templateC)
        XCTAssertGreaterThan(same, different)
        XCTAssertGreaterThan(same, 0.55)
    }

    func testLiveScoringTracksMatchingTone() {
        let extractor = AudioFeatureExtractor()
        let reference = sine(freq: 880, seconds: 0.8)
        let template = extractor.extractTemplate(from: reference, profile: .beep)
        let matcher = SoundMatcher()
        matcher.load(template)

        extractor.reset()
        let liveMatch = extractor.append(sine(freq: 880, seconds: 0.8), streamTime: 0)
        var peakMatch: Float = 0
        for frame in liveMatch {
            peakMatch = max(peakMatch, matcher.score(frame: frame).similarity)
        }

        matcher.resetBuffer()
        extractor.reset()
        let liveOther = extractor.append(sine(freq: 2400, seconds: 0.8), streamTime: 0)
        var peakOther: Float = 0
        for frame in liveOther {
            peakOther = max(peakOther, matcher.score(frame: frame).similarity)
        }

        XCTAssertGreaterThan(peakMatch, peakOther)
    }

    func testAdjacentPianoNotesStayApart() {
        let extractor = AudioFeatureExtractor()
        let notes = [60, 61, 62, 64, 67, 72]
        let templates = notes.map { midi in
            extractor.extractTemplate(from: piano(midi: midi, seconds: 1.0), profile: .beep)
        }
        for template in templates {
            XCTAssertTrue(template.pitched, "expected a stable pitch")
            XCTAssertGreaterThan(template.pitchHz, 50)
        }
        for (index, template) in templates.enumerated() {
            let same = SoundMatcher.similarity(
                between: template,
                and: extractor.extractTemplate(from: piano(midi: notes[index], seconds: 1.0, brightness: 0.55), profile: .beep)
            )
            XCTAssertGreaterThan(same, 0.8, "midi \(notes[index]) did not match itself: \(same)")
            if index + 1 < templates.count {
                let other = SoundMatcher.similarity(between: template, and: templates[index + 1])
                XCTAssertLessThan(other, 0.55, "midi \(notes[index]) vs \(notes[index + 1]) = \(other)")
            }
        }
        let c4 = templates[0]
        let c5 = templates[5]
        XCTAssertLessThan(SoundMatcher.similarity(between: c4, and: c5), 0.55)
    }

    func testLivePianoNoteRejectsItsNeighbor() {
        let extractor = AudioFeatureExtractor()
        let template = extractor.extractTemplate(from: piano(midi: 60, seconds: 1.0), profile: .beep)
        let matcher = SoundMatcher()
        matcher.load(template)

        func peak(midi: Int) -> Float {
            matcher.resetBuffer()
            extractor.reset()
            var best: Float = 0
            for frame in extractor.append(piano(midi: midi, seconds: 1.0), streamTime: 0) {
                best = max(best, matcher.score(frame: frame).similarity)
            }
            return best
        }

        let same = peak(midi: 60)
        let neighbor = peak(midi: 61)
        let octave = peak(midi: 72)
        XCTAssertGreaterThan(same, 0.8)
        XCTAssertLessThan(neighbor, 0.55)
        XCTAssertLessThan(octave, 0.55)
        XCTAssertGreaterThan(same, neighbor)
    }

    private func piano(midi: Int, seconds: Double, brightness: Double = 0.35) -> [Float] {
        let frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        let sampleRate = AudioDSP.sampleRate
        let count = Int(seconds * sampleRate)
        let inharmonicity = 0.0002
        return (0..<count).map { index in
            let time = Double(index) / sampleRate
            let envelope = exp(-time * 1.6) * (1 - exp(-time * 120))
            var sample = 0.0
            for harmonic in 1...10 {
                let partial = Double(harmonic) * frequency * sqrt(1 + inharmonicity * Double(harmonic * harmonic))
                if partial >= sampleRate / 2 { break }
                sample += exp(-Double(harmonic) * brightness) * sin(2 * Double.pi * partial * time)
            }
            return Float(sample * envelope * 0.2)
        }
    }

    private func sine(freq: Double, seconds: Double, phase: Double = 0) -> [Float] {
        let sr = AudioDSP.sampleRate
        let n = Int(seconds * sr)
        return (0..<n).map { i in
            Float(sin(2 * Double.pi * freq * Double(i) / sr + phase))
        }
    }
}
