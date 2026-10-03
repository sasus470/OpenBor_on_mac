import AppKit
import GameController
import SwiftUI

final class HostRuntimeWindow: NSWindow {
    var interceptClose = false
    var onInterceptedClose: (() -> Void)?

    override func performClose(_ sender: Any?) {
        if interceptClose {
            onInterceptedClose?()
            return
        }

        super.performClose(sender)
    }
}

final class HostWindowController: NSWindowController, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("OpenBORMacV2.HostWindow")

    private let metalViewController: NSViewController & HostSurfaceRendering
    let runtimeMode: EngineRuntimeMode
    private(set) var launchConfiguration: EngineLaunchConfiguration
    private let session: EngineRuntimeSession
    private let runtime: EngineRuntime
    var onRuntimeStateChanged: ((EngineRuntimeState, EngineRuntimeDiagnostics) -> Void)?
    private var keyboardInputSnapshot = EngineInputSnapshot()
    private var controllerInputSnapshot = EngineInputSnapshot()
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var gameControllerObserversInstalled = false
    private var gameControllerObserverTokens: [NSObjectProtocol] = []
    private var hasShutDownRuntime = false
    private var allowWindowClose = false
    private(set) var isSuspended = false
    private(set) var suspendedPakURL: URL?
    private var pendingSuspendForResume = false
    private var focusLiveStateOnFirstFrame = false
    private var fullscreenEntryPending = false
    var onSuspendRequested: ((URL?) -> Void)?
    var onSuspended: (() -> Void)?
    var onWindowDismissed: (() -> Void)?
    var onQuickMenuLoadRequested: ((String) throws -> Void)?
    var onQuickMenuCaptured: (() -> Void)?
    private let quickMenu = QuickMenuModel()
    private var quickMenuView: NSHostingView<QuickMenuView>?
    private var quickMenuVisible = false
    private var controllerShortcutHeld = false
    private let rewindTimeline = RewindTimelineModel()
    private var rewindTimelineView: NSHostingView<RewindTimelineView>?
    private var rewindWasQuickMenu = false
    private var rewindResultTimer: Timer?
    private var menuControllerSnapshot = EngineInputSnapshot()

    init(runtimeMode: EngineRuntimeMode, launchConfiguration: EngineLaunchConfiguration) {
        if launchConfiguration.useMetalRenderer {
            self.metalViewController = MetalSurfaceViewController()
        } else {
            self.metalViewController = OpenGLSurfaceViewController()
        }
        self.runtimeMode = runtimeMode
        self.launchConfiguration = launchConfiguration
        self.session = EngineRuntimeFactory.makeSession(mode: runtimeMode)
        self.runtime = session.runtime
        let window = HostRuntimeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        switch runtimeMode {
        case .mock:
            window.title = "OpenBOR Runtime Host (Demo)"
        case .process:
            window.title = "OpenBOR Runtime Host (Embedded Engine)"
        case .bridge:
            window.title = "OpenBOR Runtime Host (Bridge Experimental)"
        }
        window.identifier = Self.windowIdentifier
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.minSize = NSSize(width: 640, height: 360)
        window.contentViewController = metalViewController

        super.init(window: window)
        window.delegate = self
        window.interceptClose = runtimeMode == .process
        window.onInterceptedClose = { [weak self] in
            self?.handleInterceptedClose()
        }
        installQuickMenu()
        applySavedShader()
        metalViewController.attachTransport(session.transport)
        wireRuntime()
        installInputMonitoring()
        installGameControllerSupport()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var runtimeStateSnapshot: EngineRuntimeState {
        runtime.state
    }

    var runtimeDiagnosticsSnapshot: EngineRuntimeDiagnostics {
        runtime.diagnostics
    }

    var canSuspendForResume: Bool {
        runtimeMode == .process && !hasShutDownRuntime && !isSuspended && runtime.state == .running
    }

    var liveSaveStateSupportSnapshot: EngineLiveSaveStateSupport {
        runtime.liveSaveStateSupport
    }

    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
    }

    func enterFullscreenIfNeeded() {
        guard let window, !window.styleMask.contains(.fullScreen), !fullscreenEntryPending else { return }
        fullscreenEntryPending = true
        // Enter after the launch has finished presenting and centering the host window.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fullscreenEntryPending = false
            guard let window = self.window, window.isVisible,
                  !self.hasShutDownRuntime, !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }

    func captureLiveSaveState() throws -> EngineLiveSaveStateArtifact {
        try runtime.captureLiveSaveState()
    }

    func startRuntimeWithoutShowingWindow() {
        _ = window
        startRuntimeIfNeeded()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        presentWindow()
        startRuntimeIfNeeded()
    }

    func presentWindow() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKey()
        window.makeFirstResponder(metalViewController.view)
        if isSuspended {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isSuspended else { return }
                self.runtime.resume()
                self.isSuspended = false
                self.suspendedPakURL = nil
            }
            return
        }
        isSuspended = false
        suspendedPakURL = nil
    }

    func relaunch(with launchConfiguration: EngineLaunchConfiguration) {
        closeRewindTimeline()
        dismissQuickMenu()
        self.launchConfiguration = launchConfiguration
        applySavedShader()
        isSuspended = false
        suspendedPakURL = nil
        clearBridgeInput()
        runtime.stop()
        metalViewController.resetDisplay()
        presentWindow()
        startRuntimeIfNeeded()
    }

    func shutdownRuntime() {
        guard !hasShutDownRuntime else { return }
        closeRewindTimeline()
        dismissQuickMenu()
        hasShutDownRuntime = true
        allowWindowClose = true
        (window as? HostRuntimeWindow)?.interceptClose = false
        isSuspended = false
        suspendedPakURL = nil
        clearBridgeInput()
        removeInputMonitoring()
        removeGameControllerObservers()
        runtime.stop()
        metalViewController.resetDisplay()
        window?.orderOut(nil)
    }

    func suspendForResume() {
        guard runtimeMode == .process, !hasShutDownRuntime else { return }
        guard !pendingSuspendForResume else { return }
        closeRewindTimeline()
        dismissQuickMenu()

        if let window, window.styleMask.contains(.fullScreen) {
            pendingSuspendForResume = true
            window.toggleFullScreen(nil)
            return
        }

        performSuspendForResumeNow()
    }

    private func performSuspendForResumeNow() {
        onSuspendRequested?(launchConfiguration.pakURL)
        runtime.suspend()
        isSuspended = true
        pendingSuspendForResume = false
        suspendedPakURL = launchConfiguration.pakURL
        clearBridgeInput()
        metalViewController.resetDisplay()
        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderOut(nil)
        }
        onSuspended?()
    }

    func canResumeLiveSession(for pakURL: URL?) -> Bool {
        runtimeMode == .process &&
        isSuspended &&
        suspendedPakURL == pakURL
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowWindowClose {
            return true
        }

        if runtimeMode == .process {
            suspendForResume()
            return false
        }

        return true
    }

    private func handleInterceptedClose() {
        if runtimeMode == .process, !allowWindowClose {
            suspendForResume()
            return
        }

        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        let wasActive = !hasShutDownRuntime
        shutdownRuntime()
        if wasActive { onWindowDismissed?() }
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        metalViewController.hostState = .transitioningToFullscreen
        metalViewController.hostWindowDidChangePresentation()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        rewindTimeline.isFullscreen = true
        metalViewController.hostState = .fullscreen
        metalViewController.hostWindowDidChangePresentation()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        metalViewController.hostState = .transitioningToWindowed
        metalViewController.hostWindowDidChangePresentation()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        rewindTimeline.isFullscreen = false
        metalViewController.hostState = .windowed
        metalViewController.hostWindowDidChangePresentation()
        if pendingSuspendForResume {
            DispatchQueue.main.async { [weak self] in
                self?.performSuspendForResumeNow()
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        metalViewController.hostWindowDidResize()
    }

    func windowDidResignKey(_ notification: Notification) {
        clearBridgeInput()
    }

    private func wireRuntime() {
        metalViewController.onFirstFrameReceived = { [weak self] in
            guard let self, self.focusLiveStateOnFirstFrame else { return }
            self.focusLiveStateOnFirstFrame = false
            guard !self.hasShutDownRuntime, !self.isSuspended,
                  self.window?.isVisible == true else { return }
            self.presentWindow()
        }
        runtime.onStateChange = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                self.onRuntimeStateChanged?(state, self.runtime.diagnostics)
            }
        }

        runtime.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self else { return }
                self.metalViewController.display(frame: frame)
            }
        }
    }

    private func startRuntimeIfNeeded() {
        guard runtime.state == .idle else { return }
        metalViewController.resetDisplay()
        // Engine startup may activate its internal window after the host.
        // Reclaim keyboard focus once rendering starts for a live restore.
        focusLiveStateOnFirstFrame = launchConfiguration.liveStateBootURL != nil

        do {
            try runtime.prepare(configuration: launchConfiguration)
            onRuntimeStateChanged?(runtime.state, runtime.diagnostics)
            try runtime.start()
            onRuntimeStateChanged?(runtime.state, runtime.diagnostics)
        } catch {
            onRuntimeStateChanged?(runtime.state, runtime.diagnostics)
            print("V2 mock runtime failed to start: \(error)")
        }
    }

    private func installInputMonitoring() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleBridgeKeyEvent(event, isPressed: true)
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return event }
            return self.handleBridgeKeyEvent(event, isPressed: false)
        }
    }

    private func removeInputMonitoring() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let keyUpMonitor {
            NSEvent.removeMonitor(keyUpMonitor)
            self.keyUpMonitor = nil
        }
    }

    private func handleBridgeKeyEvent(_ event: NSEvent, isPressed: Bool) -> NSEvent? {
        guard (runtimeMode == .bridge || runtimeMode == .process),
              let window,
              event.window === window
        else {
            return event
        }

        var handled = true

        if rewindTimeline.isPresented {
            if isPressed && !event.isARepeat {
                if QuickMenuPreferences.shared.rewindKey.matches(event) || event.keyCode == 53 { cancelRewindTimeline() }
                else {
                    switch event.keyCode {
                    case 123: rewindTimeline.move(-1)
                    case 124: rewindTimeline.move(1)
                    case 126: rewindTimeline.move(-1)
                    case 125: rewindTimeline.move(1)
                    case 36: rewindTimeline.applySelected()
                    default: break
                    }
                }
            }
            return nil
        }

        if runtimeMode == .process, QuickMenuPreferences.shared.rewindKey.matches(event),
           QuickMenuPreferences.shared.rewindKey != QuickMenuPreferences.shared.keyboard {
            if isPressed && !event.isARepeat { openRewindTimeline() }
            return nil
        }

        if runtimeMode == .process, QuickMenuPreferences.shared.keyboard.matches(event) {
            if isPressed && !event.isARepeat { toggleQuickMenu() }
            return nil
        }
        if quickMenuVisible {
            if isPressed && !event.isARepeat {
                switch event.keyCode {
                case 126: quickMenu.moveAction(-1)
                case 125: quickMenu.moveAction(1)
                case 123: quickMenu.moveSlot(-1)
                case 124: quickMenu.moveSlot(1)
                case 36: performQuickMenuAction(quickMenu.selectedAction)
                case 53: dismissQuickMenu()
                default: break
                }
            }
            return nil
        }


        switch event.keyCode {
        case 126:
            keyboardInputSnapshot.up = isPressed
        case 125:
            keyboardInputSnapshot.down = isPressed
        case 123:
            keyboardInputSnapshot.left = isPressed
        case 124:
            keyboardInputSnapshot.right = isPressed
        case 36:
            keyboardInputSnapshot.start = isPressed
        case 53:
            keyboardInputSnapshot.escape = isPressed
        default:
            handled = handleBridgeCharacter(event, isPressed: isPressed)
        }

        if handled {
            submitCombinedBridgeInput()
            return nil
        }

        return event
    }

    private func handleBridgeCharacter(_ event: NSEvent, isPressed: Bool) -> Bool {
        guard let character = event.charactersIgnoringModifiers?.lowercased().first else {
            return false
        }

        switch character {
        case "a":
            keyboardInputSnapshot.attack = isPressed
        case "s":
            keyboardInputSnapshot.attack2 = isPressed
        case "z":
            keyboardInputSnapshot.attack3 = isPressed
        case "x":
            keyboardInputSnapshot.attack4 = isPressed
        case "d":
            keyboardInputSnapshot.jump = isPressed
        case "f":
            keyboardInputSnapshot.special = isPressed
        default:
            return false
        }

        return true
    }

    private func clearBridgeInput() {
        guard runtimeMode == .bridge || runtimeMode == .process else { return }
        if runtimeMode == .process { QuickMenuPreferences.shared.publishRewind() }
        keyboardInputSnapshot = EngineInputSnapshot()
        controllerInputSnapshot = EngineInputSnapshot()
        submitCombinedBridgeInput()
    }

    private func submitCombinedBridgeInput() {
        runtime.submitInput(combinedBridgeInputSnapshot())
    }

    private func combinedBridgeInputSnapshot() -> EngineInputSnapshot {
        EngineInputSnapshot(
            up: keyboardInputSnapshot.up || controllerInputSnapshot.up,
            down: keyboardInputSnapshot.down || controllerInputSnapshot.down,
            left: keyboardInputSnapshot.left || controllerInputSnapshot.left,
            right: keyboardInputSnapshot.right || controllerInputSnapshot.right,
            attack: keyboardInputSnapshot.attack || controllerInputSnapshot.attack,
            attack2: keyboardInputSnapshot.attack2 || controllerInputSnapshot.attack2,
            attack3: keyboardInputSnapshot.attack3 || controllerInputSnapshot.attack3,
            attack4: keyboardInputSnapshot.attack4 || controllerInputSnapshot.attack4,
            jump: keyboardInputSnapshot.jump || controllerInputSnapshot.jump,
            special: keyboardInputSnapshot.special || controllerInputSnapshot.special,
            start: keyboardInputSnapshot.start || controllerInputSnapshot.start,
            escape: keyboardInputSnapshot.escape || controllerInputSnapshot.escape
        )
    }

    private func installGameControllerSupport() {
        guard !gameControllerObserversInstalled else { return }
        gameControllerObserversInstalled = true
        gameControllerObserverTokens.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.configureConnectedControllers()
        })
        gameControllerObserverTokens.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.controllerInputSnapshot = EngineInputSnapshot()
            self?.submitCombinedBridgeInput()
            self?.configureConnectedControllers()
        })
        configureConnectedControllers()
    }

    private func removeGameControllerObservers() {
        for token in gameControllerObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        gameControllerObserverTokens.removeAll()
        gameControllerObserversInstalled = false
    }

    private func configureConnectedControllers() {
        for controller in GCController.controllers() {
            if let extendedGamepad = controller.extendedGamepad {
                extendedGamepad.valueChangedHandler = { [weak self] _, _ in
                    self?.updateControllerSnapshot(from: controller)
                }
            } else if let microGamepad = controller.microGamepad {
                microGamepad.valueChangedHandler = { [weak self] _, _ in
                    self?.updateControllerSnapshot(from: controller)
                }
            }
        }
        updateControllerSnapshot(from: GCController.controllers().first)
    }

    private func updateControllerSnapshot(from controller: GCController?) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.updateControllerSnapshot(from: controller) }
            return
        }
        guard runtimeMode == .bridge || runtimeMode == .process else { return }

        let newSnapshot: EngineInputSnapshot
        if let extendedGamepad = controller?.extendedGamepad {
            let analogDirections = digitalDirections(from: extendedGamepad.leftThumbstick.xAxis.value,
                                                     y: extendedGamepad.leftThumbstick.yAxis.value)
            newSnapshot = EngineInputSnapshot(
                up: extendedGamepad.dpad.up.isPressed || analogDirections.up,
                down: extendedGamepad.dpad.down.isPressed || analogDirections.down,
                left: extendedGamepad.dpad.left.isPressed || analogDirections.left,
                right: extendedGamepad.dpad.right.isPressed || analogDirections.right,
                attack: extendedGamepad.buttonA.isPressed,
                attack2: extendedGamepad.buttonX.isPressed,
                attack3: extendedGamepad.leftShoulder.isPressed,
                attack4: extendedGamepad.rightShoulder.isPressed,
                jump: extendedGamepad.buttonB.isPressed,
                special: extendedGamepad.buttonY.isPressed,
                start: extendedGamepad.buttonMenu.isPressed || extendedGamepad.buttonOptions?.isPressed == true,
                escape: extendedGamepad.buttonHome?.isPressed == true
            )
        } else if let microGamepad = controller?.microGamepad {
            newSnapshot = EngineInputSnapshot(
                up: microGamepad.dpad.up.isPressed,
                down: microGamepad.dpad.down.isPressed,
                left: microGamepad.dpad.left.isPressed,
                right: microGamepad.dpad.right.isPressed,
                attack: microGamepad.buttonA.isPressed,
                jump: microGamepad.buttonX.isPressed,
                start: microGamepad.buttonMenu.isPressed
            )
        } else {
            newSnapshot = EngineInputSnapshot()
        }

        let shortcut = controller?.extendedGamepad.map { QuickMenuPreferences.shared.controller.isPressed(on: $0) } ?? false
        let shortcutPressed = shortcut && !controllerShortcutHeld
        controllerShortcutHeld = shortcut
        let previousMenuSnapshot = menuControllerSnapshot
        menuControllerSnapshot = newSnapshot
        if rewindTimeline.isPresented {
            guard window?.isKeyWindow == true else { return }
            if newSnapshot.up && !previousMenuSnapshot.up { rewindTimeline.move(-1) }
            if newSnapshot.down && !previousMenuSnapshot.down { rewindTimeline.move(1) }
            if newSnapshot.left && !previousMenuSnapshot.left { rewindTimeline.move(-1) }
            if newSnapshot.right && !previousMenuSnapshot.right { rewindTimeline.move(1) }
            if newSnapshot.jump && !previousMenuSnapshot.jump { cancelRewindTimeline() }
            else if newSnapshot.attack && !previousMenuSnapshot.attack { rewindTimeline.applySelected() }
            return
        }
        if runtimeMode == .process, window?.isKeyWindow == true, shortcutPressed {
            toggleQuickMenu()
            return
        }
        if quickMenuVisible {
            guard window?.isKeyWindow == true, !shortcut else { return }
            if newSnapshot.up && !previousMenuSnapshot.up { quickMenu.moveAction(-1) }
            if newSnapshot.down && !previousMenuSnapshot.down { quickMenu.moveAction(1) }
            if newSnapshot.left && !previousMenuSnapshot.left { quickMenu.moveSlot(-1) }
            if newSnapshot.right && !previousMenuSnapshot.right { quickMenu.moveSlot(1) }
            if newSnapshot.jump && !previousMenuSnapshot.jump { dismissQuickMenu() }
            else if newSnapshot.attack && !previousMenuSnapshot.attack { performQuickMenuAction(quickMenu.selectedAction) }
            return
        }
        guard !shortcut, window?.isKeyWindow == true else { return }
        guard newSnapshot != controllerInputSnapshot else { return }
        controllerInputSnapshot = newSnapshot
        submitCombinedBridgeInput()
    }

    private func digitalDirections(from x: Float, y: Float) -> (up: Bool, down: Bool, left: Bool, right: Bool) {
        let deadzone: Float = 0.5
        return (
            up: y > deadzone,
            down: y < -deadzone,
            left: x < -deadzone,
            right: x > deadzone
        )
    }

    private func installQuickMenu() {
        guard runtimeMode == .process else { return }
        let view = NSHostingView(rootView: QuickMenuView(model: quickMenu))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        metalViewController.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: metalViewController.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: metalViewController.view.trailingAnchor),
            view.topAnchor.constraint(equalTo: metalViewController.view.topAnchor),
            view.bottomAnchor.constraint(equalTo: metalViewController.view.bottomAnchor)
        ])
        quickMenuView = view
        quickMenu.onAction = { [weak self] in self?.performQuickMenuAction($0) }
        quickMenu.onShaderDirection = { [weak self] in self?.cycleShader($0) }
        let timelineView = NSHostingView(rootView: RewindTimelineView(model: rewindTimeline))
        timelineView.translatesAutoresizingMaskIntoConstraints = false
        timelineView.isHidden = true
        metalViewController.view.addSubview(timelineView)
        NSLayoutConstraint.activate([
            timelineView.leadingAnchor.constraint(equalTo: metalViewController.view.leadingAnchor),
            timelineView.trailingAnchor.constraint(equalTo: metalViewController.view.trailingAnchor),
            timelineView.topAnchor.constraint(equalTo: metalViewController.view.topAnchor),
            timelineView.bottomAnchor.constraint(equalTo: metalViewController.view.bottomAnchor)
        ])
        rewindTimelineView = timelineView
        rewindTimeline.onSelect = { [weak self] in self?.applyRewindCheckpoint($0) }
        rewindTimeline.onCancel = { [weak self] in self?.cancelRewindTimeline() }
    }

    private func applySavedShader() {
        metalViewController.shaderPreset = HostShaderPreferences().resolved(for: launchConfiguration.pakURL)
        quickMenu.shaderTitleKey = metalViewController.shaderPreset.titleKey
        quickMenu.hasGame = launchConfiguration.pakURL != nil
        quickMenu.shaderScopeKey = HostShaderPreferences().gameOverride(for: launchConfiguration.pakURL) == nil ? "Global default" : "Game default"
    }

    private func cycleShader(_ direction: Int) {
        let presets = HostShaderPreset.allCases
        let index = presets.firstIndex(of: metalViewController.shaderPreset) ?? 0
        metalViewController.shaderPreset = presets[(index + direction + presets.count) % presets.count]
        quickMenu.shaderTitleKey = metalViewController.shaderPreset.titleKey
        quickMenu.shaderScopeKey = "Session only"
        quickMenu.status = UIStrings.text("Shader applied: %@", quickMenu.shaderTitle)
    }

    private func refreshQuickMenuSlots() {
        quickMenu.slots = V2LiveSaveStateStore().liveSaveStates(for: launchConfiguration.pakURL)
        if !quickMenu.slots.contains(where: { $0.id == quickMenu.selectedSlotID }) {
            quickMenu.selectedSlotID = quickMenu.slots.first?.id
        }
    }

    private func toggleQuickMenu() {
        if rewindTimeline.isPresented { cancelRewindTimeline(); return }
        if quickMenuVisible { dismissQuickMenu(); return }
        guard canSuspendForResume else { return }
        clearBridgeInput()
        runtime.setQuickMenuPaused(true)
        refreshQuickMenuSlots()
        quickMenu.status = ""
        quickMenu.resetSelection()
        quickMenuVisible = true
        quickMenu.isPresented = true
        quickMenuView?.isHidden = false
    }

    func dismissQuickMenu() {
        guard quickMenuVisible else { return }
        quickMenuVisible = false
        quickMenu.isPresented = false
        quickMenuView?.isHidden = true
        clearBridgeInput()
        runtime.setQuickMenuPaused(false)
        window?.makeFirstResponder(metalViewController.view)
    }

    private func performQuickMenuAction(_ action: Int) {
        do {
            switch action {
            case 0: dismissQuickMenu()
            case 1:
                let artifact = try runtime.captureLiveSaveState()
                try V2LiveSaveStateStore().persistArtifact(artifact)
                refreshQuickMenuSlots()
                quickMenu.selectedSlotID = quickMenu.slots.first?.id
                quickMenu.status = UIStrings.text("Capture saved: %@", artifact.title)
                onQuickMenuCaptured?()
            case 2:
                guard let slot = quickMenu.selectedSlotID else { return }
                try onQuickMenuLoadRequested?(slot)
            case 3, 5: suspendForResume()
            case 4: toggleFullscreen()
            case 6: cycleShader(1)
            case 7:
                guard let pakURL = launchConfiguration.pakURL else { return }
                HostShaderPreferences().saveGame(metalViewController.shaderPreset, for: pakURL)
                quickMenu.shaderScopeKey = "Game default"
                quickMenu.status = UIStrings.text("Game shader saved")
            case 8:
                HostShaderPreferences().saveGlobal(metalViewController.shaderPreset, currentGame: launchConfiguration.pakURL)
                quickMenu.shaderScopeKey = "Global default"
                quickMenu.status = UIStrings.text("Global shader saved")
            case 9:
                guard let pakURL = launchConfiguration.pakURL else { return }
                HostShaderPreferences().saveGame(nil, for: pakURL)
                applySavedShader()
                quickMenu.status = UIStrings.text("Game follows global")
            case 10:
                QuickMenuPreferences.shared.rewindEnabled.toggle()
            case 11:
                openRewindTimeline()
            default: break
            }
        } catch {
            quickMenu.status = error.localizedDescription
        }
    }

    private func openRewindTimeline() {
        guard canSuspendForResume, !rewindTimeline.isPresented else { return }
        rewindWasQuickMenu = quickMenuVisible
        clearBridgeInput()
        runtime.setQuickMenuPaused(true)
        quickMenuVisible = false
        quickMenu.isPresented = false
        quickMenuView?.isHidden = true
        rewindTimeline.checkpoints = []
        rewindTimeline.selectedID = nil
        rewindTimeline.isFullscreen = window?.styleMask.contains(.fullScreen) == true
        rewindTimeline.isLoadingHistory = true
        rewindTimeline.status = ""
        rewindTimeline.isPresented = true
        rewindTimeline.opened()
        rewindTimelineView?.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.rewindTimeline.isPresented else { return }
            self.rewindTimeline.checkpoints = RewindCheckpoint.loadHistory()
            self.rewindTimeline.selectedID = self.rewindTimeline.checkpoints.last?.id
            self.rewindTimeline.isLoadingHistory = false
            self.rewindTimeline.status = ""
        }
    }

    private func closeRewindTimeline(resumeGame: Bool = true) {
        guard rewindTimeline.isPresented else { return }
        rewindResultTimer?.invalidate()
        rewindResultTimer = nil
        try? FileManager.default.removeItem(at: V2LaunchConfigurationFactory.rewindDirectoryURL().appendingPathComponent("selection.txt"))
        rewindTimeline.isPresented = false
        rewindTimeline.isApplying = false
        rewindTimeline.isLoadingHistory = false
        rewindTimelineView?.isHidden = true
        rewindTimeline.checkpoints = []
        clearBridgeInput()
        if resumeGame { runtime.setQuickMenuPaused(false) }
        window?.makeFirstResponder(metalViewController.view)
    }

    private func cancelRewindTimeline() {
        guard !rewindTimeline.isApplying else { return }
        let returnToQuickMenu = rewindWasQuickMenu
        closeRewindTimeline(resumeGame: !returnToQuickMenu)
        if returnToQuickMenu { toggleQuickMenu() }
    }

    private func applyRewindCheckpoint(_ id: UInt64) {
        guard rewindTimeline.isPresented, !rewindTimeline.isApplying else { return }
        let directory = V2LaunchConfigurationFactory.rewindDirectoryURL()
        let resultURL = directory.appendingPathComponent("result.txt")
        do {
            try? FileManager.default.removeItem(at: resultURL)
            try String(id).write(to: directory.appendingPathComponent("selection.txt"), atomically: true, encoding: .utf8)
        } catch {
            rewindTimeline.status = error.localizedDescription
            return
        }
        rewindTimeline.isApplying = true
        rewindTimeline.status = UIStrings.text("Restoring checkpoint")
        let deadline = Date().addingTimeInterval(3)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
            guard let self, self.rewindTimeline.isPresented else { timer.invalidate(); return }
            let result = (try? String(contentsOf: resultURL).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            if result == "ok \(id)" {
                timer.invalidate()
                self.closeRewindTimeline()
            } else if result == "error \(id)" || Date() >= deadline {
                timer.invalidate()
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("selection.txt"))
                self.rewindTimeline.isApplying = false
                self.rewindTimeline.status = UIStrings.text("Checkpoint unavailable")
            }
        }
        rewindResultTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
