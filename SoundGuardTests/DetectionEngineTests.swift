import XCTest
@testable import SoundGuard

final class DetectionEngineTests: XCTestCase {
    func testRequiresConsecutiveHitsAndEnergy() {
        let engine = DetectionEngine(parameters: DetectionParameters(
            similarityThreshold: 0.8,
            consecutiveHits: 3,
            energyRatio: 2,
            minEnergy: 0.01,
            cooldown: 0.5,
            noiseAdapt: 0.05
        ))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.9, energy: 0.02, timestamp: 1)))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.9, energy: 0.02, timestamp: 1.1)))
        let result = engine.process(MatchScore(similarity: 0.92, energy: 0.02, timestamp: 1.2))
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.confidence ?? 0, 0.92, accuracy: 0.001)
    }

    func testLatchesUntilReset() {
        let engine = DetectionEngine(parameters: DetectionParameters(
            similarityThreshold: 0.7,
            consecutiveHits: 2,
            energyRatio: 1,
            minEnergy: 0.001,
            cooldown: 0.1,
            noiseAdapt: 0.05
        ))
        _ = engine.process(MatchScore(similarity: 0.9, energy: 0.2, timestamp: 1))
        XCTAssertNotNil(engine.process(MatchScore(similarity: 0.9, energy: 0.2, timestamp: 1.05)))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.99, energy: 0.4, timestamp: 2)))
        engine.resetLatch()
        _ = engine.process(MatchScore(similarity: 0.9, energy: 0.2, timestamp: 4))
        XCTAssertNotNil(engine.process(MatchScore(similarity: 0.9, energy: 0.2, timestamp: 4.05)))
    }

    func testLowEnergyDoesNotFire() {
        let engine = DetectionEngine(parameters: DetectionParameters(
            similarityThreshold: 0.5,
            consecutiveHits: 2,
            energyRatio: 8,
            minEnergy: 0.05,
            cooldown: 0,
            noiseAdapt: 0.2
        ))
        for i in 0..<6 {
            XCTAssertNil(engine.process(MatchScore(similarity: 0.99, energy: 0.0001, timestamp: Double(i))))
        }
    }

    func testStrongMatchFiresWithoutTheFullStreakOrNoiseRatio() {
        let engine = DetectionEngine(parameters: DetectionParameters(
            similarityThreshold: 0.78,
            consecutiveHits: 6,
            energyRatio: 4,
            minEnergy: 0.001,
            cooldown: 0,
            noiseAdapt: 0.5
        ))
        for index in 0..<8 {
            XCTAssertNil(engine.process(MatchScore(similarity: 0.1, energy: 0.2, timestamp: Double(index) * 0.01)))
        }
        XCTAssertNil(engine.process(MatchScore(similarity: 0.99, energy: 0.01, timestamp: 1)))
        let result = engine.process(MatchScore(similarity: 0.99, energy: 0.01, timestamp: 1.01))
        XCTAssertEqual(result?.confidence ?? 0, 0.99, accuracy: 0.001)
    }

    func testStrongMatchSurvivesOneWeakFrame() {
        let engine = DetectionEngine(parameters: DetectionParameters(
            similarityThreshold: 0.8,
            consecutiveHits: 4,
            energyRatio: 1,
            minEnergy: 0.001,
            cooldown: 0,
            noiseAdapt: 0.05
        ))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.99, energy: 0.05, timestamp: 1)))
        XCTAssertNil(engine.process(MatchScore(similarity: 0, energy: 0.05, timestamp: 1.01)))
        XCTAssertNotNil(engine.process(MatchScore(similarity: 0.97, energy: 0.05, timestamp: 1.02)))
    }

    func testBorderlineMatchStillNeedsEveryHit() {
        let engine = DetectionEngine(parameters: DetectionParameters(
            similarityThreshold: 0.78,
            consecutiveHits: 4,
            energyRatio: 1,
            minEnergy: 0.001,
            cooldown: 0,
            noiseAdapt: 0.05
        ))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.85, energy: 0.05, timestamp: 1)))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.85, energy: 0.05, timestamp: 1.01)))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.85, energy: 0.05, timestamp: 1.02)))
        XCTAssertNotNil(engine.process(MatchScore(similarity: 0.85, energy: 0.05, timestamp: 1.03)))
    }

    func testHitCounterResetsOnMiss() {
        let engine = DetectionEngine(parameters: DetectionParameters(
            similarityThreshold: 0.8,
            consecutiveHits: 3,
            energyRatio: 1,
            minEnergy: 0.01,
            cooldown: 0,
            noiseAdapt: 0.05
        ))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.9, energy: 0.2, timestamp: 1)))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.2, energy: 0.2, timestamp: 1.1)))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.9, energy: 0.2, timestamp: 1.2)))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.9, energy: 0.2, timestamp: 1.3)))
        XCTAssertNotNil(engine.process(MatchScore(similarity: 0.9, energy: 0.2, timestamp: 1.4)))
    }

    func testSingleModeIgnoresATwoFrameSpike() {
        let engine = singleEngine()
        XCTAssertNil(engine.process(MatchScore(similarity: 0.99, energy: 0.05, timestamp: 1)))
        XCTAssertNil(engine.process(MatchScore(similarity: 0.99, energy: 0.05, timestamp: 1.01)))
    }

    func testSingleModeFiresOnceAfterAQuietRoom() {
        let engine = singleEngine()
        XCTAssertNil(feed(engine, similarity: 0.1, from: 0, to: 4.0, step: 0.05))
        XCTAssertNil(feed(engine, similarity: 0.96, from: 4.05, to: 4.40, step: 0.02))
        XCTAssertNil(feed(engine, similarity: 0.1, from: 4.42, to: 4.90, step: 0.02))
        let fired = feed(engine, similarity: 0.1, from: 4.92, to: 5.40, step: 0.02)
        XCTAssertNotNil(fired)
        XCTAssertNil(feed(engine, similarity: 0.96, from: 6.0, to: 6.4, step: 0.02))
    }

    func testSingleModeIgnoresRepeatingSimilarSounds() {
        let engine = singleEngine()
        var fired: DetectionResult?
        for index in 0..<8 {
            let start = 0.3 + Double(index) * 0.9
            fired = fired ?? feed(engine, similarity: 0.96, from: start, to: start + 0.28, step: 0.02)
            fired = fired ?? feed(engine, similarity: 0.1, from: start + 0.30, to: start + 0.86, step: 0.02)
        }
        XCTAssertNil(fired)
    }

    func testSingleModeIgnoresASteadyMatch() {
        let engine = singleEngine()
        XCTAssertNil(feed(engine, similarity: 0.1, from: 0, to: 4.0, step: 0.05))
        XCTAssertNil(feed(engine, similarity: 0.97, from: 4.05, to: 7.5, step: 0.02))
        XCTAssertNil(feed(engine, similarity: 0.1, from: 7.52, to: 9.0, step: 0.05))
    }

    func testSingleModeIgnoresAWeakMatch() {
        let engine = singleEngine()
        XCTAssertNil(feed(engine, similarity: 0.1, from: 0, to: 4.0, step: 0.05))
        XCTAssertNil(feed(engine, similarity: 0.80, from: 4.05, to: 4.50, step: 0.02))
        XCTAssertNil(feed(engine, similarity: 0.1, from: 4.52, to: 8.0, step: 0.05))
    }

    func testHarmonicModeFiresOnTheCollectedStack() {
        let engine = harmonicEngine()
        let tone = harmonicTone
        XCTAssertNil(feed(engine, similarity: 0.2, harmonicity: 0.05, partials: noisePartials, from: 0, to: 4.0, step: 0.05))
        XCTAssertNil(feed(engine, similarity: 0.2, harmonicity: 0.62, partials: tone, from: 4.05, to: 4.40, step: 0.02))
        let fired = feed(engine, similarity: 0.2, harmonicity: 0.05, partials: noisePartials, from: 4.42, to: 5.4, step: 0.02)
        XCTAssertNotNil(fired)
    }

    func testHarmonicModeIgnoresTheWrongStackAndNoise() {
        let engine = harmonicEngine()
        XCTAssertNil(feed(engine, similarity: 0.99, harmonicity: 0.08, partials: harmonicTone, from: 0, to: 6.0, step: 0.05))
        engine.resetLatch()
        XCTAssertNil(feed(engine, similarity: 0.2, harmonicity: 0.05, partials: noisePartials, from: 0, to: 4.0, step: 0.05))
        XCTAssertNil(feed(engine, similarity: 0.2, harmonicity: 0.7, partials: wrongPartials, from: 4.05, to: 4.5, step: 0.02))
        XCTAssertNil(feed(engine, similarity: 0.2, harmonicity: 0.05, partials: noisePartials, from: 4.52, to: 8.0, step: 0.05))
    }

    private func singleEngine() -> DetectionEngine {
        let engine = DetectionEngine(parameters: DetectionParameters(
            similarityThreshold: 0.78,
            consecutiveHits: 4,
            energyRatio: 3,
            minEnergy: 0.001,
            cooldown: 0,
            noiseAdapt: 0.05
        ))
        engine.mode = .single
        engine.referenceDuration = 0.35
        return engine
    }

    private func harmonicEngine() -> DetectionEngine {
        let engine = singleEngine()
        engine.mode = .harmonic
        engine.templatePartials = harmonicTone
        engine.templateHarmonicity = 0.55
        return engine
    }

    private var harmonicTone: [Float] { [0.62, 0.24, 0.10, 0.04, 0, 0, 0, 0] }
    private var wrongPartials: [Float] { [0.05, 0.08, 0.12, 0.45, 0.2, 0.1, 0, 0] }
    private var noisePartials: [Float] { [Float](repeating: 0.125, count: 8) }

    private func feed(
        _ engine: DetectionEngine,
        similarity: Float,
        energy: Float = 0.05,
        harmonicity: Float = 0,
        partials: [Float] = [],
        from: Double,
        to: Double,
        step: Double
    ) -> DetectionResult? {
        var time = from
        var fired: DetectionResult?
        while time <= to + 0.0001 {
            let result = engine.process(MatchScore(
                similarity: similarity,
                energy: energy,
                timestamp: time,
                harmonicity: harmonicity,
                partials: partials
            ))
            if fired == nil { fired = result }
            time += step
        }
        return fired
    }
}
