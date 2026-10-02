import AppKit
import SwiftUI

@main
struct LauncherRuntimeTest {
    @MainActor
    static func main() {
        precondition(ProcessInfo.processInfo.environment["OPENBOR_V2_SUPPORT_ROOT"]?.hasPrefix("/tmp/") == true)
        precondition(ProcessInfo.processInfo.environment["OPENBOR_FRONTEND_SUPPORT_ROOT"]?.hasPrefix("/tmp/") == true)
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel()
        let originalBackend = model.renderBackend
        let preferences = QuickMenuPreferences.shared
        let originalRewind = preferences.rewindEnabled
        let originalRewindKey = preferences.rewindKey
        defer { preferences.rewindEnabled = originalRewind; preferences.rewindKey = originalRewindKey }
        model.renderBackend = ProcessInfo.processInfo.environment["TEST_RENDERER"] == "opengl" ? .openGL : .metal
        defer { model.renderBackend = originalBackend }
        let coordinator = model.runtimeCoordinator
        defer { coordinator.shutdown() }
        precondition(coordinator.runtimeMode == .process)
        guard let path = ProcessInfo.processInfo.environment["TEST_PAK_PATH"] else { fatalError("TEST_PAK_PATH required") }
        let game = GameEntry(id: path, title: "Integration Test", pakURL: URL(fileURLWithPath: path), modifiedAt: .now)
        model.launch(game: game)
        wait("first frame", timeout: 20) {
            coordinator.runtimeState == .running &&
            ((try? String(contentsOf: V2LaunchConfigurationFactory.hostRenderLogURL()))?.contains("frame source=") == true)
        }
        precondition(coordinator.lastLaunchedSessionMode == .newSession)
        precondition(coordinator.runtimeDiagnostics.rendererName.contains(model.renderBackend == .openGL ? "OpenGL" : "Metal"))
        coordinator.refreshSaveSlots()
        precondition(!coordinator.liveSaveStates.isEmpty, "Copy a fixture slot into the isolated LiveSaveStates directory first")
        coordinator.sessionLaunchMode = .loadLiveSaveState
        coordinator.selectedLiveSaveStateID = "live-20261002-021902"
        try? FileManager.default.removeItem(at: nativeLogURL())
        coordinator.showHostWindow()
        wait("fixture import", timeout: 20) { nativeLog().contains("[live-state] restored wave:") }
        let hostWindow = NSApplication.shared.windows.first { $0.identifier == HostWindowController.windowIdentifier }!
        if ProcessInfo.processInfo.environment["TEST_REWIND"] == "1" {
            preferences.rewindKey = preferences.keyboard == .f6 ? .f7 : .f6
            preferences.rewindEnabled = true
            // Fill the rail beyond one viewport: a short history masked the
            // opening layout bug because every checkpoint was already visible.
            RunLoop.main.run(until: Date().addingTimeInterval(16))
            let before = try! coordinatorCapture(coordinator, window: hostWindow)
            sendKey(preferences.rewindKey.keyCode, down: true, window: hostWindow)
            sendKey(preferences.rewindKey.keyCode, down: false, window: hostWindow)
            let timeline = hostWindow.contentView!.subviews.compactMap { ($0 as? NSHostingView<RewindTimelineView>)?.rootView.model }.first!
            precondition(timeline.isLoadingHistory && !timeline.showsEmptyHistory,
                         "Opening must not flash the empty-history message")
            let timelineView = hostWindow.contentView!.subviews.compactMap { $0 as? NSHostingView<RewindTimelineView> }.first!
            timelineView.layoutSubtreeIfNeeded()
            let openingBitmap = timelineView.bitmapImageRepForCachingDisplay(in: timelineView.bounds)!
            timelineView.cacheDisplay(in: timelineView.bounds, to: openingBitmap)
            try! openingBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/openbor-launcher-integration/rewind-opening.png"))
            wait("rewind previews", timeout: 5) { timeline.isPresented && timeline.checkpoints.count >= 4 }
            precondition(timeline.checkpoints.allSatisfy { $0.image != nil }, "Every recorded state needs its matching preview")
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            timelineView.layoutSubtreeIfNeeded()
            let bitmap = timelineView.bitmapImageRepForCachingDisplay(in: timelineView.bounds)!
            timelineView.cacheDisplay(in: timelineView.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/openbor-launcher-integration/rewind-timeline.png"))
            let windowedSize = hostWindow.contentView!.bounds.size
            timeline.isFullscreen = true
            hostWindow.setContentSize(NSSize(width: 1280, height: 800))
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            timelineView.layoutSubtreeIfNeeded()
            let fullscreenBitmap = timelineView.bitmapImageRepForCachingDisplay(in: timelineView.bounds)!
            timelineView.cacheDisplay(in: timelineView.bounds, to: fullscreenBitmap)
            try! fullscreenBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/openbor-launcher-integration/rewind-fullscreen-layout.png"))
            timeline.isFullscreen = false
            hostWindow.setContentSize(windowedSize)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let pausedTime = try! coordinatorCapture(coordinator, window: hostWindow)
            precondition(timeline.selectedID == timeline.checkpoints.last?.id, "Open on the newest checkpoint at the right")
            sendKey(123, down: true, window: hostWindow)
            sendKey(123, down: false, window: hostWindow)
            precondition(timeline.selectedCheckpoint?.id == timeline.checkpoints[timeline.checkpoints.count - 2].id,
                         "Left must preview an older checkpoint without confirming")
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            precondition(try! coordinatorCapture(coordinator, window: hostWindow) == pausedTime, "Browsing must pause simulation")
            sendKey(53, down: true, window: hostWindow)
            sendKey(53, down: false, window: hostWindow)
            precondition(!timeline.isPresented, "Cancel must close the timeline")
            sendKey(preferences.rewindKey.keyCode, down: true, window: hostWindow)
            sendKey(preferences.rewindKey.keyCode, down: false, window: hostWindow)
            wait("reopened timeline", timeout: 5) { timeline.checkpoints.count >= 4 }
            let selected = timeline.checkpoints[3]
            timeline.selectedID = selected.id
            timeline.applySelected()
            wait("selected rewind checkpoint", timeout: 5) { !timeline.isPresented }
            let after = try! coordinatorCapture(coordinator, window: hostWindow)
            precondition(after < before, "Selected preview must move time backwards: \(before) -> \(after)")
            let backgroundBefore = captureManifest(coordinator)["background_travel"] as! Double
            RunLoop.main.run(until: Date().addingTimeInterval(3))
            precondition(try! coordinatorCapture(coordinator, window: hostWindow) > after, "Simulation must resume after selecting")
            let backgroundAfter = captureManifest(coordinator)["background_travel"] as! Double
            precondition((captureManifest(coordinator)["music_paused"] as! Int) == 0, "Music must be unpaused after restoring")
            precondition((captureManifest(coordinator)["music_volume"] as! Int) > 0, "Music must retain an audible volume")
            precondition(nativeLog().contains("[rewind] retained music"), "An unchanged song must not restart on rewind")
            precondition(nativeLog().contains("[rewind] music checkpoint restored=1"), "Rewind must restore the decoder and buffered music position")
            precondition(backgroundAfter > backgroundBefore && abs(backgroundAfter - backgroundBefore) < 1000, "Background must keep scrolling without clock overflow: \(backgroundBefore) -> \(backgroundAfter)")
            let xBefore = try! capturePlayerX(coordinator, window: hostWindow)
            sendKey(124, down: true, window: hostWindow)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            sendKey(124, down: false, window: hostWindow)
            let xAfter = try! capturePlayerX(coordinator, window: hostWindow)
            precondition(xAfter > xBefore, "Player input must work after rewind: \(xBefore) -> \(xAfter)")
            sendKey(0, down: true, window: hostWindow) // A: attack after rewind.
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            sendKey(0, down: false, window: hostWindow)
            precondition(coordinator.runtimeState == .running, "Attack after rewind must not crash")
            sendKey(preferences.rewindKey.keyCode, down: true, window: hostWindow)
            sendKey(preferences.rewindKey.keyCode, down: false, window: hostWindow)
            wait("continued rewind recording", timeout: 5) { timeline.isPresented && timeline.checkpoints.count >= 4 }
            precondition(!timeline.checkpoints.contains { $0.id == selected.id }, "The restored moment and its discarded future must not reappear as stale checkpoints")
            sendKey(53, down: true, window: hostWindow)
            sendKey(53, down: false, window: hostWindow)
            preferences.rewindEnabled = false
            print("PASS: preview timeline pauses, cancels, restores and resumes background scrolling, movement and attack.")
        }
        let shortcut = QuickMenuPreferences.shared.keyboard
        let modifiers: NSEvent.ModifierFlags = shortcut == .commandShiftM ? [.command, .shift] : []
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: hostWindow.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: shortcut.keyCode)!
            NSApplication.shared.sendEvent(event)
        }
        wait("quick menu", timeout: 5) { hostWindow.contentView?.subviews.contains { ($0 as? NSHostingView<QuickMenuView>)?.rootView.model.isPresented == true } == true }
        precondition((try? String(contentsOf: V2LaunchConfigurationFactory.quickMenuPauseURL()).trimmingCharacters(in: .whitespacesAndNewlines)) == "1")
        if let hold = ProcessInfo.processInfo.environment["TEST_MENU_HOLD"].flatMap(Double.init) {
            print("MENU READY FOR VISUAL CHECK")
            RunLoop.main.run(until: Date().addingTimeInterval(hold))
        }
        wait("capture support", timeout: 5) { coordinator.canCaptureLiveSaveState }
        coordinator.captureLiveSaveState()
        precondition(!coordinator.liveSaveStates.isEmpty, "Capture failed: \(coordinator.runtimeDiagnostics)")
        let slot = coordinator.liveSaveStates[0]
        let boot = try! String(contentsOf: V2LiveSaveStateStore().artifact(for: game.pakURL, slotID: slot.id).bootURL!)
        precondition(boot.hasPrefix("OPENBOR_V2_LIVE_BOOT_V8"))
        precondition(boot.contains("Lisa"), "Capture should include a live player, not just the title screen")
        precondition((try? String(contentsOf: V2LaunchConfigurationFactory.quickMenuPauseURL()).trimmingCharacters(in: .whitespacesAndNewlines)) == "1", "Capture must preserve menu pause")
        coordinator.suspendLiveSession()
        wait("suspend", timeout: 5) { coordinator.resumeSessionAvailable }
        let runningBackend = model.renderBackend
        model.renderBackend = runningBackend == .metal ? .openGL : .metal
        coordinator.sessionLaunchMode = .resumeSession
        coordinator.showHostWindow()
        wait("resume", timeout: 5) {
            coordinator.refreshSaveSlots()
            return !coordinator.resumeSessionAvailable
        }
        precondition(coordinator.runtimeDiagnostics.rendererName.contains(runningBackend == .openGL ? "OpenGL" : "Metal"), "Resume must keep the existing renderer")
        model.renderBackend = runningBackend
        coordinator.sessionLaunchMode = .loadLiveSaveState
        coordinator.selectedLiveSaveStateID = slot.id
        try? FileManager.default.removeItem(at: nativeLogURL())
        coordinator.showHostWindow()
        wait("savestate import", timeout: 20) {
            nativeLog().contains("[live-state] restored wave:") && coordinator.runtimeState == .running
        }
        precondition(coordinator.lastLaunchedSessionMode == .loadLiveSaveState)
        print("PASS: integrated launcher starts the V2 host, captures V8, suspends/resumes and launches a live slot.")
    }

    static func nativeLog() -> String {
        (try? String(contentsOf: nativeLogURL())) ?? ""
    }

    @MainActor
    static func captureManifest(_ coordinator: HostWindowCoordinator) -> [String: Any] {
        let artifact = try! V2LiveSaveStateStore().artifact(for: coordinator.selectedPakURL!, slotID: coordinator.liveSaveStates.first!.id)
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: artifact.manifestURL)) as! [String: Any]
    }

    @MainActor
    static func coordinatorCapture(_ coordinator: HostWindowCoordinator, window: NSWindow) throws -> Int {
        coordinator.captureLiveSaveState()
        let slot = coordinator.liveSaveStates.first!
        let artifact = try V2LiveSaveStateStore().artifact(for: coordinator.selectedPakURL!, slotID: slot.id)
        let boot = try String(contentsOf: artifact.bootURL!)
        return Int(boot.components(separatedBy: "\n")[1].components(separatedBy: "\t")[10])!
    }

    @MainActor
    static func sendKey(_ code: UInt16, down: Bool, window: NSWindow) {
        let event = NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: code == 0 ? "a" : "", charactersIgnoringModifiers: code == 0 ? "a" : "", isARepeat: false, keyCode: code)!
        NSApplication.shared.sendEvent(event)
    }

    @MainActor
    static func capturePlayerX(_ coordinator: HostWindowCoordinator, window: NSWindow) throws -> Float {
        _ = try coordinatorCapture(coordinator, window: window)
        let artifact = try V2LiveSaveStateStore().artifact(for: coordinator.selectedPakURL!, slotID: coordinator.liveSaveStates.first!.id)
        let boot = try String(contentsOf: artifact.bootURL!)
        let player = boot.components(separatedBy: "\n")[4].components(separatedBy: "\t")
        precondition(player[0] == "1", "Rewind must preserve a live player")
        return Float(player[11])!
    }

    static func nativeLogURL() -> URL {
        let resources = Bundle.main.resourceURL!
        precondition(resources.path.hasPrefix("/private/tmp/") || resources.path.hasPrefix("/tmp/"))
        return resources.appendingPathComponent("Engine/OpenBOR.app/Contents/Resources/Logs/OpenBorLog.txt")
    }

    @MainActor
    static func wait(_ label: String, timeout: TimeInterval, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        fatalError("Timeout: \(label)")
    }
}
