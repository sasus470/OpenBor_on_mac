import CryptoKit
import Foundation

struct V2LiveSaveStateSlot: Identifiable, Equatable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let schema: String
    let engineVersion: String
}

final class V2LiveSaveStateStore {
    private static let runtimeStateSchema = "openbor-v2-runtime-state-v1"
    private static let bootStateHeader = "OPENBOR_V2_LIVE_BOOT_V8\n"

    private struct LiveSaveStateMetadata: Codable {
        let id: String
        let pakIdentifier: String
        let pakFingerprint: String
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let schema: String
        let engineVersion: String
    }

    private struct RuntimeStateHeader: Decodable {
        let schema: String
        let engineVersion: String
        let entityStateComplete: Int

        enum CodingKeys: String, CodingKey {
            case schema
            case engineVersion = "engine_version"
            case entityStateComplete = "entity_state_complete"
        }
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

    var supportsLiveSnapshots: Bool {
        true
    }

    func liveSaveStates(for pakURL: URL?) -> [V2LiveSaveStateSlot] {
        guard let pakURL else { return [] }
        let root = liveSlotsRootDirectory(for: pakURL)
        let urls = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []

        return urls.compactMap { url in
            guard let metadata = metadata(at: url) else { return nil }
            return V2LiveSaveStateSlot(
                id: metadata.id,
                title: metadata.title,
                createdAt: metadata.createdAt,
                updatedAt: metadata.updatedAt,
                schema: metadata.schema,
                engineVersion: metadata.engineVersion
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func persistArtifact(_ artifact: EngineLiveSaveStateArtifact) throws {
        let header = try runtimeStateHeader(at: artifact.manifestURL)
        guard header.schema == Self.runtimeStateSchema, header.entityStateComplete == 1 else {
            throw NSError(
                domain: "OpenBORMacV2.LiveSaveStateStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Il runtime ha restituito uno stato live incompleto o non compatibile."]
            )
        }

        let slotDirectory = liveSlotDirectory(forPakIdentifier: artifact.pakIdentifier, slotID: artifact.id)
        try fileManager.createDirectory(at: slotDirectory, withIntermediateDirectories: true)

        let metadata = LiveSaveStateMetadata(
            id: artifact.id,
            pakIdentifier: artifact.pakIdentifier,
            pakFingerprint: try pakFingerprint(for: artifact.pakURL),
            title: artifact.title,
            createdAt: artifact.createdAt,
            updatedAt: artifact.createdAt,
            schema: header.schema,
            engineVersion: header.engineVersion
        )

        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL(for: slotDirectory), options: .atomic)

        let payloadDirectory = slotDirectory.appendingPathComponent("payload", isDirectory: true)
        try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)

        let manifestDestination = payloadDirectory.appendingPathComponent(artifact.manifestURL.lastPathComponent, isDirectory: false)
        if fileManager.fileExists(atPath: manifestDestination.path) {
            try fileManager.removeItem(at: manifestDestination)
        }
        try fileManager.copyItem(at: artifact.manifestURL, to: manifestDestination)

        if let bootURL = artifact.bootURL {
            let bootDestination = payloadDirectory.appendingPathComponent("manifest.json.boot", isDirectory: false)
            if fileManager.fileExists(atPath: bootDestination.path) {
                try fileManager.removeItem(at: bootDestination)
            }
            try fileManager.copyItem(at: bootURL, to: bootDestination)
        }
        if let scriptURL = artifact.scriptURL {
            let scriptDestination = payloadDirectory.appendingPathComponent("manifest.json.script", isDirectory: false)
            if fileManager.fileExists(atPath: scriptDestination.path) {
                try fileManager.removeItem(at: scriptDestination)
            }
            try fileManager.copyItem(at: scriptURL, to: scriptDestination)
        }
        if let entityVariablesURL = artifact.entityVariablesURL {
            let entityVariablesDestination = payloadDirectory.appendingPathComponent("manifest.json.entityvars", isDirectory: false)
            if fileManager.fileExists(atPath: entityVariablesDestination.path) {
                try fileManager.removeItem(at: entityVariablesDestination)
            }
            try fileManager.copyItem(at: entityVariablesURL, to: entityVariablesDestination)
        }
    }

    func artifact(for pakURL: URL, slotID: String) throws -> EngineLiveSaveStateArtifact {
        let slotDirectory = liveSlotDirectory(for: pakURL, slotID: slotID)
        guard let metadata = metadata(at: slotDirectory) else {
            throw NSError(
                domain: "OpenBORMacV2.LiveSaveStateStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Il live savestate selezionato non esiste piu."]
            )
        }

        let currentPakFingerprint = try pakFingerprint(for: pakURL)
        guard metadata.pakIdentifier == pakIdentifier(for: pakURL),
              metadata.pakFingerprint == currentPakFingerprint else {
            throw NSError(
                domain: "OpenBORMacV2.LiveSaveStateStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Questo live savestate appartiene a un PAK diverso o modificato e non puo essere caricato in sicurezza."]
            )
        }

        let stateURL = slotDirectory.appendingPathComponent("payload/manifest.json", isDirectory: false)
        let header = try runtimeStateHeader(at: stateURL)
        guard header.schema == metadata.schema,
              header.engineVersion == metadata.engineVersion,
              header.entityStateComplete == 1 else {
            throw NSError(
                domain: "OpenBORMacV2.LiveSaveStateStore",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Il payload del live savestate non supera i controlli di integrita."]
            )
        }

        let bootURL = URL(fileURLWithPath: stateURL.path + ".boot")
        guard isCurrentBootPayload(at: bootURL) else {
            throw NSError(
                domain: "OpenBORMacV2.LiveSaveStateStore",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Questo live savestate usa un formato precedente. Crea una nuova cattura con la build attuale."]
            )
        }
        let entityVariablesURL = URL(fileURLWithPath: stateURL.path + ".entityvars")
        guard fileManager.fileExists(atPath: entityVariablesURL.path) else {
            throw NSError(
                domain: "OpenBORMacV2.LiveSaveStateStore",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Questo live savestate non contiene le variabili per-entita. Crea una nuova cattura con la build attuale."]
            )
        }

        return EngineLiveSaveStateArtifact(
            id: metadata.id,
            pakIdentifier: metadata.pakIdentifier,
            pakURL: pakURL,
            title: metadata.title,
            createdAt: metadata.createdAt,
            manifestURL: stateURL,
            bootURL: bootURL,
            scriptURL: fileManager.fileExists(atPath: stateURL.path + ".script")
                ? URL(fileURLWithPath: stateURL.path + ".script")
                : nil,
            entityVariablesURL: entityVariablesURL,
            payloadDirectoryURL: slotDirectory.appendingPathComponent("payload", isDirectory: true)
        )
    }

    private func metadata(at slotDirectory: URL) -> LiveSaveStateMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: slotDirectory)) else { return nil }
        return try? decoder.decode(LiveSaveStateMetadata.self, from: data)
    }

    private func metadataURL(for slotDirectory: URL) -> URL {
        slotDirectory.appendingPathComponent("metadata.json", isDirectory: false)
    }

    private func liveSlotsRootDirectory(for pakURL: URL) -> URL {
        liveSlotsRootDirectory(forPakIdentifier: pakIdentifier(for: pakURL))
    }

    private func liveSlotsRootDirectory(forPakIdentifier pakIdentifier: String) -> URL {
        let url = V2LaunchConfigurationFactory.liveSaveStatesRootURL()
            .appendingPathComponent(pakIdentifier, isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func liveSlotDirectory(forPakIdentifier pakIdentifier: String, slotID: String) -> URL {
        liveSlotsRootDirectory(forPakIdentifier: pakIdentifier)
            .appendingPathComponent(slotID, isDirectory: true)
    }

    private func liveSlotDirectory(for pakURL: URL, slotID: String) -> URL {
        liveSlotDirectory(forPakIdentifier: pakIdentifier(for: pakURL), slotID: slotID)
    }

    private func runtimeStateHeader(at url: URL) throws -> RuntimeStateHeader {
        let data = try Data(contentsOf: url)
        return try decoder.decode(RuntimeStateHeader.self, from: data)
    }

    private func isCurrentBootPayload(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let header = String(data: data.prefix(Self.bootStateHeader.utf8.count), encoding: .utf8) else {
            return false
        }
        return header == Self.bootStateHeader || header == "OPENBOR_V2_LIVE_BOOT_V7\n" || header == "OPENBOR_V2_LIVE_BOOT_V6\n"
    }

    private func pakFingerprint(for pakURL: URL) throws -> String {
        let data = try Data(contentsOf: pakURL, options: [.mappedIfSafe])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
}
