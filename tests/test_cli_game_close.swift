import AppKit

@MainActor
final class GameCloseTestDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var closingGame = false
    private var endingNormalTest = false
    private let expectsCLIExit = ProcessInfo.processInfo.environment["EXPECT_CLI_EXIT"] == "1"
    private let usesRealEngine = ProcessInfo.processInfo.environment["TEST_REAL_ENGINE"] == "1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        precondition(model.isLaunchOnlyMode == expectsCLIExit)
        model.runtimeCoordinator.launchFullscreen = false
        if usesRealEngine {
            model.handleStartupLaunchIfNeeded()
        } else {
            model.runtimeCoordinator.runtimeMode = .mock
            model.runtimeCoordinator.showHostWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (usesRealEngine ? 8 : 0.5)) {
            precondition(model.runtimeCoordinator.runtimeState == .running)
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && $0.identifier == HostWindowController.windowIdentifier
            }) else { fatalError("Host window not found") }
            self.closingGame = true
            print("CLOSING_GAME \(Date().timeIntervalSince1970)")
            fflush(stdout)
            window.performClose(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                precondition(!self.expectsCLIExit, "CLI launcher remained alive after game close")
                self.endingNormalTest = true
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        precondition(closingGame)
        precondition(expectsCLIExit != endingNormalTest)
        print(expectsCLIExit ? "PASS: CLI game close terminates launcher" : "PASS: normal game close keeps launcher running")
        fflush(stdout)
    }
}

@main
struct CLIGameCloseTest {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = GameCloseTestDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
