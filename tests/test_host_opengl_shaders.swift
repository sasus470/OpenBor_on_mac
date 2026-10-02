import AppKit
import OpenGL.GL3

@main
struct OpenGLShaderTest {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let attributes: [UInt32] = [NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core, NSOpenGLPFAAccelerated, NSOpenGLPFAColorSize, 24, 0].map { UInt32($0) }
        let format = NSOpenGLPixelFormat(attributes: attributes)!
        let context = NSOpenGLContext(format: format, share: nil)!
        context.makeCurrentContext()
        let program = try HostOpenGLShader.makeProgram()
        defer { glDeleteProgram(program) }
        var vao: GLuint = 0, buffer: GLuint = 0, input: GLuint = 0, output: GLuint = 0, fbo: GLuint = 0
        glGenVertexArrays(1, &vao)
        glGenBuffers(1, &buffer)
        glGenTextures(1, &input)
        glGenTextures(1, &output)
        glGenFramebuffers(1, &fbo)
        defer {
            glDeleteVertexArrays(1, &vao); glDeleteBuffers(1, &buffer)
            glDeleteTextures(1, &input); glDeleteTextures(1, &output); glDeleteFramebuffers(1, &fbo)
        }
        let pixels: [UInt8] = Array(repeating: [180, 80, 40, 255], count: 64).flatMap { $0 }
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), input)
        pixels.withUnsafeBytes { glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, 8, 8, 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress) }
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        glBindTexture(GLenum(GL_TEXTURE_2D), output)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA8, 32, 32, 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), output, 0)
        precondition(glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE))
        glViewport(0, 0, 32, 32)
        let vertices: [Float] = [-1, -1, 0, 1, 1, -1, 1, 1, -1, 1, 0, 0, 1, 1, 1, 0]
        glBindVertexArray(vao)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), buffer)
        vertices.withUnsafeBytes { glBufferData(GLenum(GL_ARRAY_BUFFER), $0.count, $0.baseAddress, GLenum(GL_STATIC_DRAW)) }
        glEnableVertexAttribArray(0); glEnableVertexAttribArray(1)
        glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 16, nil)
        glVertexAttribPointer(1, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 16, UnsafeRawPointer(bitPattern: 8))
        glUseProgram(program)
        glUniform1i(glGetUniformLocation(program, "frameTexture"), 0)
        glUniform1f(glGetUniformLocation(program, "displayHeight"), 32)
        glBindTexture(GLenum(GL_TEXTURE_2D), input)
        var results: [[UInt8]] = []
        for preset in HostShaderPreset.allCases {
            let filter = preset == .off ? GL_NEAREST : GL_LINEAR
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), filter)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), filter)
            glUniform1i(glGetUniformLocation(program, "preset"), GLint(preset.metalID))
            glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
            var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
            bytes.withUnsafeMutableBytes { glReadPixels(0, 0, 32, 32, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress) }
            results.append(bytes)
            precondition(glGetError() == GLenum(GL_NO_ERROR))
        }
        let center = (16 * 32 + 16) * 4
        precondition(results[0][center] == 180 && results[0][center + 1] == 80)
        precondition(results[1] == results[0])
        precondition(results[2][center] < results[0][center])
        precondition(results[3] != results[2] && results[3][0] == 0)
        print("PASS: all four presets compile and render correctly through an actual OpenGL 3.2 context.")
    }
}
