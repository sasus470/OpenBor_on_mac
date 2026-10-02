import Foundation
import OpenGL.GL3

@available(macOS, deprecated: 10.14, message: "Compatibility shaders; Metal remains the default.")
enum HostOpenGLShader {
    static let vertex = """
    #version 150
    in vec2 position;
    in vec2 uv;
    out vec2 texUV;
    void main() { gl_Position = vec4(position, 0.0, 1.0); texUV = uv; }
    """
    static let fragment = """
    #version 150
    uniform sampler2D frameTexture;
    uniform int preset;
    uniform float displayHeight;
    in vec2 texUV;
    out vec4 color;
    void main() {
        vec2 uv = texUV;
        vec2 p = uv * 2.0 - 1.0;
        if (preset == 3) {
            uv = (p * (1.0 + 0.025 * dot(p, p)) + 1.0) * 0.5;
            if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
                color = vec4(0.0, 0.0, 0.0, 1.0); return;
            }
        }
        vec3 rgb = texture(frameTexture, uv).rgb;
        if (preset >= 2) {
            float height = float(textureSize(frameTexture, 0).y);
            float strength = clamp(displayHeight / height - 1.0, 0.0, 1.0);
            float scan = 0.5 + 0.5 * cos(uv.y * height * 6.2831853);
            rgb *= 1.0 - strength * 0.22 * scan;
        }
        if (preset == 3) {
            int column = int(gl_FragCoord.x) % 3;
            vec3 mask = vec3(0.90); mask[column] = 1.0;
            rgb *= mask * (1.0 - 0.15 * dot(p, p));
        }
        color = vec4(rgb, 1.0);
    }
    """

    static func makeProgram() throws -> GLuint {
        func compile(_ source: String, type: GLenum) throws -> GLuint {
            let shader = glCreateShader(type)
            source.withCString { string in
                var pointer: UnsafePointer<GLchar>? = string
                glShaderSource(shader, 1, &pointer, nil)
            }
            glCompileShader(shader)
            var success: GLint = 0
            glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &success)
            if success == 0 {
                var log = [GLchar](repeating: 0, count: 4096)
                glGetShaderInfoLog(shader, 4096, nil, &log)
                glDeleteShader(shader)
                throw NSError(domain: "OpenBOR.OpenGL", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: log)])
            }
            return shader
        }
        let vs = try compile(vertex, type: GLenum(GL_VERTEX_SHADER))
        defer { glDeleteShader(vs) }
        let fs = try compile(fragment, type: GLenum(GL_FRAGMENT_SHADER))
        defer { glDeleteShader(fs) }
        let program = glCreateProgram()
        glAttachShader(program, vs)
        glAttachShader(program, fs)
        glBindAttribLocation(program, 0, "position")
        glBindAttribLocation(program, 1, "uv")
        glBindFragDataLocation(program, 0, "color")
        glLinkProgram(program)
        var success: GLint = 0
        glGetProgramiv(program, GLenum(GL_LINK_STATUS), &success)
        if success == 0 {
            var log = [GLchar](repeating: 0, count: 4096)
            glGetProgramInfoLog(program, 4096, nil, &log)
            glDeleteProgram(program)
            throw NSError(domain: "OpenBOR.OpenGL", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: log)])
        }
        return program
    }
}
