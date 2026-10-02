import AppKit
import IOSurface
import OpenGL.GL3

@available(macOS, deprecated: 10.14, message: "Compatibility renderer; Metal remains the default.")
private final class HostOpenGLView: NSOpenGLView {
    var onDraw: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func draw(_ dirtyRect: NSRect) { onDraw?() }
}

@available(macOS, deprecated: 10.14, message: "Compatibility renderer; Metal remains the default.")
final class OpenGLSurfaceViewController: NSViewController, HostSurfaceRendering {
    private var glView: HostOpenGLView?
    private var program: GLuint = 0
    private var texture: GLuint = 0
    private var vertexArray: GLuint = 0
    private var vertexBuffer: GLuint = 0
    private var textureSize = NSSize.zero
    private var latestFrame: EngineFramePacket?
    private weak var transport: EngineFrameTransport?
    private var refreshTimer: Timer?
    private var hasReceivedFrame = false
    var onFirstFrameReceived: (() -> Void)?
    var hostState: HostPresentationState = .windowed
    var shaderPreset: HostShaderPreset = .off { didSet { render() } }

    override func loadView() {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
            NSOpenGLPFADoubleBuffer, NSOpenGLPFAAccelerated,
            NSOpenGLPFAColorSize, 24, 0
        ].map { UInt32($0) }
        guard let format = NSOpenGLPixelFormat(attributes: attributes),
              let glView = HostOpenGLView(frame: .zero, pixelFormat: format) else {
            showFailure("OpenGL context unavailable")
            return
        }
        self.glView = glView
        glView.wantsLayer = true
        glView.wantsBestResolutionOpenGLSurface = true
        view = glView
        glView.openGLContext?.makeCurrentContext()
        var interval: GLint = 1
        glView.openGLContext?.setValues(&interval, for: .swapInterval)
        do { program = try HostOpenGLShader.makeProgram() }
        catch { showFailure(error.localizedDescription); return }
        glGenVertexArrays(1, &vertexArray)
        glGenBuffers(1, &vertexBuffer)
        glGenTextures(1, &texture)
        glView.onDraw = { [weak self] in self?.render() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.render() }
        if let refreshTimer { RunLoop.main.add(refreshTimer, forMode: .common) }
        try? "OpenGL host ready\n".write(to: V2LaunchConfigurationFactory.hostRenderLogURL(), atomically: true, encoding: .utf8)
    }

    deinit {
        refreshTimer?.invalidate()
        glView?.openGLContext?.makeCurrentContext()
        if texture != 0 { glDeleteTextures(1, &texture) }
        if vertexBuffer != 0 { glDeleteBuffers(1, &vertexBuffer) }
        if vertexArray != 0 { glDeleteVertexArrays(1, &vertexArray) }
        if program != 0 { glDeleteProgram(program) }
    }

    func attachTransport(_ transport: EngineFrameTransport) { self.transport = transport }
    func display(frame: EngineFramePacket) { latestFrame = frame; render() }
    func resetDisplay() { latestFrame = nil; textureSize = .zero; hasReceivedFrame = false; render(consumeFrame: false) }
    func hostWindowDidResize() { glView?.openGLContext?.update(); render() }
    func hostWindowDidChangePresentation() {
        hostWindowDidResize()
        DispatchQueue.main.async { [weak self] in self?.hostWindowDidResize() }
    }
    override func viewDidLayout() { super.viewDidLayout(); hostWindowDidResize() }

    private func showFailure(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.textColor = .systemOrange
        view = label
        NSLog("OpenBOR OpenGL: %@", message)
    }

    private func upload(_ pixels: UnsafeRawPointer, format: EngineVideoFormat, pitch: Int) {
        guard format.width > 0, format.height > 0, format.bytesPerPixel == 4 else { return }
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
        glPixelStorei(GLenum(GL_UNPACK_ROW_LENGTH), GLint(pitch / 4))
        let order = format.pixelFormatName.localizedCaseInsensitiveContains("BGRA") ? GLenum(GL_BGRA) : GLenum(GL_RGBA)
        if textureSize != NSSize(width: format.width, height: format.height) {
            textureSize = NSSize(width: format.width, height: format.height)
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, GLsizei(format.width), GLsizei(format.height), 0, order, GLenum(GL_UNSIGNED_BYTE), pixels)
        } else {
            glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0, GLsizei(format.width), GLsizei(format.height), order, GLenum(GL_UNSIGNED_BYTE), pixels)
        }
        glPixelStorei(GLenum(GL_UNPACK_ROW_LENGTH), 0)
        if !hasReceivedFrame {
            hasReceivedFrame = true
            try? "OpenGL host ready\nframe source=OpenGL format=\(format.width)x\(format.height)\n".write(to: V2LaunchConfigurationFactory.hostRenderLogURL(), atomically: true, encoding: .utf8)
            DispatchQueue.main.async { [weak self] in self?.onFirstFrameReceived?() }
        }
    }

    private func render(consumeFrame: Bool = true) {
        guard isViewLoaded, program != 0, let glView, let context = glView.openGLContext else { return }
        context.makeCurrentContext()
        if consumeFrame {
            if let frame = transport?.consumeLatestFrame() { latestFrame = frame }
            if let frame = latestFrame {
                let expected = frame.videoFormat.width * frame.videoFormat.height * 4
                if frame.bytes.count >= expected, expected > 0 {
                    frame.bytes.withUnsafeBytes { bytes in
                        if let pixels = bytes.baseAddress { upload(pixels, format: frame.videoFormat, pitch: frame.videoFormat.width * 4) }
                    }
                }
            } else if let snapshot = transport?.consumeIOSurfaceFrame() {
                IOSurfaceLock(snapshot.surface, .readOnly, nil)
                upload(IOSurfaceGetBaseAddress(snapshot.surface), format: snapshot.videoFormat, pitch: IOSurfaceGetBytesPerRow(snapshot.surface))
                IOSurfaceUnlock(snapshot.surface, .readOnly, nil)
            }
        }
        let size = glView.convertToBacking(glView.bounds).size
        guard size.width > 0, size.height > 0 else { return }
        glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
        glClearColor(0.05, 0.06, 0.08, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        if textureSize.width > 0, textureSize.height > 0 {
            var x: Float = 1, y: Float = 1
            let textureAspect = Float(textureSize.width / textureSize.height)
            let viewAspect = Float(size.width / size.height)
            let fullscreen = hostState == .fullscreen || hostState == .transitioningToFullscreen
            if textureAspect > viewAspect {
                let cover = textureAspect / viewAspect
                if fullscreen && (cover - 1) / cover <= 0.08 { x = cover }
                else { y = viewAspect / textureAspect }
            } else {
                let cover = viewAspect / textureAspect
                if fullscreen && (cover - 1) / cover <= 0.08 { y = cover }
                else { x = textureAspect / viewAspect }
            }
            let vertices: [Float] = [-x, -y, 0, 1, x, -y, 1, 1, -x, y, 0, 0, x, y, 1, 0]
            glUseProgram(program)
            glBindVertexArray(vertexArray)
            glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
            vertices.withUnsafeBytes { glBufferData(GLenum(GL_ARRAY_BUFFER), $0.count, $0.baseAddress, GLenum(GL_STREAM_DRAW)) }
            glEnableVertexAttribArray(0)
            glEnableVertexAttribArray(1)
            glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 16, nil)
            glVertexAttribPointer(1, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 16, UnsafeRawPointer(bitPattern: 8))
            glActiveTexture(GLenum(GL_TEXTURE0))
            glBindTexture(GLenum(GL_TEXTURE_2D), texture)
            let filter = shaderPreset == .off ? GL_NEAREST : GL_LINEAR
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), filter)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), filter)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
            glUniform1i(glGetUniformLocation(program, "frameTexture"), 0)
            glUniform1i(glGetUniformLocation(program, "preset"), GLint(shaderPreset.metalID))
            glUniform1f(glGetUniformLocation(program, "displayHeight"), Float(size.height) * y)
            glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
            glBindVertexArray(0)
        }
        context.flushBuffer()
    }
}
