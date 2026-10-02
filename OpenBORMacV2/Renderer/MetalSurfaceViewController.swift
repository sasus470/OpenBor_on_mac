import AppKit
import Foundation
import IOSurface
import MetalKit
import simd

enum HostPresentationState {
    case windowed
    case transitioningToFullscreen
    case fullscreen
    case transitioningToWindowed
}

private struct HostVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

final class HostMetalView: MTKView {
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        _ = event
    }

    override func keyUp(with event: NSEvent) {
        _ = event
    }
}

final class MetalSurfaceViewController: NSViewController, MTKViewDelegate, HostSurfaceRendering {
    private let metalView = HostMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var texture: MTLTexture?
    private var textureSize: SIMD2<Int32> = .zero
    private var latestFrame: EngineFramePacket?
    private weak var transport: EngineFrameTransport?
    private var renderSourceLabel = "Packet"
    private var refreshTimer: Timer?
    private let hostRenderLogURL = V2LaunchConfigurationFactory.hostRenderLogURL()
    private var drawCount: Int = 0
    private var lastLoggedFrameSignature: String?
    var onFirstFrameReceived: (() -> Void)?
    private var hasReceivedFrame = false

    var hostState: HostPresentationState = .windowed
    var shaderPreset: HostShaderPreset = .off {
        didSet { requestRedraw() }
    }

    override func loadView() {
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0)
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.delegate = self
        metalView.preferredFramesPerSecond = 60
        metalView.framebufferOnly = true
        metalView.autoResizeDrawable = true
        commandQueue = metalView.device?.makeCommandQueue()
        pipelineState = buildPipeline(device: metalView.device)
        try? FileManager.default.removeItem(at: hostRenderLogURL)
        view = metalView
        startRefreshLoop()
        appendRenderLog("loadView")
        DispatchQueue.main.async { [weak self] in
            _ = self?.view.window?.makeFirstResponder(self?.metalView)
        }
    }

    deinit {
        stopRefreshLoop()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        refreshDrawableSize()
    }

    func hostWindowDidResize() {
        refreshDrawableSize()
    }

    func hostWindowDidChangePresentation() {
        refreshDrawableSize()
        DispatchQueue.main.async { [weak self] in
            self?.refreshDrawableSize()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.refreshDrawableSize()
        }
    }

    func display(frame: EngineFramePacket) {
        latestFrame = frame
        notifyFirstFrameReceived()
        logFrameIfNeeded(videoFormat: frame.videoFormat, source: "Display")
        requestRedraw()
    }

    func resetDisplay() {
        hasReceivedFrame = false
        latestFrame = nil
        texture = nil
        textureSize = .zero
        lastLoggedFrameSignature = nil
        appendRenderLog("resetDisplay")
        requestRedraw()
    }

    func attachTransport(_ transport: EngineFrameTransport) {
        self.transport = transport
    }

    func draw(in view: MTKView) {
        drawCount += 1
        refreshDrawableSizeIfNeeded()
        guard
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentRenderPassDescriptor,
            let commandQueue,
            let pipelineState
        else {
            if drawCount <= 5 || (drawCount % 120) == 0 {
                appendRenderLog("draw skipped currentDrawable=\(view.currentDrawable != nil) renderPass=\(view.currentRenderPassDescriptor != nil)")
            }
            return
        }

        updateTextureFromLatestFrame()
        if drawCount <= 5 || (drawCount % 120) == 0 {
            appendRenderLog("draw #\(drawCount) source=\(renderSourceLabel) texture=\(texture != nil) size=\(textureSize.x)x\(textureSize.y) drawable=\(Int(view.drawableSize.width))x\(Int(view.drawableSize.height))")
        }
        let vertices = makeVertices(drawableSize: view.drawableSize)

        let commandBuffer = commandQueue.makeCommandBuffer()
        let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: passDescriptor)
        encoder?.setRenderPipelineState(pipelineState)
        encoder?.setVertexBytes(vertices,
                                length: MemoryLayout<HostVertex>.stride * vertices.count,
                                index: 0)
        let verticesHeight = abs(vertices[2].position.y - vertices[0].position.y) * 0.5
        let hostInfo: [UInt32] = [texture == nil ? 0 : 1, shaderPreset.metalID,
                                  UInt32(max(1, view.drawableSize.width)),
                                  UInt32(max(1, Float(view.drawableSize.height) * verticesHeight))]
        hostInfo.withUnsafeBytes { bytes in
            encoder?.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        if let texture {
            encoder?.setFragmentTexture(texture, index: 0)
        }
        encoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        encoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _ = size
    }

    private func buildPipeline(device: MTLDevice?) -> MTLRenderPipelineState? {
        guard let device else { return nil }

        do {
            let library = try device.makeLibrary(source: HostShaderPreset.metalSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "hostVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "hostFragment")
            descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            assertionFailure("Failed to build Metal pipeline: \\(error)")
            return nil
        }
    }

    private func updateTextureFromLatestFrame() {
        guard let device = metalView.device else { return }
        if let transportedFrame = transport?.consumeLatestFrame() {
            latestFrame = transportedFrame
            notifyFirstFrameReceived()
        }
        if latestFrame == nil, let surfaceSnapshot = transport?.consumeIOSurfaceFrame() {
            updateTextureFromIOSurface(surfaceSnapshot, device: device)
            notifyFirstFrameReceived()
            return
        }
        guard let frame = latestFrame else { return }
        renderSourceLabel = "Packet"
        logFrameIfNeeded(videoFormat: frame.videoFormat, source: renderSourceLabel)

        if texture == nil ||
            textureSize.x != Int32(frame.videoFormat.width) ||
            textureSize.y != Int32(frame.videoFormat.height) {
            let pixelFormat: MTLPixelFormat = frame.videoFormat.pixelFormatName.localizedCaseInsensitiveContains("BGRA")
                ? .bgra8Unorm
                : .rgba8Unorm
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                      width: frame.videoFormat.width,
                                                                      height: frame.videoFormat.height,
                                                                      mipmapped: false)
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            texture = device.makeTexture(descriptor: descriptor)
            textureSize = SIMD2(Int32(frame.videoFormat.width), Int32(frame.videoFormat.height))
        }

        guard let texture else { return }

        frame.bytes.withUnsafeBytes { rawBuffer in
            texture.replace(region: MTLRegionMake2D(0, 0, frame.videoFormat.width, frame.videoFormat.height),
                            mipmapLevel: 0,
                            withBytes: rawBuffer.baseAddress!,
                            bytesPerRow: frame.videoFormat.width * frame.videoFormat.bytesPerPixel)
        }
    }

    private func startRefreshLoop() {
        stopRefreshLoop()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.requestRedraw()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    private func notifyFirstFrameReceived() {
        guard !hasReceivedFrame else { return }
        hasReceivedFrame = true
        // Window activation must occur outside Metal's draw callback.
        DispatchQueue.main.async { [weak self] in
            self?.onFirstFrameReceived?()
        }
    }

    private func stopRefreshLoop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func requestRedraw() {
        guard isViewLoaded else { return }
        refreshDrawableSizeIfNeeded()
        metalView.draw()
    }

    private func logFrameIfNeeded(videoFormat: EngineVideoFormat, source: String) {
        let signature = "\(source)-\(videoFormat.width)x\(videoFormat.height)-\(videoFormat.pixelFormatName)"
        guard lastLoggedFrameSignature != signature else { return }
        lastLoggedFrameSignature = signature
        appendRenderLog("frame source=\(source) format=\(videoFormat.width)x\(videoFormat.height) \(videoFormat.pixelFormatName)")
    }

    private func appendRenderLog(_ line: String) {
        let formatter = ISO8601DateFormatter()
        let text = "\(formatter.string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: hostRenderLogURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? text.write(to: hostRenderLogURL, atomically: true, encoding: .utf8)
        }
    }

    private func updateTextureFromIOSurface(_ snapshot: IOSurfaceFrameSnapshot, device: MTLDevice) {
        guard snapshot.videoFormat.width > 0, snapshot.videoFormat.height > 0 else {
            return
        }

        let pixelFormat: MTLPixelFormat = snapshot.videoFormat.pixelFormatName.localizedCaseInsensitiveContains("BGRA")
            ? .bgra8Unorm
            : .rgba8Unorm

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                  width: snapshot.videoFormat.width,
                                                                  height: snapshot.videoFormat.height,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        if let surfaceTexture = device.makeTexture(descriptor: descriptor, iosurface: snapshot.surface, plane: 0) {
            texture = surfaceTexture
            textureSize = SIMD2(Int32(snapshot.videoFormat.width), Int32(snapshot.videoFormat.height))
            renderSourceLabel = "IOSurface"
            logFrameIfNeeded(videoFormat: snapshot.videoFormat, source: renderSourceLabel)
        }
    }

    private func makeVertices(drawableSize: CGSize) -> [HostVertex] {
        guard textureSize.x > 0, textureSize.y > 0, drawableSize.width > 0, drawableSize.height > 0 else {
            return [
                HostVertex(position: SIMD2(-1, -1), uv: SIMD2(0, 1)),
                HostVertex(position: SIMD2( 1, -1), uv: SIMD2(1, 1)),
                HostVertex(position: SIMD2(-1,  1), uv: SIMD2(0, 0)),
                HostVertex(position: SIMD2( 1,  1), uv: SIMD2(1, 0))
            ]
        }

        let textureAspect = Float(textureSize.x) / Float(textureSize.y)
        let drawableAspect = Float(drawableSize.width) / Float(drawableSize.height)
        let prefersFullscreenFill = hostState == .fullscreen || hostState == .transitioningToFullscreen
        let maxCropFraction: Float = 0.08

        var scaleX: Float = 1.0
        var scaleY: Float = 1.0

        if textureAspect > drawableAspect {
            let coverScaleX = textureAspect / drawableAspect
            let cropFraction = (coverScaleX - 1.0) / coverScaleX
            if prefersFullscreenFill && cropFraction <= maxCropFraction {
                scaleX = coverScaleX
            } else {
                scaleY = drawableAspect / textureAspect
            }
        } else {
            let coverScaleY = drawableAspect / textureAspect
            let cropFraction = (coverScaleY - 1.0) / coverScaleY
            if prefersFullscreenFill && cropFraction <= maxCropFraction {
                scaleY = coverScaleY
            } else {
                scaleX = textureAspect / drawableAspect
            }
        }

        return [
            HostVertex(position: SIMD2(-scaleX, -scaleY), uv: SIMD2(0, 1)),
            HostVertex(position: SIMD2( scaleX, -scaleY), uv: SIMD2(1, 1)),
            HostVertex(position: SIMD2(-scaleX,  scaleY), uv: SIMD2(0, 0)),
            HostVertex(position: SIMD2( scaleX,  scaleY), uv: SIMD2(1, 0))
        ]
    }

    private func refreshDrawableSize() {
        let size = metalView.convertToBacking(metalView.bounds).size
        guard size.width > 0, size.height > 0 else { return }
        metalView.drawableSize = size
        metalView.setNeedsDisplay(metalView.bounds)
    }

    private func refreshDrawableSizeIfNeeded() {
        let size = metalView.convertToBacking(metalView.bounds).size
        guard size.width > 0, size.height > 0 else { return }
        guard metalView.drawableSize != size else { return }
        metalView.drawableSize = size
    }
}
