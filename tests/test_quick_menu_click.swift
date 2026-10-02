import AppKit
import SwiftUI

enum V2LaunchConfigurationFactory {
    static func rewindCommandURL() -> URL {
        URL(fileURLWithPath: "/tmp/openbor-quick-menu-test-rewind.txt")
    }
}

// Compile alongside the production QuickMenuView.swift, without the engine.
struct V2LiveSaveStateSlot: Identifiable {
    let id: String
    let title: String
}

private final class TestMenuWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@main
struct QuickMenuClickTest {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = QuickMenuModel()
        model.slots = [.init(id: "test", title: "Test slot")]
        model.selectedSlotID = "test"
        var shaderDirection = 0
        model.onShaderDirection = { shaderDirection = $0 }
        model.selectedAction = 6
        model.moveSlot(-1)
        precondition(shaderDirection == -1 && model.selectedSlotID == "test")
        model.selectedAction = 1
        var receivedAction: Int?
        model.onAction = { receivedAction = $0 }
        let host = NSHostingView(rootView: QuickMenuView(model: model))
        let window = TestMenuWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 700),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        window.makeKey()
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 400, y: 422), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        precondition(receivedAction == 1, "Decorative overlays blocked the capture button")
        // Exercise navigation in a viewport that cannot show all actions.
        window.setContentSize(NSSize(width: 640, height: 360))
        model.isPresented = true
        model.selectClickedAction(0)
        for action in 1..<model.actions.count {
            model.moveAction(1)
            let revision = model.navigationRevision
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            model.selectHoveredAction(0)
            precondition(model.selectedAction == action, "Stationary mouse stole scroll selection")
            precondition(model.navigationRevision == revision)
        }
        let pointer = NSEvent.mouseLocation
        model.selectHoveredAction(2, pointerLocation: NSPoint(x: pointer.x + 10, y: pointer.y))
        precondition(model.selectedAction == 2, "Actual mouse movement should still select rows")
        let revision = model.navigationRevision
        model.selectHoveredAction(3, pointerLocation: NSPoint(x: pointer.x + 10, y: pointer.y))
        precondition(model.selectedAction == 2 && model.navigationRevision == revision)
        let preferences = InterfaceLanguagePreferences.shared
        let originalLanguage = preferences.language
        defer { preferences.language = originalLanguage }
        for language in InterfaceLanguage.allCases {
            preferences.language = language
            precondition(model.actions[0] == UIStrings.format("Resume game", language: language))
            precondition(model.actions.count == 12)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        print("PASS: clicking the retro menu capture button invokes the capture action.")
        print("PASS: small-window navigation ignores stationary hover; mouse selection does not trigger auto-scroll.")
    }
}
