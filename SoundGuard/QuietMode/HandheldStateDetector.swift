import Foundation

struct MotionSample: Equatable {
    var time: TimeInterval
    var rotationRate: Double
    var userAcceleration: Double
    var gravityX: Double
    var gravityY: Double
    var gravityZ: Double
}

/// Window thresholds for a first device pass. They are not a calibrated standard.
struct HandheldDetectorTuning: Equatable {
    var windowSeconds: TimeInterval = 0.45
    var minSamplesPerWindow: Int = 4
    /// Consecutive active windows before leaving unknown or placed.
    var handheldWindows: Int = 3
    /// Consecutive still windows before calling a handheld phone placed.
    var placedWindows: Int = 6
    var handheldRotation: Double = 0.8
    var handheldUserAccel: Double = 0.25
    var placedRotation: Double = 0.15
    var placedUserAccel: Double = 0.06
    var placedGravityStep: Double = 0.08
    /// No sample for this long means the estimate is unknown, so quiet mode must not keep silencing.
    var staleSeconds: TimeInterval = 2.5
}

final class HandheldStateDetector {
    private(set) var state: HandheldState = .unknown
    var tuning: HandheldDetectorTuning

    private var buffer: [MotionSample] = []
    private var windowStart: TimeInterval?
    private var lastSampleTime: TimeInterval?
    private var handheldStreak = 0
    private var placedStreak = 0
    private var unavailable = false

    init(tuning: HandheldDetectorTuning = HandheldDetectorTuning()) {
        self.tuning = tuning
    }

    func reset() {
        state = .unknown
        buffer.removeAll(keepingCapacity: true)
        windowStart = nil
        lastSampleTime = nil
        handheldStreak = 0
        placedStreak = 0
        unavailable = false
    }

    /// Sensor missing or a motion error. Fail open: do not stay quiet.
    func markUnavailable() -> HandheldState {
        unavailable = true
        state = .unknown
        handheldStreak = 0
        placedStreak = 0
        buffer.removeAll(keepingCapacity: true)
        windowStart = nil
        return state
    }

    func ingest(_ sample: MotionSample) -> HandheldState {
        unavailable = false
        lastSampleTime = sample.time
        if windowStart == nil {
            windowStart = sample.time
        }
        buffer.append(sample)
        guard let start = windowStart, sample.time - start >= tuning.windowSeconds else {
            return state
        }
        if buffer.count >= tuning.minSamplesPerWindow {
            classify(buffer)
        }
        windowStart = sample.time
        buffer = [sample]
        return state
    }

    /// `time` must use the same clock as the samples.
    func evaluate(at time: TimeInterval) -> HandheldState {
        guard !unavailable else {
            state = .unknown
            return state
        }
        if let lastSampleTime, time - lastSampleTime > tuning.staleSeconds {
            state = .unknown
            handheldStreak = 0
            placedStreak = 0
            buffer.removeAll(keepingCapacity: true)
            windowStart = nil
        }
        return state
    }

    private func classify(_ window: [MotionSample]) {
        let rotation = window.reduce(0.0) { $0 + $1.rotationRate } / Double(window.count)
        let accel = window.reduce(0.0) { $0 + $1.userAcceleration } / Double(window.count)
        let gravityStep = Self.gravityStep(window)
        let moving = rotation >= tuning.handheldRotation || accel >= tuning.handheldUserAccel
        let still = rotation <= tuning.placedRotation
            && accel <= tuning.placedUserAccel
            && gravityStep <= tuning.placedGravityStep

        if moving {
            placedStreak = 0
            handheldStreak += 1
            if state != .handheld, handheldStreak >= tuning.handheldWindows {
                state = .handheld
            }
        } else if still {
            handheldStreak = 0
            placedStreak += 1
            if state != .placed, placedStreak >= tuning.placedWindows {
                state = .placed
            }
        } else {
            handheldStreak = 0
            placedStreak = 0
        }
    }

    private static func gravityStep(_ window: [MotionSample]) -> Double {
        guard let first = window.first, let last = window.last else { return 0 }
        let dx = last.gravityX - first.gravityX
        let dy = last.gravityY - first.gravityY
        let dz = last.gravityZ - first.gravityZ
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}
