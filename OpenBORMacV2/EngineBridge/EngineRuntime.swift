import Foundation

protocol EngineRuntime: AnyObject {
    var state: EngineRuntimeState { get }
    var diagnostics: EngineRuntimeDiagnostics { get }
    var liveSaveStateSupport: EngineLiveSaveStateSupport { get }
    var onStateChange: ((EngineRuntimeState) -> Void)? { get set }
    var onFrame: ((EngineFramePacket) -> Void)? { get set }

    func prepare(configuration: EngineLaunchConfiguration) throws
    func start() throws
    func stop()
    func suspend()
    func resume()
    func setQuickMenuPaused(_ paused: Bool)
    func submitInput(_ snapshot: EngineInputSnapshot)
    func captureLiveSaveState() throws -> EngineLiveSaveStateArtifact
    func restoreLiveSaveState(from artifact: EngineLiveSaveStateArtifact) throws
}

extension EngineRuntime {
    func setQuickMenuPaused(_ paused: Bool) {}

    var liveSaveStateSupport: EngineLiveSaveStateSupport {
        .unsupported
    }

    func captureLiveSaveState() throws -> EngineLiveSaveStateArtifact {
        throw NSError(
            domain: "OpenBORMacV2.EngineRuntime",
            code: 100,
            userInfo: [NSLocalizedDescriptionKey: liveSaveStateSupport.summary]
        )
    }

    func restoreLiveSaveState(from artifact: EngineLiveSaveStateArtifact) throws {
        _ = artifact
        throw NSError(
            domain: "OpenBORMacV2.EngineRuntime",
            code: 101,
            userInfo: [NSLocalizedDescriptionKey: liveSaveStateSupport.summary]
        )
    }
}
