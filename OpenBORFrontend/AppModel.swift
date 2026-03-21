import AppKit
import Foundation
import SQLite3
import UniformTypeIdentifiers

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct GameEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let pakURL: URL
    let modifiedAt: Date
}

struct SaveEntry: Identifiable, Hashable {
    let id: String
    let fileURL: URL
    let modifiedAt: Date
    
    var displayName: String {
        fileURL.deletingPathExtension().lastPathComponent
    }
}

private enum CoverSource: String {
    case generated
    case screenscraper
}

private struct ScreenScraperGameMatch {
    let id: Int
    let title: String
}

private enum ScreenScraperClient {
    static let baseURL = URL(string: "https://api.screenscraper.fr/api2")!
    static let softName = "OpenBORFrontendLauncher"
    
    struct Credentials {
        let developerID: String
        let developerPassword: String
        let userID: String
        let userPassword: String
    }
    
    static func searchGame(title: String, credentials: Credentials) async throws -> ScreenScraperGameMatch? {
        var components = URLComponents(url: baseURL.appendingPathComponent("jeuRecherche.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = credentialsQueryItems(credentials: credentials) + [
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "recherche", value: title)
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { return nil }
        let container = root["response"] as? [String: Any] ?? root
        let gamesValue = container["jeux"] ?? container["jeu"]
        let games = arrayValue(from: gamesValue)
        
        for entry in games {
            if let match = gameMatch(from: entry) {
                return match
            }
        }
        
        return nil
    }
    
    static func downloadBoxArt(for gameID: Int, credentials: Credentials) async throws -> Data? {
        let mediaCandidates = ["box-2D", "box-texture", "box-scan"]
        
        for media in mediaCandidates {
            var components = URLComponents(url: baseURL.appendingPathComponent("mediaJeu.php"), resolvingAgainstBaseURL: false)!
            components.queryItems = credentialsQueryItems(credentials: credentials) + [
                URLQueryItem(name: "jeuid", value: String(gameID)),
                URLQueryItem(name: "media", value: media),
                URLQueryItem(name: "outputformat", value: "png"),
                URLQueryItem(name: "maxwidth", value: "600"),
                URLQueryItem(name: "maxheight", value: "840")
            ]
            
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            if isImagePayload(data) {
                return data
            }
        }
        
        return nil
    }
    
    private static func credentialsQueryItems(credentials: Credentials) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "devid", value: credentials.developerID),
            URLQueryItem(name: "devpassword", value: credentials.developerPassword),
            URLQueryItem(name: "softname", value: softName)
        ]
        
        if !credentials.userID.isEmpty {
            items.append(URLQueryItem(name: "ssid", value: credentials.userID))
        }
        if !credentials.userPassword.isEmpty {
            items.append(URLQueryItem(name: "sspassword", value: credentials.userPassword))
        }
        
        return items
    }
    
    private static func arrayValue(from any: Any?) -> [[String: Any]] {
        if let array = any as? [[String: Any]] {
            return array
        }
        if let dictionary = any as? [String: Any] {
            return [dictionary]
        }
        return []
    }
    
    private static func gameMatch(from dictionary: [String: Any]) -> ScreenScraperGameMatch? {
        let idValue = dictionary["id"] ?? dictionary["jeu_id"] ?? dictionary["gameid"]
        let titleValue = dictionary["nom"] ?? dictionary["jeu_nom"] ?? dictionary["name"]
        
        let id: Int?
        if let intValue = idValue as? Int {
            id = intValue
        } else if let stringValue = idValue as? String {
            id = Int(stringValue)
        } else {
            id = nil
        }
        
        let title = (titleValue as? String) ?? "Unknown"
        
        guard let id else { return nil }
        return ScreenScraperGameMatch(id: id, title: title)
    }
    
    private static func isImagePayload(_ data: Data) -> Bool {
        if data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) { return true }
        if data.starts(with: Data([0xFF, 0xD8, 0xFF])) { return true }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
           ["NOMEDIA", "CRCOK", "MD5OK", "SHA1OK"].contains(text) {
            return false
        }
        return false
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var games: [GameEntry] = []
    @Published var selectedGameID: GameEntry.ID?
    @Published var statusText = "Ready"
    @Published var showingSettings = false
    @Published var searchText = ""
    @Published private(set) var coverURLs: [String: URL] = [:]
    @Published private(set) var coverRefreshTokens: [String: UUID] = [:]
    @Published var screenScraperDeveloperID = UserDefaults.standard.string(forKey: "ss.developerID") ?? "" {
        didSet { UserDefaults.standard.set(screenScraperDeveloperID, forKey: "ss.developerID") }
    }
    @Published var screenScraperDeveloperPassword = UserDefaults.standard.string(forKey: "ss.developerPassword") ?? "" {
        didSet { UserDefaults.standard.set(screenScraperDeveloperPassword, forKey: "ss.developerPassword") }
    }
    @Published var screenScraperUserID = UserDefaults.standard.string(forKey: "ss.userID") ?? "" {
        didSet { UserDefaults.standard.set(screenScraperUserID, forKey: "ss.userID") }
    }
    @Published var screenScraperUserPassword = UserDefaults.standard.string(forKey: "ss.userPassword") ?? "" {
        didSet { UserDefaults.standard.set(screenScraperUserPassword, forKey: "ss.userPassword") }
    }
    
    let pakDirectory: URL
    let savesDirectory: URL
    let logsDirectory: URL
    let screenshotsDirectory: URL
    let coversDirectory: URL
    let coverDatabaseURL: URL
    
    private let startupPak: URL?
    private var coverDatabase: OpaquePointer?
    private var screenScraperFetchInFlight: Set<String> = []
    
    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenBOR Frontend", isDirectory: true)
        pakDirectory = base.appendingPathComponent("Paks", isDirectory: true)
        savesDirectory = base.appendingPathComponent("Saves", isDirectory: true)
        logsDirectory = base.appendingPathComponent("Logs", isDirectory: true)
        screenshotsDirectory = base.appendingPathComponent("ScreenShots", isDirectory: true)
        coversDirectory = base.appendingPathComponent("Covers", isDirectory: true)
        coverDatabaseURL = base.appendingPathComponent("CoverLibrary.sqlite", isDirectory: false)
        startupPak = AppModel.parseLaunchArgument()
        
        ensureDirectories()
        openCoverDatabase()
        importSeedPaksIfNeeded()
        reloadGames()
    }
    
    deinit {
        if let coverDatabase {
            sqlite3_close(coverDatabase)
        }
    }
    
    var selectedGame: GameEntry? {
        games.first(where: { $0.id == selectedGameID }) ?? filteredGames.first
    }
    
    var filteredGames: [GameEntry] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return games
        }
        return games.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    var isLaunchOnlyMode: Bool {
        startupPak != nil
    }
    
    func handleStartupLaunchIfNeeded() {
        guard let startupPak else { return }
        launch(pakURL: startupPak)
        NSApp.terminate(nil)
    }
    
    func reloadGames() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: pakDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        
        games = urls
            .filter { $0.pathExtension.lowercased() == "pak" }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let modified = values?.contentModificationDate ?? .distantPast
                let title = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
                return GameEntry(id: url.path, title: title, pakURL: url, modifiedAt: modified)
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        
        if selectedGameID == nil || !games.contains(where: { $0.id == selectedGameID }) {
            selectedGameID = games.first?.id
        }
        
        refreshCoverLibrary()
        statusText = games.isEmpty ? "No games found in Paks" : "\(games.count) game(s) available"
    }
    
    func coverURL(for game: GameEntry?) -> URL? {
        guard let game else { return nil }
        return coverURLs[game.id]
    }
    
    func coverRefreshToken(for game: GameEntry?) -> UUID {
        guard let game else { return UUID() }
        return coverRefreshTokens[game.id] ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    }
    
    var hasScreenScraperDeveloperCredentials: Bool {
        !screenScraperDeveloperID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !screenScraperDeveloperPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func refreshRemoteCovers() {
        refreshCoverLibrary()
    }
    
    func saves(for game: GameEntry?) -> [SaveEntry] {
        guard let game else { return [] }
        let fm = FileManager.default
        let stem = game.pakURL.deletingPathExtension().lastPathComponent
        let urls = (try? fm.contentsOfDirectory(
            at: savesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        
        return urls
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix(stem) || name == "bor.cfg"
            }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return SaveEntry(id: url.path, fileURL: url, modifiedAt: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }
    
    func launchSelectedGame() {
        guard let selectedGame else { return }
        launch(game: selectedGame)
    }
    
    func launch(game: GameEntry) {
        launch(pakURL: game.pakURL)
    }
    
    func openPaksFolder() {
        NSWorkspace.shared.open(pakDirectory)
    }
    
    func openSavesFolder() {
        NSWorkspace.shared.open(savesDirectory)
    }
    
    func openCoversFolder() {
        NSWorkspace.shared.open(coversDirectory)
    }
    
    func reveal(_ game: GameEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([game.pakURL])
    }
    
    func reveal(_ save: SaveEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([save.fileURL])
    }
    
    func importCover(for game: GameEntry) {
        let panel = NSOpenPanel()
        panel.title = "Choose cover for \(game.title)"
        panel.message = "Select a PNG, JPG, JPEG, or WEBP image to use as the game's cover."
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        
        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }
        
        let destinationURL = coversDirectory.appendingPathComponent(coverFileName(for: game))
        
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: selectedURL, to: destinationURL)
            saveCoverRecord(for: game, coverURL: destinationURL, source: "manual")
            coverURLs[game.id] = destinationURL
            coverRefreshTokens[game.id] = UUID()
            statusText = "Cover importata per \(game.title)"
        } catch {
            NSSound.beep()
            statusText = "Import cover failed: \(error.localizedDescription)"
        }
    }
    
    private func launch(pakURL: URL) {
        let engineApp = Bundle.main.resourceURL?
            .appendingPathComponent("Engine/OpenBOR.app", isDirectory: true)
        guard let engineApp, FileManager.default.fileExists(atPath: engineApp.path) else {
            statusText = "Embedded OpenBOR engine not found"
            NSSound.beep()
            return
        }
        
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = true
        config.arguments = [pakURL.path]
        config.environment = [
            "OPENBOR_PAKS_DIR": pakDirectory.path,
            "OPENBOR_SAVES_DIR": savesDirectory.path,
            "OPENBOR_LOGS_DIR": logsDirectory.path,
            "OPENBOR_SCREENSHOTS_DIR": screenshotsDirectory.path
        ]
        
        statusText = "Launching \(pakURL.lastPathComponent)..."
        NSWorkspace.shared.openApplication(at: engineApp, configuration: config) { _, error in
            Task { @MainActor in
                if let error {
                    self.statusText = "Launch failed: \(error.localizedDescription)"
                    NSSound.beep()
                } else {
                    self.statusText = "Running \(pakURL.lastPathComponent)"
                }
            }
        }
    }
    
    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [pakDirectory, savesDirectory, logsDirectory, screenshotsDirectory, coversDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    private func importSeedPaksIfNeeded() {
        guard games.isEmpty else { return }
        guard let seedDir = Bundle.main.resourceURL?.appendingPathComponent("SeedPaks", isDirectory: true) else { return }
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: seedDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for url in urls where url.pathExtension.lowercased() == "pak" {
            let dest = pakDirectory.appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: url, to: dest)
            }
        }
    }
    
    private static func parseLaunchArgument() -> URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--launch"), index + 1 < args.count else {
            return nil
        }
        return URL(fileURLWithPath: args[index + 1])
    }
    
    private func openCoverDatabase() {
        guard sqlite3_open(coverDatabaseURL.path, &coverDatabase) == SQLITE_OK else {
            coverDatabase = nil
            return
        }
        
        let createSQL = """
        CREATE TABLE IF NOT EXISTS covers (
            game_id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            cover_path TEXT NOT NULL,
            source TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """
        
        sqlite3_exec(coverDatabase, createSQL, nil, nil, nil)
    }
    
    private func refreshCoverLibrary() {
        var updated: [String: URL] = [:]
        
        for game in games {
            if let existing = existingCoverURL(for: game), FileManager.default.fileExists(atPath: existing.path) {
                updated[game.id] = existing
                coverRefreshTokens[game.id] = UUID()
                if coverSource(for: game) != .screenscraper {
                    queueScreenScraperFetchIfPossible(for: game)
                }
                continue
            }
            
            if let generated = generateCover(for: game) {
                saveCoverRecord(for: game, coverURL: generated, source: CoverSource.generated.rawValue)
                updated[game.id] = generated
                coverRefreshTokens[game.id] = UUID()
                queueScreenScraperFetchIfPossible(for: game)
            }
        }
        
        coverURLs = updated
    }
    
    private func coverSource(for game: GameEntry) -> CoverSource? {
        guard let coverDatabase else { return nil }
        let querySQL = "SELECT source FROM covers WHERE game_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(coverDatabase, querySQL, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (game.id as NSString).utf8String, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        
        return CoverSource(rawValue: String(cString: text))
    }
    
    private func existingCoverURL(for game: GameEntry) -> URL? {
        guard let coverDatabase else { return nil }
        let querySQL = "SELECT cover_path FROM covers WHERE game_id = ? LIMIT 1;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(coverDatabase, querySQL, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (game.id as NSString).utf8String, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        
        return URL(fileURLWithPath: String(cString: text))
    }
    
    private func saveCoverRecord(for game: GameEntry, coverURL: URL, source: String) {
        guard let coverDatabase else { return }
        let upsertSQL = """
        INSERT INTO covers (game_id, title, cover_path, source, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(game_id) DO UPDATE SET
            title = excluded.title,
            cover_path = excluded.cover_path,
            source = excluded.source,
            updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(coverDatabase, upsertSQL, -1, &statement, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, (game.id as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, (game.title as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, (coverURL.path as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, (source as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
        sqlite3_step(statement)
    }
    
    private func queueScreenScraperFetchIfPossible(for game: GameEntry) {
        guard hasScreenScraperDeveloperCredentials else { return }
        guard !screenScraperFetchInFlight.contains(game.id) else { return }
        
        screenScraperFetchInFlight.insert(game.id)
        
        Task {
            defer {
                Task { @MainActor in
                    self.screenScraperFetchInFlight.remove(game.id)
                }
            }
            
            guard let credentials = makeScreenScraperCredentials() else { return }
            
            do {
                guard let match = try await ScreenScraperClient.searchGame(title: game.title, credentials: credentials),
                      let data = try await ScreenScraperClient.downloadBoxArt(for: match.id, credentials: credentials) else {
                    return
                }
                
                let coverURL = coversDirectory.appendingPathComponent(coverFileName(for: game))
                try data.write(to: coverURL, options: .atomic)
                
                await MainActor.run {
                    self.saveCoverRecord(for: game, coverURL: coverURL, source: CoverSource.screenscraper.rawValue)
                    self.coverURLs[game.id] = coverURL
                    self.coverRefreshTokens[game.id] = UUID()
                    self.statusText = "Cover aggiornata da ScreenScraper per \(match.title)"
                }
            } catch {
                await MainActor.run {
                    self.statusText = "ScreenScraper non disponibile per \(game.title)"
                }
            }
        }
    }
    
    private func makeScreenScraperCredentials() -> ScreenScraperClient.Credentials? {
        let developerID = screenScraperDeveloperID.trimmingCharacters(in: .whitespacesAndNewlines)
        let developerPassword = screenScraperDeveloperPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !developerID.isEmpty, !developerPassword.isEmpty else {
            return nil
        }
        
        return .init(
            developerID: developerID,
            developerPassword: developerPassword,
            userID: screenScraperUserID.trimmingCharacters(in: .whitespacesAndNewlines),
            userPassword: screenScraperUserPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    
    private func generateCover(for game: GameEntry) -> URL? {
        let size = NSSize(width: 600, height: 840)
        let image = NSImage(size: size)
        let coverURL = coversDirectory.appendingPathComponent(coverFileName(for: game))
        let rect = NSRect(origin: .zero, size: size)
        
        image.lockFocus()
        
        let colors = palette(for: game.title)
        let background = NSGradient(colors: colors) ?? NSGradient(starting: .orange, ending: .red)
        background?.draw(in: rect, angle: 120)
        
        NSColor.black.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 24, dy: 24), xRadius: 34, yRadius: 34).fill()
        
        let badgeRect = NSRect(x: 48, y: size.height - 176, width: 132, height: 132)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 28, yRadius: 28).fill()
        
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 64, weight: .bold)
        let icon = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        icon?.draw(in: badgeRect.insetBy(dx: 28, dy: 28))
        
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byWordWrapping
        
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .heavy),
            .foregroundColor: NSColor.white,
            .paragraphStyle: titleParagraph
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]
        let initialsAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 124, weight: .black),
            .foregroundColor: NSColor.white.withAlphaComponent(0.12)
        ]
        
        let initials = gameInitials(for: game.title)
        NSString(string: initials).draw(in: NSRect(x: 330, y: 58, width: 220, height: 150), withAttributes: initialsAttributes)
        NSString(string: game.title).draw(in: NSRect(x: 48, y: 218, width: 504, height: 300), withAttributes: titleAttributes)
        NSString(string: game.pakURL.deletingPathExtension().lastPathComponent).draw(in: NSRect(x: 48, y: 124, width: 504, height: 36), withAttributes: subtitleAttributes)
        NSString(string: "OPENBOR").draw(in: NSRect(x: 48, y: 64, width: 180, height: 28), withAttributes: subtitleAttributes)
        
        image.unlockFocus()
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        do {
            try pngData.write(to: coverURL, options: .atomic)
            return coverURL
        } catch {
            return nil
        }
    }
    
    private func coverFileName(for game: GameEntry) -> String {
        let raw = game.pakURL.deletingPathExtension().lastPathComponent.lowercased()
        let cleaned = raw
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "--", with: "-")
        return "\(cleaned)-cover.png"
    }
    
    private func gameInitials(for title: String) -> String {
        let words = title
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
            .prefix(3)
        let initials = words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        return initials.isEmpty ? "BOR" : initials
    }
    
    private func palette(for title: String) -> [NSColor] {
        let palettes: [[NSColor]] = [
            [NSColor(calibratedRed: 0.95, green: 0.34, blue: 0.19, alpha: 1), NSColor(calibratedRed: 0.49, green: 0.07, blue: 0.18, alpha: 1)],
            [NSColor(calibratedRed: 0.15, green: 0.56, blue: 0.96, alpha: 1), NSColor(calibratedRed: 0.06, green: 0.13, blue: 0.39, alpha: 1)],
            [NSColor(calibratedRed: 0.98, green: 0.68, blue: 0.17, alpha: 1), NSColor(calibratedRed: 0.63, green: 0.22, blue: 0.09, alpha: 1)],
            [NSColor(calibratedRed: 0.22, green: 0.79, blue: 0.56, alpha: 1), NSColor(calibratedRed: 0.04, green: 0.25, blue: 0.23, alpha: 1)],
            [NSColor(calibratedRed: 0.72, green: 0.36, blue: 0.95, alpha: 1), NSColor(calibratedRed: 0.19, green: 0.08, blue: 0.33, alpha: 1)]
        ]
        let hash = abs(title.lowercased().hashValue)
        return palettes[hash % palettes.count]
    }
}
