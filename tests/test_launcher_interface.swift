import AppKit
import SwiftUI

@main
struct LauncherInterfaceTest {
    @MainActor
    static func main() throws {
        precondition(ProcessInfo.processInfo.environment["OPENBOR_FRONTEND_SUPPORT_ROOT"]?.hasPrefix("/tmp/") == true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = AppModel()
        model.games = [.init(id: "/tmp/hyper.pak", title: "Hyper Duel", pakURL: URL(fileURLWithPath: "/tmp/hyper.pak"), modifiedAt: .now)]
        model.selectedGameID = model.games[0].id
        let language = InterfaceLanguagePreferences.shared
        let originalLanguage = language.language
        defer { language.language = originalLanguage }
        model.showingSettings = true
        let host = NSHostingView(rootView: ContentView().environmentObject(model))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 980, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for selected in InterfaceLanguage.allCases {
            language.language = selected
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/openbor-launcher-integration/interface-\(selected.rawValue).png"))
        }
        model.showingSettings = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/openbor-launcher-integration/arcade-library.png"))
        print("PASS: the launcher settings render in all four languages at 980x640.")
    }
}
