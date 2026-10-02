import Foundation

enum V2SessionLaunchMode: String, CaseIterable, Identifiable {
    case newSession
    case resumeSession
    case resumeProgress
    case loadSaveState
    case loadLiveSaveState

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newSession:
            return "Nuova Sessione"
        case .resumeSession:
            return "Resume Sessione Live"
        case .resumeProgress:
            return "Riprendi Salvataggio"
        case .loadSaveState:
            return "Carica Snapshot Disco"
        case .loadLiveSaveState:
            return "Carica Live Savestate"
        }
    }

    var detailText: String {
        switch self {
        case .newSession:
            return "Avvia il gioco da zero senza riusare la sessione live sospesa."
        case .resumeSession:
            return "Riprende la stessa sessione sospesa esattamente dal punto in cui hai chiuso la finestra del gioco."
        case .resumeProgress:
            return "Riapre il progresso salvato su disco dal gioco o dall'ultima sessione persistita."
        case .loadSaveState:
            return "Carica uno snapshot manuale dei file di salvataggio su disco. Non e ancora un live save state completo tipo RetroArch."
        case .loadLiveSaveState:
            return "Ripristina uno stato live sperimentale del motore. Usa solo slot creati con lo stesso PAK."
        }
    }
}

struct V2SaveStateSlot: Identifiable, Equatable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let fileCount: Int
}

final class V2SaveStateStore {
    private enum SnapshotKind: String, Codable {
        case resumeSession
        case manual
    }

    private struct SnapshotMetadata: Codable {
        var id: String
        var title: String
        var pakDisplayName: String
        var pakIdentifier: String
        var createdAt: Date
        var updatedAt: Date
        var kind: SnapshotKind
        var fileCount: Int
    }

    enum LaunchSource {
        case newSession
        case resumeSession
        case resumeProgress
        case manualState(String)
        case liveState(String)
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func savedProgressAvailable(for pakURL: URL?) -> Bool {
        guard let pakURL else { return false }
        return snapshotMetadata(at: resumeSnapshotDirectory(for: pakURL)) != nil
    }

    func manualSaveStates(for pakURL: URL?) -> [V2SaveStateSlot] {
        guard let pakURL else { return [] }
        let slotsRoot = manualSnapshotsRootDirectory(for: pakURL)
        let urls = (try? fileManager.contentsOfDirectory(at: slotsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []

        return urls.compactMap { url in
            guard let metadata = snapshotMetadata(at: url), metadata.kind == .manual else { return nil }
            return V2SaveStateSlot(
                id: metadata.id,
                title: metadata.title,
                createdAt: metadata.createdAt,
                updatedAt: metadata.updatedAt,
                fileCount: metadata.fileCount
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func workingStateExists(for pakURL: URL?) -> Bool {
        guard let pakURL else { return false }
        let workingDirectory = workingSavesDirectory(for: pakURL)
        guard let enumerator = fileManager.enumerator(at: workingDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return false
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                return true
            }
        }

        return false
    }

    func prepareWorkingSaves(for pakURL: URL, source: LaunchSource) throws -> URL {
        let workingDirectory = workingSavesDirectory(for: pakURL)
        try ensureDirectory(workingDirectory)
        try clearDirectoryContents(workingDirectory)

        switch source {
        case .newSession, .liveState:
            break
        case .resumeSession:
            break
        case .resumeProgress:
            let snapshotDirectory = resumeSnapshotDirectory(for: pakURL)
            if snapshotMetadata(at: snapshotDirectory) != nil {
                try restoreSnapshotContents(from: snapshotFilesDirectory(for: snapshotDirectory), to: workingDirectory)
            }
        case .manualState(let slotID):
            let snapshotDirectory = manualSnapshotDirectory(for: pakURL, slotID: slotID)
            guard snapshotMetadata(at: snapshotDirectory) != nil else {
                throw NSError(
                    domain: "OpenBORMacV2.SaveStateStore",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Il save state selezionato non esiste piu."]
                )
            }
            try restoreSnapshotContents(from: snapshotFilesDirectory(for: snapshotDirectory), to: workingDirectory)
        }

        return workingDirectory
    }

    func persistSavedProgress(for pakURL: URL) throws {
        let workingDirectory = workingSavesDirectory(for: pakURL)
        guard workingStateExists(for: pakURL) else { return }

        let snapshotDirectory = resumeSnapshotDirectory(for: pakURL)
        _ = try writeSnapshot(from: workingDirectory, to: snapshotDirectory, pakURL: pakURL, kind: .resumeSession, title: "Riprendi Progresso")
    }

    @discardableResult
    func createManualSaveState(for pakURL: URL) throws -> V2SaveStateSlot {
        let workingDirectory = workingSavesDirectory(for: pakURL)
        guard workingStateExists(for: pakURL) else {
            throw NSError(
                domain: "OpenBORMacV2.SaveStateStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Non c'e ancora uno stato di gioco da salvare per questo titolo."]
            )
        }

        let slotID = "state-\(timestampToken())"
        let title = "Snapshot Disco \(displayTimestamp())"
        let snapshotDirectory = manualSnapshotDirectory(for: pakURL, slotID: slotID)
        let metadata = try writeSnapshot(from: workingDirectory, to: snapshotDirectory, pakURL: pakURL, kind: .manual, title: title, id: slotID)

        return V2SaveStateSlot(
            id: metadata.id,
            title: metadata.title,
            createdAt: metadata.createdAt,
            updatedAt: metadata.updatedAt,
            fileCount: metadata.fileCount
        )
    }

    func deleteManualSaveState(for pakURL: URL, slotID: String) throws {
        let snapshotDirectory = manualSnapshotDirectory(for: pakURL, slotID: slotID)
        guard fileManager.fileExists(atPath: snapshotDirectory.path) else { return }
        try fileManager.removeItem(at: snapshotDirectory)
    }

    private func writeSnapshot(from sourceDirectory: URL,
                               to snapshotDirectory: URL,
                               pakURL: URL,
                               kind: SnapshotKind,
                               title: String,
                               id: String? = nil) throws -> SnapshotMetadata
    {
        try ensureDirectory(snapshotDirectory)
        try clearDirectoryContents(snapshotDirectory)

        let filesDirectory = snapshotFilesDirectory(for: snapshotDirectory)
        try ensureDirectory(filesDirectory)
        try copyDirectoryContents(from: sourceDirectory, to: filesDirectory)

        let existing = snapshotMetadata(at: snapshotDirectory)
        let now = Date()
        let metadata = SnapshotMetadata(
            id: id ?? existing?.id ?? kind.rawValue,
            title: title,
            pakDisplayName: pakURL.deletingPathExtension().lastPathComponent,
            pakIdentifier: pakIdentifier(for: pakURL),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            kind: kind,
            fileCount: regularFileCount(in: filesDirectory)
        )

        let data = try encoder.encode(metadata)
        try data.write(to: snapshotDirectory.appendingPathComponent("metadata.json", isDirectory: false), options: .atomic)
        return metadata
    }

    private func snapshotMetadata(at snapshotDirectory: URL) -> SnapshotMetadata? {
        let metadataURL = snapshotDirectory.appendingPathComponent("metadata.json", isDirectory: false)
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? decoder.decode(SnapshotMetadata.self, from: data)
    }

    private func regularFileCount(in directory: URL) -> Int {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return 0
        }

        var count = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    private func workingSavesDirectory(for pakURL: URL) -> URL {
        V2LaunchConfigurationFactory.workingSavesRootURL()
            .appendingPathComponent(pakIdentifier(for: pakURL), isDirectory: true)
    }

    private func saveStatesRootDirectory(for pakURL: URL) -> URL {
        V2LaunchConfigurationFactory.saveStatesRootURL()
            .appendingPathComponent(pakIdentifier(for: pakURL), isDirectory: true)
    }

    private func manualSnapshotsRootDirectory(for pakURL: URL) -> URL {
        saveStatesRootDirectory(for: pakURL).appendingPathComponent("slots", isDirectory: true)
    }

    private func manualSnapshotDirectory(for pakURL: URL, slotID: String) -> URL {
        manualSnapshotsRootDirectory(for: pakURL).appendingPathComponent(slotID, isDirectory: true)
    }

    private func resumeSnapshotDirectory(for pakURL: URL) -> URL {
        saveStatesRootDirectory(for: pakURL).appendingPathComponent("resume-session", isDirectory: true)
    }

    private func snapshotFilesDirectory(for snapshotDirectory: URL) -> URL {
        snapshotDirectory.appendingPathComponent("files", isDirectory: true)
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

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func clearDirectoryContents(_ directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for url in contents {
            try fileManager.removeItem(at: url)
        }
    }

    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try ensureDirectory(destination)
        let contents = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

        for sourceURL in contents {
            let isDirectory = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let destinationURL = destination.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: isDirectory)
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    private func restoreSnapshotContents(from source: URL, to workingDirectory: URL) throws {
        let nestedSavesDirectory = source.appendingPathComponent("Saves", isDirectory: true)
        if fileManager.fileExists(atPath: nestedSavesDirectory.path) {
            try copyDirectoryContents(from: source, to: workingDirectory)
            return
        }

        let legacySavesDirectory = workingDirectory.appendingPathComponent("Saves", isDirectory: true)
        try ensureDirectory(legacySavesDirectory)
        try copyDirectoryContents(from: source, to: legacySavesDirectory)
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
}
