import Foundation

/// Microphone audio captured at the moment an alarm latches, keyed by event id.
enum TriggerClipStore {
    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Triggers", isDirectory: true)
    }

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).wav")
    }

    static func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    static func save(samples: [Float], id: UUID) {
        guard samples.count >= 1_600 else { return }
        try? WaveFile.write(samples: samples, to: url(for: id))
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
