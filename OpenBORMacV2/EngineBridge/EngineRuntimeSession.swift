import Foundation

final class EngineRuntimeSession {
    let mode: EngineRuntimeMode
    let transport: EngineFrameTransport
    let runtime: EngineRuntime

    init(mode: EngineRuntimeMode,
         transport: EngineFrameTransport,
         runtime: EngineRuntime)
    {
        self.mode = mode
        self.transport = transport
        self.runtime = runtime
    }
}
