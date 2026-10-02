import Foundation

final class InProcessFrameTransport: EngineFrameTransport {
    private let lock = NSLock()
    private var latestFrame: EngineFramePacket?
    private(set) var descriptor: FrameTransportDescriptor = .callback

    func prepareProducerSide(videoFormat: EngineVideoFormat) throws {
        lock.lock()
        defer { lock.unlock() }
        latestFrame = nil
        descriptor = FrameTransportDescriptor(
            mode: .callback,
            name: "In-Process Frame Buffer",
            details: [
                "pixelFormat": videoFormat.pixelFormatName,
                "width": "\(videoFormat.width)",
                "height": "\(videoFormat.height)"
            ]
        )
    }

    func publish(_ frame: EngineFramePacket) throws {
        lock.lock()
        latestFrame = frame
        lock.unlock()
    }

    func consumeLatestFrame() -> EngineFramePacket? {
        lock.lock()
        defer { lock.unlock() }
        return latestFrame
    }

    func consumeIOSurfaceFrame() -> IOSurfaceFrameSnapshot? {
        nil
    }

    func reset() {
        lock.lock()
        latestFrame = nil
        descriptor = .callback
        lock.unlock()
    }
}
