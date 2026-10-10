import XCTest
@testable import SoundGuard

final class AlarmToneTests: XCTestCase {
    func testSynthesizedTonesAreDistinct() {
        let rendered = AlarmTone.allCases.filter { $0 != .classic }.map { AlarmTone.render($0) }
        XCTAssertEqual(rendered.count, 5)
        for samples in rendered {
            XCTAssertGreaterThan(samples.count, 1_600)
            XCTAssertTrue(samples.contains { abs($0) > 0.2 })
        }
        for index in 0..<rendered.count {
            for other in (index + 1)..<rendered.count {
                XCTAssertNotEqual(rendered[index], rendered[other])
            }
        }
        XCTAssertTrue(AlarmTone.render(.classic).isEmpty)
    }

    func testWaveFileStartsWithRiffHeader() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sg-alarm-tone-test.wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try WaveFile.write(samples: AlarmTone.render(.pulse), to: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertGreaterThan(data.count, 44)
    }

    func testTriggerClipSkipsShortAudio() {
        let id = UUID()
        defer { TriggerClipStore.delete(id) }
        TriggerClipStore.save(samples: [0.2, 0.2], id: id)
        XCTAssertFalse(TriggerClipStore.exists(id))
        TriggerClipStore.save(samples: Array(repeating: 0.25, count: 2_000), id: id)
        XCTAssertTrue(TriggerClipStore.exists(id))
        TriggerClipStore.delete(id)
        XCTAssertFalse(TriggerClipStore.exists(id))
    }
}
