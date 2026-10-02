import AppKit

final class HostWindowCoordinator: ObservableObject {
    @Published var runtimeMode: EngineRuntimeMode = .mock
    @Published private(set) var availablePakURLs: [URL] = []
    @Published var selectedPakURL: URL? {
        didSet {
            refreshSaveSlots()
        }
    }
    @Published var sessionLaunchMode: V2SessionLaunchMode = .newSession
    @Published private(set) var resumeSessionAvailable = false
    @Published private(set) var savedProgressAvailable = false
    @Published private(set) var manualSaveStates: [V2SaveStateSlot] = []
    @Published private(set) var liveSaveStateSupported = false
    @Published private(set) var liveSaveStates: [V2LiveSaveStateSlot] = []
    @Published var selectedSaveStateID: String?
    @Published var selectedLiveSaveStateID: String?
    @Published private(set) var runtimeState: EngineRuntimeState = .idle
    @Published private(set) var runtimeDiagnostics: EngineRuntimeDiagnostics = .empty
    @Published private(set) var lastLaunchedPakURL: URL?
    @Published private(set) var lastLaunchedSessionMode: V2SessionLaunchMode = .newSession
    @Published private(set) var liveSessionControllable = false
    @Published private(set) var liveSaveStateStatusMessage = "Nessuna cattura live effettuata in questa sessione."
    private var windowController: HostWindowController?
    private var liveSuspendedPakURL: URL?
    private let saveStateStore = V2SaveStateStore()
    private let liveSaveStateStore = V2LiveSaveStateStore()
    private var previousRuntimeState: EngineRuntimeState = .idle
    private var activeLaunchSource: V2SaveStateStore.LaunchSource?
    var configureLaunch: ((EngineLaunchConfiguration) -> EngineLaunchConfiguration)?

    func shutdown() {
        if let pakURL = lastLaunchedPakURL, shouldPersistResumeSession(for: activeLaunchSource) {
            try? saveStateStore.persistSavedProgress(for: pakURL)
        }
        windowController?.shutdownRuntime()
        windowController = nil
    }

    init() {
        refreshAvailablePaks()
        refreshSaveSlots()
    }

    var canLaunchSelectedGame: Bool {
        if runtimeMode == .mock {
            return true
        }

        guard selectedPakURL != nil else { return false }

        switch sessionLaunchMode {
        case .newSession:
            return true
        case .resumeSession:
            return resumeSessionAvailable
        case .resumeProgress:
            return savedProgressAvailable
        case .loadSaveState:
            return selectedSaveStateID != nil
        case .loadLiveSaveState:
            return selectedLiveSaveStateID != nil
        }
    }

    var selectedGameDisplayName: String {
        lastLaunchedPakURL?.deletingPathExtension().lastPathComponent ??
        selectedPakURL?.deletingPathExtension().lastPathComponent ??
        "No game selected"
    }

    var runtimeStatusSummary: String {
        switch runtimeState {
        case .failed(let message):
            return message
        case .running:
            if runtimeMode == .mock {
                return "Host window active."
            }
            if runtimeMode == .bridge {
                return "Experimental bridge runtime launched. Watch the host window for real engine frames."
            }
            return "Embedded engine launched."
        case .preparing:
            return "Preparing runtime and launch configuration."
        case .stopping:
            return "Stopping current runtime."
        case .idle:
            return runtimeMode == .mock ? "Ready to open the host window." : "Ready to launch the selected game."
        }
    }

    var runtimeExecutableName: String {
        runtimeDiagnostics.executableURL?.lastPathComponent ?? "Not launched yet"
    }

    var runtimeArgumentsSummary: String {
        runtimeDiagnostics.lastLaunchArguments.isEmpty
            ? "No launch arguments recorded yet"
            : runtimeDiagnostics.lastLaunchArguments.joined(separator: " ")
    }

    var canCreateManualSaveState: Bool {
        selectedPakURL != nil && runtimeState == .idle && saveStateStore.workingStateExists(for: selectedPakURL)
    }

    var canDeleteSelectedSaveState: Bool {
        selectedPakURL != nil && selectedSaveStateID != nil
    }

    var diskSnapshotSummary: String {
        manualSaveStates.isEmpty
            ? "Non ci sono ancora snapshot disco manuali per questo gioco."
            : "Seleziona uno snapshot disco manuale da caricare."
    }

    var liveSaveStateSummary: String {
        if liveSaveStateSupported {
            return "Il live savestate ora include le variabili script per-entita. Crea una nuova cattura con questa build prima di provarne il caricamento."
        }
        return "I live save state tipo RetroArch sono ancora in preparazione. In questa build qui usiamo solo snapshot dei file di salvataggio su disco."
    }

    var canCaptureLiveSaveState: Bool {
        runtimeMode == .process &&
        windowController?.liveSaveStateSupportSnapshot.canCapture == true
    }

    var canSuspendLiveSession: Bool {
        runtimeMode == .process && liveSessionControllable
    }

    var sessionModeSummary: String {
        switch sessionLaunchMode {
        case .resumeSession:
            return resumeSessionAvailable
                ? "E disponibile una sessione live sospesa da riprendere esattamente da dove l'hai lasciata."
                : "Non esiste ancora una sessione live sospesa per questo gioco."
        case .resumeProgress:
            return savedProgressAvailable
                ? "E disponibile un salvataggio persistito da riaprire per questo gioco."
                : "Non esiste ancora un salvataggio persistito disponibile per questo gioco."
        case .loadSaveState:
            return diskSnapshotSummary
        case .loadLiveSaveState:
            return liveSaveStates.isEmpty
                ? "Crea prima un nuovo live savestate durante il gioco."
                : "Carica un nuovo live savestate creato con questa build."
        case .newSession:
            return sessionLaunchMode.detailText
        }
    }

    func refreshAvailablePaks() {
        let pakURLs = V2LaunchConfigurationFactory.availablePakURLs()
        availablePakURLs = pakURLs

        if let selectedPakURL, pakURLs.contains(selectedPakURL) {
            return
        }

        selectedPakURL = pakURLs.first
    }

    func refreshSaveSlots() {
        resumeSessionAvailable = hasLiveResumeSession(for: selectedPakURL)
        savedProgressAvailable = saveStateStore.savedProgressAvailable(for: selectedPakURL)
        manualSaveStates = saveStateStore.manualSaveStates(for: selectedPakURL)
        liveSaveStateSupported = liveSaveStateStore.supportsLiveSnapshots
        liveSaveStates = liveSaveStateStore.liveSaveStates(for: selectedPakURL)

        if selectedSaveStateID == nil ||
           !manualSaveStates.contains(where: { $0.id == selectedSaveStateID }) {
            selectedSaveStateID = manualSaveStates.first?.id
        }
        if selectedLiveSaveStateID == nil ||
           !liveSaveStates.contains(where: { $0.id == selectedLiveSaveStateID }) {
            selectedLiveSaveStateID = liveSaveStates.first?.id
        }
    }

    func showHostWindow() {
        do {
            closeStaleHostWindows()

            if runtimeMode == .process {
                if sessionLaunchMode == .resumeSession,
                   let windowController,
                   windowController.canResumeLiveSession(for: selectedPakURL) {
                    lastLaunchedPakURL = windowController.launchConfiguration.pakURL
                    lastLaunchedSessionMode = .resumeSession
                    activeLaunchSource = .resumeSession
                    liveSuspendedPakURL = nil
                    liveSessionControllable = true
                    runtimeState = windowController.runtimeStateSnapshot
                    runtimeDiagnostics = windowController.runtimeDiagnosticsSnapshot
                    windowController.presentWindow()
                    DispatchQueue.main.async { [weak self] in self?.refreshSaveSlots() }
                    return
                }

                let launchPlan = try makeLaunchPlan()
                let launchConfiguration = configureLaunch?(launchPlan.configuration) ?? launchPlan.configuration
                lastLaunchedPakURL = launchConfiguration.pakURL
                lastLaunchedSessionMode = launchPlan.sessionMode
                activeLaunchSource = launchPlan.source
                if launchPlan.sessionMode != .resumeSession {
                    liveSuspendedPakURL = nil
                }

                if let windowController,
                   windowController.runtimeMode == runtimeMode,
                   windowController.launchConfiguration.useMetalRenderer == launchConfiguration.useMetalRenderer {
                    liveSessionControllable = true
                    windowController.relaunch(with: launchConfiguration)
                    windowController.window?.center()
                    windowController.presentWindow()
                    return
                }

                if let windowController {
                    windowController.shutdownRuntime()
                    windowController.close()
                    self.windowController = nil
                }

                let windowController = HostWindowController(runtimeMode: runtimeMode, launchConfiguration: launchConfiguration)
                wire(windowController)
                self.windowController = windowController
                liveSessionControllable = true
                windowController.showWindow(nil)
                windowController.window?.center()
                windowController.presentWindow()
                return
            }

            let launchPlan = try makeLaunchPlan()
            let launchConfiguration = configureLaunch?(launchPlan.configuration) ?? launchPlan.configuration
            lastLaunchedPakURL = launchConfiguration.pakURL
            lastLaunchedSessionMode = launchPlan.sessionMode
            activeLaunchSource = launchPlan.source
            if launchPlan.sessionMode != .resumeSession {
                liveSuspendedPakURL = nil
            }

            if let windowController,
               windowController.runtimeMode == runtimeMode,
               windowController.launchConfiguration == launchConfiguration {
                windowController.showWindow(nil)
                windowController.presentWindow()
                return
            }

            if let windowController {
                windowController.shutdownRuntime()
                windowController.close()
                self.windowController = nil
            }

            let windowController = HostWindowController(runtimeMode: runtimeMode, launchConfiguration: launchConfiguration)
            wire(windowController)
            self.windowController = windowController
            liveSessionControllable = runtimeMode == .process
            windowController.showWindow(nil)
            windowController.window?.center()
            windowController.presentWindow()
        } catch {
            runtimeState = .failed(error.localizedDescription)
            runtimeDiagnostics.lastErrorMessage = error.localizedDescription
        }
    }

    func toggleFullscreen() {
        guard runtimeMode != .process else { return }
        showHostWindow()
        windowController?.toggleFullscreen()
    }

    func suspendLiveSession() {
        guard runtimeMode == .process else { return }
        guard let windowController else { return }
        lastLaunchedPakURL = windowController.launchConfiguration.pakURL
        lastLaunchedSessionMode = .resumeSession
        activeLaunchSource = .resumeSession
        liveSuspendedPakURL = windowController.launchConfiguration.pakURL?.standardizedFileURL
        windowController.suspendForResume()
        refreshSaveSlots()
    }

    func createManualSaveState() {
        guard let selectedPakURL else { return }

        do {
            let slot = try saveStateStore.createManualSaveState(for: selectedPakURL)
            refreshSaveSlots()
            selectedSaveStateID = slot.id
        } catch {
            runtimeState = .failed(error.localizedDescription)
            runtimeDiagnostics.lastErrorMessage = error.localizedDescription
        }
    }

    func deleteSelectedSaveState() {
        guard let selectedPakURL, let selectedSaveStateID else { return }

        do {
            try saveStateStore.deleteManualSaveState(for: selectedPakURL, slotID: selectedSaveStateID)
            refreshSaveSlots()
        } catch {
            runtimeState = .failed(error.localizedDescription)
            runtimeDiagnostics.lastErrorMessage = error.localizedDescription
        }
    }

    func captureLiveSaveState() {
        guard runtimeMode == .process else { return }
        guard let windowController else { return }

        do {
            let artifact = try windowController.captureLiveSaveState()
            try liveSaveStateStore.persistArtifact(artifact)
            refreshSaveSlots()
            liveSaveStateStatusMessage = "Cattura live salvata: \(artifact.title)"
        } catch {
            runtimeState = .failed(error.localizedDescription)
            runtimeDiagnostics.lastErrorMessage = error.localizedDescription
            liveSaveStateStatusMessage = error.localizedDescription
        }
    }

    private func wire(_ windowController: HostWindowController) {
        runtimeState = .idle
        runtimeDiagnostics = .empty
        liveSessionControllable = windowController.runtimeMode == .process
        windowController.onSuspendRequested = { [weak self] pakURL in
            guard let self, let pakURL else { return }
            self.liveSuspendedPakURL = pakURL.standardizedFileURL
            self.liveSessionControllable = true
            self.refreshSaveSlots()
        }
        windowController.onSuspended = { [weak self] in
            guard let self else { return }
            defer {
                self.presentPrimaryWindow()
                self.refreshSaveSlots()
            }

            guard let lastLaunchedPakURL else {
                return
            }
            self.liveSuspendedPakURL = lastLaunchedPakURL.standardizedFileURL

            guard self.shouldPersistResumeSession(for: self.activeLaunchSource) else {
                return
            }

            do {
                try self.saveStateStore.persistSavedProgress(for: lastLaunchedPakURL)
            } catch {
                self.runtimeDiagnostics.lastErrorMessage = error.localizedDescription
            }
        }
        windowController.onQuickMenuCaptured = { [weak self] in
            self?.refreshSaveSlots()
            self?.liveSaveStateStatusMessage = "Live savestate salvato dal menu rapido."
        }
        windowController.onQuickMenuLoadRequested = { [weak self, weak windowController] slotID in
            guard let self, let windowController,
                  let pakURL = windowController.launchConfiguration.pakURL else { return }
            let artifact = try self.liveSaveStateStore.artifact(for: pakURL, slotID: slotID)
            guard artifact.bootURL != nil else {
                throw NSError(domain: "OpenBORMacV2.QuickMenu", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: UIStrings.text("Invalid slot")])
            }
            let saves = try self.saveStateStore.prepareWorkingSaves(for: pakURL, source: .newSession)
            var configuration = V2LaunchConfigurationFactory.makeDefault(
                selectedPakURL: pakURL, savesDirectoryOverrideURL: saves,
                liveStateBootURL: artifact.bootURL, liveStateScriptURL: artifact.scriptURL,
                liveStateEntityVariablesURL: artifact.entityVariablesURL)
            self.lastLaunchedPakURL = pakURL
            self.lastLaunchedSessionMode = .loadLiveSaveState
            self.activeLaunchSource = .liveState(slotID)
            self.liveSuspendedPakURL = nil
            configuration = self.configureLaunch?(configuration) ?? configuration
            configuration.useMetalRenderer = windowController.launchConfiguration.useMetalRenderer
            windowController.relaunch(with: configuration)
            self.refreshSaveSlots()
        }
        windowController.onRuntimeStateChanged = { [weak self] state, diagnostics in
            guard let self else { return }
            let oldState = self.runtimeState
            self.previousRuntimeState = oldState
            self.runtimeState = state
            self.runtimeDiagnostics = diagnostics
            self.liveSessionControllable = self.windowController?.runtimeMode == .process
            self.handleRuntimeTransition(from: oldState, to: state)
        }
    }

    private struct LaunchPlan {
        let configuration: EngineLaunchConfiguration
        let source: V2SaveStateStore.LaunchSource
        let sessionMode: V2SessionLaunchMode
    }

    private func makeLaunchPlan() throws -> LaunchPlan {
        guard runtimeMode == .mock || selectedPakURL != nil else {
            return LaunchPlan(
                configuration: V2LaunchConfigurationFactory.makeDefault(selectedPakURL: selectedPakURL),
                source: .newSession,
                sessionMode: .newSession
            )
        }

        guard let selectedPakURL else {
            return LaunchPlan(
                configuration: V2LaunchConfigurationFactory.makeDefault(selectedPakURL: nil),
                source: .newSession,
                sessionMode: .newSession
            )
        }

        let launchSource: V2SaveStateStore.LaunchSource
        let sessionMode = sessionLaunchMode
        switch sessionLaunchMode {
        case .newSession:
            launchSource = .newSession
        case .resumeSession:
            launchSource = .resumeSession
        case .resumeProgress:
            launchSource = .resumeProgress
        case .loadSaveState:
            guard let selectedSaveStateID else {
                throw NSError(
                    domain: "OpenBORMacV2.HostWindowCoordinator",
                    code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "Seleziona un save state prima di lanciare il gioco."]
                )
            }
            launchSource = .manualState(selectedSaveStateID)
        case .loadLiveSaveState:
            guard let selectedLiveSaveStateID else {
                throw NSError(
                    domain: "OpenBORMacV2.HostWindowCoordinator",
                    code: 11,
                    userInfo: [NSLocalizedDescriptionKey: "Seleziona un live savestate prima di lanciare il gioco."]
                )
            }
            let artifact = try liveSaveStateStore.artifact(for: selectedPakURL, slotID: selectedLiveSaveStateID)
            guard artifact.bootURL != nil else {
                throw NSError(
                    domain: "OpenBORMacV2.HostWindowCoordinator",
                    code: 12,
                    userInfo: [NSLocalizedDescriptionKey: "Questo slot live e precedente al nuovo importatore e non contiene il payload di ripristino."]
                )
            }
            launchSource = .liveState(selectedLiveSaveStateID)
            let savesDirectoryURL = try saveStateStore.prepareWorkingSaves(for: selectedPakURL, source: .newSession)
            return LaunchPlan(
                configuration: V2LaunchConfigurationFactory.makeDefault(
                    selectedPakURL: selectedPakURL,
                    savesDirectoryOverrideURL: savesDirectoryURL,
                    liveStateBootURL: artifact.bootURL,
                    liveStateScriptURL: artifact.scriptURL,
                    liveStateEntityVariablesURL: artifact.entityVariablesURL
                ),
                source: launchSource,
                sessionMode: .loadLiveSaveState
            )
        }

        let savesDirectoryURL = try saveStateStore.prepareWorkingSaves(for: selectedPakURL, source: launchSource)
        return LaunchPlan(
            configuration: V2LaunchConfigurationFactory.makeDefault(
                selectedPakURL: selectedPakURL,
                savesDirectoryOverrideURL: savesDirectoryURL,
                autoResumeSavedGame: sessionMode == .resumeProgress
            ),
            source: launchSource,
            sessionMode: sessionMode
        )
    }

    private func handleRuntimeTransition(from oldState: EngineRuntimeState, to newState: EngineRuntimeState) {
        let wasRunning = {
            switch oldState {
            case .running, .stopping:
                return true
            default:
                return false
            }
        }()

        let isTerminalIdleLike = {
            switch newState {
            case .idle, .failed:
                return true
            default:
                return false
            }
        }()

        guard wasRunning, isTerminalIdleLike, let lastLaunchedPakURL else {
            return
        }

        defer {
            activeLaunchSource = nil
        }

        liveSessionControllable = false

        guard shouldPersistResumeSession(for: activeLaunchSource) else {
            refreshSaveSlots()
            return
        }

        do {
            try saveStateStore.persistSavedProgress(for: lastLaunchedPakURL)
            refreshSaveSlots()
        } catch {
            runtimeDiagnostics.lastErrorMessage = error.localizedDescription
        }
    }

    private func shouldPersistResumeSession(for launchSource: V2SaveStateStore.LaunchSource?) -> Bool {
        switch launchSource {
        case .newSession, .resumeSession, .resumeProgress, .liveState:
            return true
        case .manualState, .none:
            return false
        }
    }

    private func closeStaleHostWindows() {
        for window in NSApp.windows {
            guard window.identifier == HostWindowController.windowIdentifier else { continue }
            if window === windowController?.window { continue }
            window.orderOut(nil)
            window.close()
        }
    }

    private func presentPrimaryWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier != HostWindowController.windowIdentifier {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            break
        }
    }

    private func hasLiveResumeSession(for pakURL: URL?) -> Bool {
        guard let pakURL else { return false }
        return liveSuspendedPakURL == pakURL.standardizedFileURL
    }
}
