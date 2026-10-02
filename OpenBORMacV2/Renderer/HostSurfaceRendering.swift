import AppKit

protocol HostSurfaceRendering: AnyObject {
    var hostState: HostPresentationState { get set }
    var shaderPreset: HostShaderPreset { get set }
    var onFirstFrameReceived: (() -> Void)? { get set }
    func display(frame: EngineFramePacket)
    func resetDisplay()
    func attachTransport(_ transport: EngineFrameTransport)
    func hostWindowDidResize()
    func hostWindowDidChangePresentation()
}
