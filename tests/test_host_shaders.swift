import Foundation
import Metal
import simd

@main
struct HostShaderTest {
    static func main() throws {
        let suite = "OpenBOR.ShaderTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let game = URL(fileURLWithPath: "/tmp/game-a.pak")
        let other = URL(fileURLWithPath: "/tmp/game-b.pak")
        let prefs = HostShaderPreferences(defaults: defaults)
        precondition(prefs.resolved(for: game) == .off)
        prefs.saveGlobal(.scanlines, currentGame: game)
        precondition(prefs.resolved(for: game) == .scanlines)
        prefs.saveGame(.off, for: game)
        prefs.saveGame(.smooth, for: other)
        precondition(prefs.resolved(for: game) == .off)
        prefs.saveGlobal(.crtLite, currentGame: game)
        let reloaded = HostShaderPreferences(defaults: UserDefaults(suiteName: suite)!)
        precondition(reloaded.resolved(for: game) == .crtLite)
        precondition(reloaded.resolved(for: other) == .smooth)
        prefs.saveGame(nil, for: other)
        precondition(prefs.resolved(for: other) == .crtLite)

        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("A Metal device is required for shader validation")
        }
        let library = try device.makeLibrary(source: HostShaderPreset.metalSource, options: nil)
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.vertexFunction = library.makeFunction(name: "hostVertex")
        pipeline.fragmentFunction = library.makeFunction(name: "hostFragment")
        pipeline.colorAttachments[0].pixelFormat = .rgba8Unorm
        let state = try device.makeRenderPipelineState(descriptor: pipeline)
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 8, height: 8, mipmapped: false)
        inputDescriptor.storageMode = .shared
        inputDescriptor.usage = .shaderRead
        let input = device.makeTexture(descriptor: inputDescriptor)!
        let pixels: [UInt8] = Array(repeating: [180, 80, 40, 255], count: 64).flatMap { $0 }
        pixels.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 32) }
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 32, height: 32, mipmapped: false)
        outputDescriptor.storageMode = .shared
        outputDescriptor.usage = .renderTarget
        let output = device.makeTexture(descriptor: outputDescriptor)!
        let vertices: [SIMD2<Float>] = [SIMD2(-1, -1), SIMD2(0, 1), SIMD2(1, -1), SIMD2(1, 1), SIMD2(-1, 1), SIMD2(0, 0), SIMD2(1, 1), SIMD2(1, 0)]
        var results: [[UInt8]] = []
        for preset in HostShaderPreset.allCases {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let command = queue.makeCommandBuffer()!
            let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
            encoder.setRenderPipelineState(state)
            vertices.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
            let info: [UInt32] = [1, preset.metalID, 32, 32]
            info.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.setFragmentTexture(input, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            precondition(command.status == .completed, "GPU error: \(String(describing: command.error))")
            var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
            bytes.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: 128, from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0) }
            results.append(bytes)
        }
        let center = (16 * 32 + 16) * 4
        print("Center pixels:", results.map { Array($0[center..<center + 4]) })
        precondition(results[0][center] == 180 && results[0][center + 1] == 80)
        precondition(results[1] == results[0])
        precondition(results[2][center] < results[0][center])
        precondition(results[3] != results[2] && results[3][0] == 0)
        print("PASS: shader preferences persist with game precedence; all four presets compile and render on Metal.")
    }
}
