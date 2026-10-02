import Foundation

enum EngineRuntimeState: Equatable {
    case idle
    case preparing
    case running
    case stopping
    case failed(String)

    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .preparing:
            return "Preparing"
        case .running:
            return "Running"
        case .stopping:
            return "Stopping"
        case .failed:
            return "Failed"
        }
    }

    var accentName: String {
        switch self {
        case .idle:
            return "secondary"
        case .preparing:
            return "yellow"
        case .running:
            return "green"
        case .stopping:
            return "orange"
        case .failed:
            return "red"
        }
    }
}

struct EngineLaunchConfiguration: Equatable {
    var pakURL: URL?
    var paksDirectoryURL: URL?
    var savesDirectoryURL: URL?
    var logsDirectoryURL: URL?
    var screenshotsDirectoryURL: URL?
    var useMetalRenderer: Bool
    var shaderPresetName: String?
    var autoResumeSavedGame: Bool
    var liveStateBootURL: URL?
    var liveStateScriptURL: URL?
    var liveStateEntityVariablesURL: URL?
    var extraArguments: [String]

    static let `default` = EngineLaunchConfiguration(
        pakURL: nil,
        paksDirectoryURL: nil,
        savesDirectoryURL: nil,
        logsDirectoryURL: nil,
        screenshotsDirectoryURL: nil,
        useMetalRenderer: true,
        shaderPresetName: nil,
        autoResumeSavedGame: false,
        liveStateBootURL: nil,
        liveStateScriptURL: nil,
        liveStateEntityVariablesURL: nil,
        extraArguments: []
    )
}

struct EngineVideoFormat: Equatable {
    var width: Int
    var height: Int
    var bytesPerPixel: Int
    var pixelFormatName: String
}

struct EngineFramePacket: Equatable {
    var videoFormat: EngineVideoFormat
    var timestamp: TimeInterval
    var bytes: Data
}

struct EngineInputSnapshot: Equatable {
    var up: Bool = false
    var down: Bool = false
    var left: Bool = false
    var right: Bool = false
    var attack: Bool = false
    var attack2: Bool = false
    var attack3: Bool = false
    var attack4: Bool = false
    var jump: Bool = false
    var special: Bool = false
    var start: Bool = false
    var escape: Bool = false
}

struct EngineRuntimeDiagnostics: Equatable {
    var executableURL: URL?
    var lastLaunchArguments: [String]
    var rendererName: String
    var lastErrorMessage: String?

    static let empty = EngineRuntimeDiagnostics(
        executableURL: nil,
        lastLaunchArguments: [],
        rendererName: "Unknown",
        lastErrorMessage: nil
    )
}

enum EngineLiveSaveStateStrategy: Equatable {
    case unsupported
    case runtimeSerialization
    case liveProcessSnapshot
}

struct EngineLiveSaveStateSupport: Equatable {
    var strategy: EngineLiveSaveStateStrategy
    var canCapture: Bool
    var canRestore: Bool
    var summary: String

    static let unsupported = EngineLiveSaveStateSupport(
        strategy: .unsupported,
        canCapture: false,
        canRestore: false,
        summary: "Questo runtime non espone ancora una serializzazione completa dello stato live."
    )
}

struct EngineLiveSaveStateArtifact: Identifiable, Equatable {
    let id: String
    let pakIdentifier: String
    let pakURL: URL
    let title: String
    let createdAt: Date
    let manifestURL: URL
    let bootURL: URL?
    let scriptURL: URL?
    let entityVariablesURL: URL?
    let payloadDirectoryURL: URL
}
