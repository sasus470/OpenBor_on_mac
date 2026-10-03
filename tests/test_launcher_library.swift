import AppKit
import SwiftUI

@main
struct LauncherLibraryTest {
    @MainActor
    static func main() throws {
        guard let rootPath = ProcessInfo.processInfo.environment["OPENBOR_FRONTEND_SUPPORT_ROOT"], rootPath.hasPrefix("/tmp/") else {
            fatalError("An isolated /tmp support root is required")
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: rootPath)
        let defaults = UserDefaults.standard
        let keys = ["launcher.pakDirectory", "launcher.libraryLayout", "launcher.launchFullscreen"]
        let previous = keys.map { defaults.object(forKey: $0) }
        let language = InterfaceLanguagePreferences.shared
        let originalLanguage = language.language
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            language.language = originalLanguage
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let first = root.appendingPathComponent("Library One", isDirectory: true).standardizedFileURL
        let second = root.appendingPathComponent("Library Two", isDirectory: true).standardizedFileURL
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let titles = ["Alpha Wings", "Blue Horizon", "Cosmic Patrol", "Dragon Squadron", "Evening Raid", "Final Frontier", "Golden Sky", "Hyper Duel"]
        for title in titles {
            try Data().write(to: first.appendingPathComponent(title + ".pak"))
        }
        try Data().write(to: second.appendingPathComponent("Other Game.PAK"))
        try FileManager.default.createDirectory(at: second.appendingPathComponent("not-a-game.pak"), withIntermediateDirectories: true)
        let model = AppModel()
        precondition(!model.launchFullscreen && !model.runtimeCoordinator.launchFullscreen)
        model.launchFullscreen = true
        precondition(model.runtimeCoordinator.launchFullscreen)
        precondition(model.libraryLayout == .sidebar)
        precondition(model.setPaksFolder(first))
        precondition(model.games.count == 8 && !model.usesDefaultPakDirectory)
        precondition(model.games.allSatisfy { $0.pakURL.deletingLastPathComponent().resolvingSymlinksInPath().path == first.resolvingSymlinksInPath().path }, "Unexpected game paths: \(model.games.map(\.pakURL)) versus \(first)")
        model.selectedGameID = model.games[3].id
        model.searchText = "Cosmic"
        precondition(model.filteredGames.count == 1)
        precondition(model.setPaksFolder(second))
        precondition(model.games.count == 1 && model.searchText.isEmpty)
        precondition(model.selectedGame?.title == "Other Game")
        precondition(model.runtimeCoordinator.selectedPakURL == model.selectedGame?.pakURL)
        precondition(!model.setPaksFolder(root.appendingPathComponent("missing")))
        precondition(model.pakDirectory.path == second.path)
        model.libraryLayout = .grid
        let restored = AppModel()
        precondition(restored.launchFullscreen && restored.runtimeCoordinator.launchFullscreen)
        model.launchFullscreen = false
        precondition(!model.runtimeCoordinator.launchFullscreen)
        precondition(restored.libraryLayout == .grid && restored.pakDirectory.path == second.path)
        precondition(restored.games.count == 1)
        precondition(model.setPaksFolder(first))
        let host = NSHostingView(rootView: ContentView().environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 980, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        window.makeKey()
        defer { window.orderOut(nil) }
        model.libraryLayout = .sidebar
        for selected in InterfaceLanguage.allCases {
            language.language = selected
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            host.layoutSubtreeIfNeeded()
            let segments = segmentedControls(in: host)
            let expected = UIStrings.format("Sidebar list", language: selected)
            precondition(segments.contains { control in (0..<control.segmentCount).contains { control.label(forSegment: $0) == expected } }, "Layout labels did not update immediately in \(selected)")
        }
        for selected in InterfaceLanguage.allCases {
            language.language = selected
            for layout in LauncherLibraryLayout.allCases {
                model.libraryLayout = layout
                try screenshot(host, to: root.appendingPathComponent("\(layout.rawValue)-\(selected.rawValue).png"))
            }
        }
        language.language = .italian
        for layout in LauncherLibraryLayout.allCases {
            model.libraryLayout = layout
            model.selectedGameID = model.games[0].id
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            click(host, window: window, pointFromTop: layout == .sidebar ? NSPoint(x: 45, y: 260) : NSPoint(x: 270, y: 220))
            try screenshot(host, to: root.appendingPathComponent("click-cover-\(layout.rawValue).png"))
            precondition(model.selectedGameID == model.games[1].id, "Cover click did not select the second game in \(layout)")
            click(host, window: window, pointFromTop: layout == .sidebar ? NSPoint(x: 125, y: 325) : NSPoint(x: 440, y: 339))
            precondition(model.selectedGameID == model.games[2].id, "Title click did not select the third game in \(layout)")
        }
        model.showingSettings = true
        try screenshot(host, to: root.appendingPathComponent("library-settings.png"))
        model.showingSettings = false
        model.libraryLayout = .grid
        window.setContentSize(NSSize(width: 1280, height: 800))
        try screenshot(host, to: root.appendingPathComponent("grid-wide.png"))
        model.searchText = "no matches"
        try screenshot(host, to: root.appendingPathComponent("grid-empty-search.png"))
        model.resetPaksFolder()
        precondition(model.usesDefaultPakDirectory && model.pakDirectory == model.defaultPakDirectory)
        precondition(defaults.string(forKey: "launcher.pakDirectory") == nil)
        let afterReset = AppModel()
        precondition(afterReset.usesDefaultPakDirectory)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: first.path)
        precondition(remainingFiles.count == 8)
        print("PASS: PAK folder switching, validation, persistence, reset, search and filtering; cover/title click selection in both layouts; grid/list render in four languages at 980x640 and 1280x800.")
        print("Screenshots: \(root.path)")
    }

    @MainActor
    static func segmentedControls(in view: NSView) -> [NSSegmentedControl] {
        (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap { segmentedControls(in: $0) }
    }

    @MainActor
    static func click(_ host: NSView, window: NSWindow, pointFromTop: NSPoint) {
        let point = NSPoint(x: pointFromTop.x, y: host.isFlipped ? pointFromTop.y : host.bounds.height - pointFromTop.y)
        let location = host.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    }

    @MainActor
    static func screenshot(_ host: NSView, to url: URL) throws {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
