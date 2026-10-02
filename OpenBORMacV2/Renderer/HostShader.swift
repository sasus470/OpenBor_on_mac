import Foundation

enum HostShaderPreset: String, CaseIterable, Identifiable {
    case off, smooth, scanlines
    case crtLite = "crt-lite"

    var id: String { rawValue }
    var metalID: UInt32 { UInt32(Self.allCases.firstIndex(of: self)!) }
    var title: String { UIStrings.text(titleKey) }
    var titleKey: String {
        switch self {
        case .off: return "Original"
        case .smooth: return "Bilinear"
        case .scanlines: return "Scanlines"
        case .crtLite: return "CRT Lite"
        }
    }

    static let metalSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct VertexIn { float2 position; float2 uv; };
    struct VertexOut { float4 position [[position]]; float2 uv; };
    vertex VertexOut hostVertex(const device VertexIn *vertices [[buffer(0)]], uint vid [[vertex_id]]) {
        VertexOut out;
        out.position = float4(vertices[vid].position, 0.0, 1.0);
        out.uv = vertices[vid].uv;
        return out;
    }
    struct HostInfo { uint useTexture; uint preset; uint width; uint height; };
    fragment float4 hostFragment(VertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]], constant HostInfo& info [[buffer(0)]]) {
        if (!info.useTexture) return float4(0.11, 0.12, 0.15, 1.0);
        constexpr sampler pixel(address::clamp_to_edge, filter::nearest);
        constexpr sampler smooth(address::clamp_to_edge, filter::linear);
        float2 uv = in.uv;
        if (info.preset == 0) return tex.sample(pixel, uv);
        if (info.preset == 1) return tex.sample(smooth, uv);
        float2 p = uv * 2.0 - 1.0;
        if (info.preset == 3) {
            uv = (p * (1.0 + 0.025 * dot(p, p)) + 1.0) * 0.5;
            if (any(uv < 0.0) || any(uv > 1.0)) return float4(0.0, 0.0, 0.0, 1.0);
        }
        float3 color = tex.sample(smooth, uv).rgb;
        // Suppress subpixel scanlines at native size to avoid moire while resizing.
        float sourceHeight = float(tex.get_height());
        float strength = clamp(float(info.height) / sourceHeight - 1.0, 0.0, 1.0);
        float scan = 0.5 + 0.5 * cos(uv.y * sourceHeight * 6.2831853);
        color *= 1.0 - strength * 0.22 * scan;
        if (info.preset == 3) {
            uint column = uint(in.position.x) % 3;
            float3 mask = float3(0.90);
            mask[column] = 1.0;
            color *= mask * (1.0 - 0.15 * dot(p, p));
        }
        return float4(color, 1.0);
    }
    """
}

struct HostShaderPreferences {
    private let defaults: UserDefaults
    private let globalKey = "hostShader.global"
    private let gamesKey = "hostShader.games"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var global: HostShaderPreset {
        HostShaderPreset(rawValue: defaults.string(forKey: globalKey) ?? "") ?? .off
    }

    private func key(for pakURL: URL) -> String { pakURL.standardizedFileURL.path }

    func gameOverride(for pakURL: URL?) -> HostShaderPreset? {
        guard let pakURL, let raw = defaults.dictionary(forKey: gamesKey)?[key(for: pakURL)] as? String else { return nil }
        return HostShaderPreset(rawValue: raw)
    }

    func resolved(for pakURL: URL?) -> HostShaderPreset { gameOverride(for: pakURL) ?? global }

    func saveGame(_ preset: HostShaderPreset?, for pakURL: URL) {
        var games = defaults.dictionary(forKey: gamesKey) ?? [:]
        games[key(for: pakURL)] = preset?.rawValue
        defaults.set(games, forKey: gamesKey)
    }

    func saveGlobal(_ preset: HostShaderPreset, currentGame: URL?) {
        defaults.set(preset.rawValue, forKey: globalKey)
        // The current game should inherit the newly chosen global default.
        if let currentGame { saveGame(nil, for: currentGame) }
    }
}
