import Foundation

enum WaveFile {
    static func write(samples: [Float], to url: URL, sampleRate: Int = 16_000) throws {
        let frames = samples.count
        var pcm = Data(count: frames * MemoryLayout<Int16>.size)
        pcm.withUnsafeMutableBytes { raw in
            let dest = raw.bindMemory(to: Int16.self)
            for index in 0..<frames {
                let clamped = max(-1, min(1, samples[index]))
                dest[index] = Int16(clamped * 32_767)
            }
        }
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: string.utf8) }
        func appendU32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func appendU16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let dataSize = UInt32(pcm.count)
        append("RIFF")
        appendU32(36 + dataSize)
        append("WAVE")
        append("fmt ")
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate) * 2)
        appendU16(2)
        appendU16(16)
        append("data")
        appendU32(dataSize)
        data.append(pcm)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
