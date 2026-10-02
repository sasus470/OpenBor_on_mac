import Foundation

struct IOSurfaceTransportPlan {
    let mode: FrameTransportMode = .ioSurface

    let producerRequirements: [String] = [
        "Create a shareable IOSurface-backed pixel buffer on the engine side",
        "Expose width, height, bytesPerRow and pixel format metadata",
        "Signal host when a new frame is ready"
    ]

    let consumerRequirements: [String] = [
        "Resolve the shared surface in the host process",
        "Wrap the surface in a Metal texture without copying pixels",
        "Present frames in the AppKit + Metal window"
    ]

    let whyThisMatters: String = "IOSurface is the cleanest macOS-native path to move frame ownership away from the legacy SDL window while keeping rendering fast."
}
