import Foundation

enum V2LaunchConfigurationFactory {
    static func appSupportRootURL() -> URL {
        let fileManager = FileManager.default
        if let path = ProcessInfo.processInfo.environment["OPENBOR_V2_SUPPORT_ROOT"], !path.isEmpty {
            let root = URL(fileURLWithPath: path, isDirectory: true)
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("OpenBORMacV2", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("OpenBORMacV2", isDirectory: true)

        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func bridgeDirectoryURL() -> URL {
        let directory = appSupportRootURL().appendingPathComponent("Bridge", isDirectory: true)
        if Bundle.main.bundleIdentifier == "com.salvatorecuccoro.openborfrontend" {
            return directory.appendingPathComponent("Frontend", isDirectory: true)
        }
        return directory
    }

    static func bridgeFrameInfoURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("frameinfo.txt", isDirectory: false)
    }

    static func bridgeFrameDataURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("frame.raw", isDirectory: false)
    }

    static func bridgeLogURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("engine-bridge.log", isDirectory: false)
    }

    static func bridgeInputURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("inputstate.txt", isDirectory: false)
    }

    static func liveStateRequestURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("livestate-request.txt", isDirectory: false)
    }

    static func quickMenuPauseURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("quick-menu-pause.txt")
    }

    static func rewindCommandURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("rewind-command.txt")
    }

    static func rewindDirectoryURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("Rewind", isDirectory: true)
    }

    static func liveStateManifestURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("livestate-manifest.json", isDirectory: false)
    }

    static func processRuntimeLogURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("process-runtime.log", isDirectory: false)
    }

    static func hostRenderLogURL() -> URL {
        bridgeDirectoryURL().appendingPathComponent("host-render.log", isDirectory: false)
    }

    static func saveStatesRootURL() -> URL {
        let url = appSupportRootURL().appendingPathComponent("SaveStates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func liveSaveStatesRootURL() -> URL {
        let url = appSupportRootURL().appendingPathComponent("LiveSaveStates", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func workingSavesRootURL() -> URL {
        var url = appSupportRootURL().appendingPathComponent("WorkingSaves", isDirectory: true)
        if Bundle.main.bundleIdentifier == "com.salvatorecuccoro.openborfrontend" {
            url = url.appendingPathComponent("Frontend", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeDefault(selectedPakURL: URL? = nil,
                            savesDirectoryOverrideURL: URL? = nil,
                            autoResumeSavedGame: Bool = false,
                            liveStateBootURL: URL? = nil,
                            liveStateScriptURL: URL? = nil,
                            liveStateEntityVariablesURL: URL? = nil) -> EngineLaunchConfiguration {
        let fileManager = FileManager.default
        let appSupportRoot = appSupportRootURL()

        let paksDirectory = preferredPaksDirectory()
        let savesDirectory = savesDirectoryOverrideURL ?? appSupportRoot.appendingPathComponent("Saves", isDirectory: true)
        let logsDirectory = appSupportRoot.appendingPathComponent("Logs", isDirectory: true)
        let screenshotsDirectory = appSupportRoot.appendingPathComponent("ScreenShots", isDirectory: true)

        [appSupportRoot, savesDirectory, logsDirectory, screenshotsDirectory, bridgeDirectoryURL()].forEach { url in
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        return EngineLaunchConfiguration(
            pakURL: selectedPakURL,
            paksDirectoryURL: paksDirectory,
            savesDirectoryURL: savesDirectory,
            logsDirectoryURL: logsDirectory,
            screenshotsDirectoryURL: screenshotsDirectory,
            useMetalRenderer: true,
            shaderPresetName: nil,
            autoResumeSavedGame: autoResumeSavedGame,
            liveStateBootURL: liveStateBootURL,
            liveStateScriptURL: liveStateScriptURL,
            liveStateEntityVariablesURL: liveStateEntityVariablesURL,
            extraArguments: []
        )
    }

    static func availablePakURLs() -> [URL] {
        let fileManager = FileManager.default
        let candidateDirectories = preferredPakDirectories()
        var seenPaths = Set<String>()
        var pakURLs: [URL] = []

        for directory in candidateDirectories {
            let urls = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in urls where url.pathExtension.lowercased() == "pak" {
                let normalizedPath = url.standardizedFileURL.path
                guard seenPaths.insert(normalizedPath).inserted else { continue }
                pakURLs.append(url)
            }
        }

        return pakURLs.sorted { lhs, rhs in
            lhs.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(
                rhs.deletingPathExtension().lastPathComponent
            ) == .orderedAscending
        }
    }

    private static func preferredPaksDirectory() -> URL? {
        let fileManager = FileManager.default
        let candidates = preferredPakDirectories()

        for candidate in candidates {
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        if let fallback = candidates.last {
            try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }

        return nil
    }

    private static func preferredPakDirectories() -> [URL] {
        let fileManager = FileManager.default
        let appSupportPaks = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("OpenBORMacV2/Paks", isDirectory: true)

        let bundleSeedPaks = Bundle.main.resourceURL?
            .appendingPathComponent("SeedPaks", isDirectory: true)

        let legacyCandidates = [
            URL(fileURLWithPath: "/Users/salvatorecuccoro/Applications/OpenBOR Frontend Launcher.app/Contents/Resources/Paks"),
            URL(fileURLWithPath: "/Users/salvatorecuccoro/Documents/New project/build/final/OpenBOR Frontend Launcher.app/Contents/Resources/Paks"),
            URL(fileURLWithPath: "/Users/salvatorecuccoro/Documents/New project/build/final/OpenBOR Frontend Launcher 20260323-0642.app/Contents/Resources/Paks")
        ]

        return [appSupportPaks, bundleSeedPaks]
            .compactMap { $0 }
            + legacyCandidates
    }
}
