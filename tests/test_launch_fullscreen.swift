import AppKit

@main
struct LaunchFullscreenTest {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.regular)
        for useMetal in [true, false] {
            let coordinator = HostWindowCoordinator()
            coordinator.configureLaunch = { configuration in
                var result = configuration
                result.useMetalRenderer = useMetal
                return result
            }
            coordinator.showHostWindow()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.identifier == HostWindowController.windowIdentifier }) else {
                fatalError("Missing host window")
            }
            precondition(!window.styleMask.contains(.fullScreen))
            coordinator.launchFullscreen = true
            coordinator.showHostWindow()
            RunLoop.main.run(until: Date().addingTimeInterval(3))
            precondition(window.styleMask.contains(.fullScreen), "Fullscreen launch failed, Metal: \(useMetal)")
            // Repeated launches must not toggle an already-fullscreen window back out.
            coordinator.showHostWindow()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            precondition(window.styleMask.contains(.fullScreen))
            window.toggleFullScreen(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            coordinator.shutdown()
            window.close()
        }
        print("PASS: windowed and fullscreen launch, repeated launch, Metal and OpenGL")
    }
}
