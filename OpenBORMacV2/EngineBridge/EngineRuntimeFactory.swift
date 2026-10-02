import Foundation

enum EngineRuntimeMode: String, CaseIterable, Identifiable {
    case mock
    case process
    case bridge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mock:
            return "Demo Runtime"
        case .process:
            return "Embedded Engine"
        case .bridge:
            return "Bridge Runtime"
        }
    }

    var detailText: String {
        switch self {
        case .mock:
            return "Runs inside the new AppKit + Metal host."
        case .process:
            return "Launches the embedded OpenBOR engine directly from V2, without opening the old launcher."
        case .bridge:
            return "Experimental mode: launches the rebuilt engine and keeps the new Metal host visible for IOSurface bridge testing."
        }
    }
}

enum EngineRuntimeFactory {
    static func makeSession(mode: EngineRuntimeMode) -> EngineRuntimeSession {
        switch mode {
        case .mock:
            let transport = InProcessFrameTransport()
            return EngineRuntimeSession(
                mode: mode,
                transport: transport,
                runtime: MockOpenBORRuntime(frameTransport: transport)
            )
        case .process:
            let transport = IOSurfaceFrameTransport()
            return EngineRuntimeSession(
                mode: mode,
                transport: transport,
                runtime: ProcessOpenBORRuntime(frameTransport: transport, executableVariant: .stableEmbedded)
            )
        case .bridge:
            let transport = IOSurfaceFrameTransport()
            return EngineRuntimeSession(
                mode: mode,
                transport: transport,
                runtime: ProcessOpenBORRuntime(frameTransport: transport, executableVariant: .bridgeExperimental)
            )
        }
    }
}
