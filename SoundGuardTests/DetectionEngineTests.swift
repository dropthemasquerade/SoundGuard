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
}
