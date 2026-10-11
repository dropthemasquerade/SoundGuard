import CoreMotion
import Foundation

/// Device-motion feed. Updates are not guaranteed once iOS suspends the process.
final class HandheldMotionMonitor {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    var onSample: ((MotionSample) -> Void)?
    var onUnavailable: (() -> Void)?
    private var running = false

    init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
    }

    func start() {
        guard !running else { return }
        guard motion.isDeviceMotionAvailable else {
            onUnavailable?()
            return
        }
        running = true
        motion.deviceMotionUpdateInterval = 0.05
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, error in
            guard let self else { return }
            if error != nil || data == nil {
                self.onUnavailable?()
                return
            }
            guard let data else { return }
            let rotation = data.rotationRate
            let user = data.userAcceleration
            let gravity = data.gravity
            let sample = MotionSample(
                time: data.timestamp,
                rotationRate: (rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z).squareRoot(),
                userAcceleration: (user.x * user.x + user.y * user.y + user.z * user.z).squareRoot(),
                gravityX: gravity.x,
                gravityY: gravity.y,
                gravityZ: gravity.z
            )
            self.onSample?(sample)
        }
    }

    func stop() {
        guard running else { return }
        running = false
        motion.stopDeviceMotionUpdates()
    }
}
