import Foundation
import QuartzCore

final class MockOpenBORRuntime: EngineRuntime {
    private let frameTransport: EngineFrameTransport
    private(set) var state: EngineRuntimeState = .idle {
        didSet { onStateChange?(state) }
    }

    private(set) var diagnostics: EngineRuntimeDiagnostics = .empty
    let liveSaveStateSupport = EngineLiveSaveStateSupport(
        strategy: .unsupported,
        canCapture: false,
        canRestore: false,
        summary: "Il runtime demo non supporta live save state reali."
    )
    var onStateChange: ((EngineRuntimeState) -> Void)?
    var onFrame: ((EngineFramePacket) -> Void)?

    private var configuration: EngineLaunchConfiguration = .default
    private var timer: Timer?
    private var timebase: TimeInterval = 0
    private let frameSource = DemoFrameSource()

    init(frameTransport: EngineFrameTransport = InProcessFrameTransport()) {
        self.frameTransport = frameTransport
    }

    func prepare(configuration: EngineLaunchConfiguration) throws {
        self.configuration = configuration
        let bootstrapFormat = EngineVideoFormat(
            width: 960,
            height: 540,
            bytesPerPixel: 4,
            pixelFormatName: "RGBA8"
        )
        try frameTransport.prepareProducerSide(videoFormat: bootstrapFormat)
        diagnostics = EngineRuntimeDiagnostics(
            executableURL: nil,
            lastLaunchArguments: OpenBORLaunchArgumentBuilder.makeArguments(from: configuration),
            rendererName: configuration.useMetalRenderer ? "Metal (mock runtime)" : "Software (mock runtime)",
            lastErrorMessage: nil
        )
        state = .preparing
    }

    func start() throws {
        guard state == .preparing || state == .idle else { return }

        stopTimer()
        timebase = CACurrentMediaTime()
        state = .running

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.emitFrame()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        state = .stopping
        stopTimer()
        state = .idle
    }

    func suspend() {
        stopTimer()
    }

    func resume() {
        guard state == .running else { return }
        stopTimer()
        timebase = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.emitFrame()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func submitInput(_ snapshot: EngineInputSnapshot) {
        _ = snapshot
    }

    private func emitFrame() {
        guard state == .running else { return }

        let elapsed = CACurrentMediaTime() - timebase
        let image = frameSource.makeFrame(time: elapsed, drawableWidth: 960, drawableHeight: 540)
        let packet = EngineFramePacket(
            videoFormat: EngineVideoFormat(
                width: image.width,
                height: image.height,
                bytesPerPixel: 4,
                pixelFormatName: "RGBA8"
            ),
            timestamp: elapsed,
            bytes: Data(image.bytes)
        )
        try? frameTransport.publish(packet)
        onFrame?(packet)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        frameTransport.reset()
    }
}
