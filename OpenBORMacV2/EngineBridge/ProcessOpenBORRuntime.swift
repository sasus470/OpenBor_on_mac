import Foundation
import QuartzCore
import Darwin

enum ProcessExecutableVariant {
    case stableEmbedded
    case bridgeExperimental

    var candidateExecutableURLs: [URL] {
        let bundleExecutable = Bundle.main.resourceURL?
            .appendingPathComponent("Engine/OpenBOR.app/Contents/MacOS/OpenBOR-bin", isDirectory: false)

        switch self {
        case .stableEmbedded:
            return [
                bundleExecutable,
                URL(fileURLWithPath: "/Users/salvatorecuccoro/Documents/New project/build/final/OpenBOR Frontend Launcher.app/Contents/Resources/Engine/OpenBOR.app/Contents/MacOS/OpenBOR-bin"),
                URL(fileURLWithPath: "/Users/salvatorecuccoro/Documents/New project/build/frontend/OpenBOR Frontend Launcher.app/Contents/Resources/Engine/OpenBOR.app/Contents/MacOS/OpenBOR-bin"),
                URL(fileURLWithPath: "/Users/salvatorecuccoro/Applications/OpenBOR Frontend Launcher.app/Contents/Resources/Engine/OpenBOR.app/Contents/MacOS/OpenBOR-bin")
            ].compactMap { $0 }
        case .bridgeExperimental:
            return [
                bundleExecutable,
                URL(fileURLWithPath: "/Users/salvatorecuccoro/Documents/New project/build/final/OpenBOR Frontend Launcher.app/Contents/Resources/Engine/OpenBOR.app/Contents/MacOS/OpenBOR-bin"),
                URL(fileURLWithPath: "/Users/salvatorecuccoro/Documents/New project/build/frontend/OpenBOR Frontend Launcher.app/Contents/Resources/Engine/OpenBOR.app/Contents/MacOS/OpenBOR-bin"),
                URL(fileURLWithPath: "/Users/salvatorecuccoro/Applications/OpenBOR Frontend Launcher.app/Contents/Resources/Engine/OpenBOR.app/Contents/MacOS/OpenBOR-bin")
            ].compactMap { $0 }
        }
    }

    var rendererDisplayName: String {
        switch self {
        case .stableEmbedded:
            return "Metal (embedded engine)"
        case .bridgeExperimental:
            return "Metal (bridge runtime)"
        }
    }

    var enableFallbackFrames: Bool {
        switch self {
        case .stableEmbedded:
            return false
        case .bridgeExperimental:
            return false
        }
    }
}

final class ProcessOpenBORRuntime: EngineRuntime {
    private static let bootstrapVideoFormat = EngineVideoFormat(
        width: 2048,
        height: 2048,
        bytesPerPixel: 4,
        pixelFormatName: "BGRA8"
    )

    private let frameTransport: EngineFrameTransport
    private let executableVariant: ProcessExecutableVariant
    private let fallbackFrameSource = DemoFrameSource()
    private(set) var state: EngineRuntimeState = .idle {
        didSet { onStateChange?(state) }
    }

    private(set) var diagnostics: EngineRuntimeDiagnostics = .empty
    var onStateChange: ((EngineRuntimeState) -> Void)?
    var onFrame: ((EngineFramePacket) -> Void)?

    private var configuration: EngineLaunchConfiguration = .default
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var launchExecutableURL: URL?
    private var fallbackTimer: Timer?
    private var fallbackTimebase: TimeInterval = 0
    private let fileManager = FileManager.default
    private var lastSerializedInput: String?
    private var processRuntimeLogURL: URL? = V2LaunchConfigurationFactory.processRuntimeLogURL()
    private var isSuspended = false

    var liveSaveStateSupport: EngineLiveSaveStateSupport {
        EngineLiveSaveStateSupport(
            strategy: .runtimeSerialization,
            canCapture: state == .running,
            canRestore: false,
            summary: "Questa build puo catturare un manifest diagnostico dello stato live del motore, ma non ripristina ancora un savestate completo."
        )
    }

    init(frameTransport: EngineFrameTransport = InProcessFrameTransport(),
         executableVariant: ProcessExecutableVariant = .stableEmbedded) {
        self.frameTransport = frameTransport
        self.executableVariant = executableVariant
    }

    func prepare(configuration: EngineLaunchConfiguration) throws {
        self.configuration = configuration
        state = .preparing
        frameTransport.reset()

        let executableURL = try resolveExecutableURL()
        let arguments = OpenBORLaunchArgumentBuilder.makeArguments(from: configuration)

        launchExecutableURL = executableURL
        diagnostics = EngineRuntimeDiagnostics(
            executableURL: executableURL,
            lastLaunchArguments: arguments,
            rendererName: configuration.useMetalRenderer ? executableVariant.rendererDisplayName : "OpenGL (host runtime)",
            lastErrorMessage: nil
        )
        if let processRuntimeLogURL {
            try? fileManager.removeItem(at: processRuntimeLogURL)
        }
        clearLiveInputState()
        try frameTransport.prepareProducerSide(videoFormat: Self.bootstrapVideoFormat)
    }

    func start() throws {
        guard state == .preparing || state == .idle else { return }
        terminateLingeringChildProcesses()
        setQuickMenuPaused(false)

        let executableURL = try launchExecutableURL ?? resolveExecutableURL()
        let arguments = OpenBORLaunchArgumentBuilder.makeArguments(from: configuration)

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = makeEnvironment()
        process.currentDirectoryURL = configuration.logsDirectoryURL
            ?? configuration.savesDirectoryURL
            ?? V2LaunchConfigurationFactory.appSupportRootURL()

        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleTermination(process)
            }
        }

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        attachReadabilityHandlers(stdoutPipe: stdoutPipe, stderrPipe: stderrPipe)

        do {
            try process.run()
            state = .running
            if executableVariant.enableFallbackFrames {
                startFallbackFrameFeed()
            }
        } catch {
            diagnostics.lastErrorMessage = error.localizedDescription
            state = .failed("Failed to launch OpenBOR process: \(error.localizedDescription)")
            throw error
        }
    }

    func stop() {
        state = .stopping
        isSuspended = false
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let process {
            process.terminationHandler = nil

            if process.isRunning {
                process.terminate()

                for _ in 0..<40 where process.isRunning {
                    usleep(50_000)
                }

                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)

                    for _ in 0..<20 where process.isRunning {
                        usleep(50_000)
                    }
                }
            }
        }

        terminateLingeringChildProcesses()

        stopFallbackFrameFeed()
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        frameTransport.reset()
        lastSerializedInput = nil
        state = .idle
    }

    func suspend() {
        guard let process, process.isRunning, !isSuspended else { return }
        clearLiveInputState()
        kill(process.processIdentifier, SIGUSR1)
        stopFallbackFrameFeed()
        isSuspended = true
    }

    func resume() {
        guard let process, isSuspended else { return }
        kill(process.processIdentifier, SIGUSR2)
        if executableVariant.enableFallbackFrames {
            startFallbackFrameFeed()
        }
        isSuspended = false
    }

    func setQuickMenuPaused(_ paused: Bool) {
        try? (paused ? "1" : "0").write(
            to: V2LaunchConfigurationFactory.quickMenuPauseURL(), atomically: true, encoding: .utf8
        )
    }

    func submitInput(_ snapshot: EngineInputSnapshot) {
        guard executableVariant == .bridgeExperimental || executableVariant == .stableEmbedded else {
            return
        }
        let inputURL = V2LaunchConfigurationFactory.bridgeInputURL()

        let serialized = [
            snapshot.up,
            snapshot.down,
            snapshot.left,
            snapshot.right,
            snapshot.attack,
            snapshot.attack2,
            snapshot.attack3,
            snapshot.attack4,
            snapshot.jump,
            snapshot.special,
            snapshot.start,
            snapshot.escape
        ]
        .map { $0 ? "1" : "0" }
        .joined(separator: " ")

        guard serialized != lastSerializedInput else { return }
        lastSerializedInput = serialized
        try? serialized.write(to: inputURL, atomically: false, encoding: .utf8)
    }

    func captureLiveSaveState() throws -> EngineLiveSaveStateArtifact {
        guard state == .running, !isSuspended else {
            throw NSError(
                domain: "OpenBORMacV2.ProcessOpenBORRuntime",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: "La cattura live richiede una sessione in esecuzione e visibile, non sospesa."]
            )
        }

        guard let pakURL = configuration.pakURL else {
            throw NSError(
                domain: "OpenBORMacV2.ProcessOpenBORRuntime",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "Non c'e un gioco attivo da cui catturare lo stato live."]
            )
        }

        let requestURL = V2LaunchConfigurationFactory.liveStateRequestURL()
        let manifestURL = V2LaunchConfigurationFactory.liveStateManifestURL()
        try? fileManager.removeItem(at: requestURL)
        try? fileManager.removeItem(at: manifestURL)
        try? fileManager.removeItem(at: URL(fileURLWithPath: manifestURL.path + ".boot"))
        try? fileManager.removeItem(at: URL(fileURLWithPath: manifestURL.path + ".script"))
        try? fileManager.removeItem(at: URL(fileURLWithPath: manifestURL.path + ".entityvars"))

        let requestToken = ISO8601DateFormatter().string(from: Date())
        try requestToken.write(to: requestURL, atomically: true, encoding: .utf8)

        let timeout = Date().addingTimeInterval(2.0)
        while Date() < timeout {
            if fileManager.fileExists(atPath: manifestURL.path) {
                let artifactID = "live-\(timestampToken())"
                let stagingDirectory = V2LaunchConfigurationFactory.liveSaveStatesRootURL()
                    .appendingPathComponent("_staging", isDirectory: true)
                    .appendingPathComponent(artifactID, isDirectory: true)
                try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

                let stagedManifestURL = stagingDirectory.appendingPathComponent("manifest.json", isDirectory: false)
                if fileManager.fileExists(atPath: stagedManifestURL.path) {
                    try fileManager.removeItem(at: stagedManifestURL)
                }
                try fileManager.copyItem(at: manifestURL, to: stagedManifestURL)

                let bootURL = URL(fileURLWithPath: manifestURL.path + ".boot")
                let stagedBootURL = stagingDirectory.appendingPathComponent("manifest.json.boot", isDirectory: false)
                if fileManager.fileExists(atPath: bootURL.path) {
                    if fileManager.fileExists(atPath: stagedBootURL.path) {
                        try fileManager.removeItem(at: stagedBootURL)
                    }
                    try fileManager.copyItem(at: bootURL, to: stagedBootURL)
                }
                let scriptURL = URL(fileURLWithPath: manifestURL.path + ".script")
                let stagedScriptURL = stagingDirectory.appendingPathComponent("manifest.json.script", isDirectory: false)
                if fileManager.fileExists(atPath: scriptURL.path) {
                    if fileManager.fileExists(atPath: stagedScriptURL.path) {
                        try fileManager.removeItem(at: stagedScriptURL)
                    }
                    try fileManager.copyItem(at: scriptURL, to: stagedScriptURL)
                }
                let entityVariablesURL = URL(fileURLWithPath: manifestURL.path + ".entityvars")
                let stagedEntityVariablesURL = stagingDirectory.appendingPathComponent("manifest.json.entityvars", isDirectory: false)
                if fileManager.fileExists(atPath: entityVariablesURL.path) {
                    if fileManager.fileExists(atPath: stagedEntityVariablesURL.path) {
                        try fileManager.removeItem(at: stagedEntityVariablesURL)
                    }
                    try fileManager.copyItem(at: entityVariablesURL, to: stagedEntityVariablesURL)
                }

                return EngineLiveSaveStateArtifact(
                    id: artifactID,
                    pakIdentifier: pakIdentifier(for: pakURL),
                    pakURL: pakURL,
                    title: "Cattura Live \(displayTimestamp())",
                    createdAt: Date(),
                    manifestURL: stagedManifestURL,
                    bootURL: fileManager.fileExists(atPath: stagedBootURL.path) ? stagedBootURL : nil,
                    scriptURL: fileManager.fileExists(atPath: stagedScriptURL.path) ? stagedScriptURL : nil,
                    entityVariablesURL: fileManager.fileExists(atPath: stagedEntityVariablesURL.path) ? stagedEntityVariablesURL : nil,
                    payloadDirectoryURL: stagingDirectory
                )
            }
            usleep(50_000)
        }

        throw NSError(
            domain: "OpenBORMacV2.ProcessOpenBORRuntime",
            code: 22,
            userInfo: [NSLocalizedDescriptionKey: "Il motore non ha restituito in tempo il manifest dello stato live."]
        )
    }

    private func clearLiveInputState() {
        let inputURL = V2LaunchConfigurationFactory.bridgeInputURL()
        let serialized = Array(repeating: "0", count: 12).joined(separator: " ")
        lastSerializedInput = serialized
        try? serialized.write(to: inputURL, atomically: false, encoding: .utf8)
    }

    private func resolveExecutableURL() throws -> URL {
        let fileManager = FileManager.default
        if let match = executableVariant.candidateExecutableURLs.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return match
        }

        throw NSError(
            domain: "OpenBORMacV2.ProcessOpenBORRuntime",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to find an embedded OpenBOR engine executable for V2."]
        )
    }

    private func pakIdentifier(for pakURL: URL) -> String {
        let baseName = pakURL.deletingPathExtension().lastPathComponent
        let scalars = baseName.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let compact = String(scalars).replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
        return compact.trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
    }

    private func timestampToken() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func displayTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private func makeEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["OPENBOR_V2_QUICK_MENU_PAUSE_PATH"] = V2LaunchConfigurationFactory.quickMenuPauseURL().path

        if let paksDirectoryURL = configuration.paksDirectoryURL {
            environment["OPENBOR_PAKS_DIR"] = paksDirectoryURL.path
        }

        if let savesDirectoryURL = configuration.savesDirectoryURL {
            environment["OPENBOR_SAVES_DIR"] = savesDirectoryURL.path
        }

        if let logsDirectoryURL = configuration.logsDirectoryURL {
            environment["OPENBOR_LOGS_DIR"] = logsDirectoryURL.path
        }

        if let screenshotsDirectoryURL = configuration.screenshotsDirectoryURL {
            environment["OPENBOR_SCREENSHOTS_DIR"] = screenshotsDirectoryURL.path
        }

        environment["OPENBOR_USE_METAL"] = configuration.useMetalRenderer ? "1" : "0"
        environment["OPENBOR_V2_AUTORESUME"] = configuration.autoResumeSavedGame ? "1" : "0"
        if let liveStateBootURL = configuration.liveStateBootURL {
            environment["OPENBOR_V2_LIVESTATE_BOOT_PATH"] = liveStateBootURL.path
            environment["OPENBOR_V2_AUTORESUME"] = "1"
        }
        if let liveStateScriptURL = configuration.liveStateScriptURL {
            environment["OPENBOR_V2_LIVESTATE_SCRIPT_PATH"] = liveStateScriptURL.path
        }
        if let liveStateEntityVariablesURL = configuration.liveStateEntityVariablesURL {
            environment["OPENBOR_V2_LIVESTATE_ENTITYVARS_PATH"] = liveStateEntityVariablesURL.path
        }

        if let shaderPresetName = configuration.shaderPresetName, !shaderPresetName.isEmpty {
            environment["OPENBOR_METAL_SHADER"] = shaderPresetName
        }

        if let surfaceTransport = frameTransport as? IOSurfaceFrameTransport {
            let surfaceID = surfaceTransport.currentSurfaceID()
            if surfaceID != 0 {
                environment["OPENBOR_V2_IOSURFACE_ID"] = "\(surfaceID)"
            }
            if let frameInfoPath = surfaceTransport.frameInfoPath() {
                environment["OPENBOR_V2_FRAMEINFO_PATH"] = frameInfoPath
            }
            if let frameDataPath = surfaceTransport.frameDataPath() {
                try? fileManager.removeItem(atPath: frameDataPath)
                environment["OPENBOR_V2_FRAME_PATH"] = frameDataPath
            }
            let bridgeLogURL = V2LaunchConfigurationFactory.bridgeLogURL()
            try? fileManager.removeItem(at: bridgeLogURL)
            environment["OPENBOR_V2_LOG_PATH"] = bridgeLogURL.path

            let bridgeInputURL = V2LaunchConfigurationFactory.bridgeInputURL()
            try? fileManager.removeItem(at: bridgeInputURL)
            environment["OPENBOR_V2_INPUT_PATH"] = bridgeInputURL.path

            let liveStateRequestURL = V2LaunchConfigurationFactory.liveStateRequestURL()
            let liveStateManifestURL = V2LaunchConfigurationFactory.liveStateManifestURL()
            try? fileManager.removeItem(at: liveStateRequestURL)
            try? fileManager.removeItem(at: liveStateManifestURL)
            environment["OPENBOR_V2_LIVESTATE_REQUEST_PATH"] = liveStateRequestURL.path
            environment["OPENBOR_V2_LIVESTATE_MANIFEST_PATH"] = liveStateManifestURL.path
            environment["OPENBOR_V2_HOSTED"] = "1"
            let rewindDirectory = V2LaunchConfigurationFactory.bridgeDirectoryURL().appendingPathComponent("Rewind", isDirectory: true)
            try? fileManager.removeItem(at: rewindDirectory)
            try? fileManager.createDirectory(at: rewindDirectory, withIntermediateDirectories: true)
            QuickMenuPreferences.shared.publishRewind()
            environment["OPENBOR_V2_REWIND_DIRECTORY"] = rewindDirectory.path
            environment["OPENBOR_V2_REWIND_COMMAND_PATH"] = V2LaunchConfigurationFactory.rewindCommandURL().path
        }

        return environment
    }

    private func attachReadabilityHandlers(stdoutPipe: Pipe, stderrPipe: Pipe) {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeOutput(from: handle, isError: false)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consumeOutput(from: handle, isError: true)
        }
    }

    private func consumeOutput(from handle: FileHandle, isError: Bool) {
        let data = handle.availableData
        guard !data.isEmpty else { return }

        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        if let processRuntimeLogURL,
           let handle = try? FileHandle(forWritingTo: processRuntimeLogURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = text.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        } else if let processRuntimeLogURL {
            try? text.write(to: processRuntimeLogURL, atomically: true, encoding: .utf8)
        }
        if isError {
            diagnostics.lastErrorMessage = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        print("[OpenBOR process] \(text)", terminator: "")
    }

    private func handleTermination(_ process: Process) {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stopFallbackFrameFeed()

        if process.terminationStatus == 0 {
            state = .idle
        } else {
            let message = diagnostics.lastErrorMessage ?? "OpenBOR process exited with status \(process.terminationStatus)"
            state = .failed(message)
        }

        self.process = nil
        stdoutPipe = nil
        stderrPipe = nil
        frameTransport.reset()
        lastSerializedInput = nil
        isSuspended = false
    }

    private func startFallbackFrameFeed() {
        stopFallbackFrameFeed()
        fallbackTimebase = CACurrentMediaTime()

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.emitFallbackFrame()
        }

        if let fallbackTimer {
            RunLoop.main.add(fallbackTimer, forMode: .common)
        }
    }

    private func stopFallbackFrameFeed() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func emitFallbackFrame() {
        guard state == .running else { return }

        let elapsed = CACurrentMediaTime() - fallbackTimebase
        let image = fallbackFrameSource.makeFrame(time: elapsed, drawableWidth: 960, drawableHeight: 540)
        let packet = EngineFramePacket(
            videoFormat: EngineVideoFormat(
                width: image.width,
                height: image.height,
                bytesPerPixel: 4,
                pixelFormatName: "RGBA8"
            ),
            timestamp: elapsed,
            bytes: Data(image.bytes)
        )

        try? frameTransport.publish(packet)
        onFrame?(packet)
    }

    private func terminateLingeringChildProcesses() {
        let parentPID = String(ProcessInfo.processInfo.processIdentifier)

        let pgrep = Process()
        let outputPipe = Pipe()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", parentPID]
        pgrep.standardOutput = outputPipe
        pgrep.standardError = Pipe()

        do {
            try pgrep.run()
            pgrep.waitUntilExit()
        } catch {
            return
        }

        guard pgrep.terminationStatus == 0,
              let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        else {
            return
        }

        let pids = output
            .split(whereSeparator: \.isWhitespace)
            .compactMap { pidText in pid_t(pidText) }

        for pid in pids where pid > 0 && pid != getpid() {
            kill(pid, SIGKILL)
        }
    }
}
