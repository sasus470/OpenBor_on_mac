import Foundation
import IOSurface

enum FrameTransportMode: String, CaseIterable, Equatable {
    case callback
    case sharedMemory
    case ioSurface
}

struct FrameTransportDescriptor: Equatable {
    var mode: FrameTransportMode
    var name: String
    var details: [String: String]

    static let callback = FrameTransportDescriptor(
        mode: .callback,
        name: "Callback",
        details: [:]
    )
}

struct IOSurfaceFrameSnapshot {
    var surface: IOSurfaceRef
    var videoFormat: EngineVideoFormat
}

protocol EngineFrameTransport: AnyObject {
    var descriptor: FrameTransportDescriptor { get }

    func prepareProducerSide(videoFormat: EngineVideoFormat) throws
    func publish(_ frame: EngineFramePacket) throws
    func consumeLatestFrame() -> EngineFramePacket?
    func consumeIOSurfaceFrame() -> IOSurfaceFrameSnapshot?
    func reset()
}
