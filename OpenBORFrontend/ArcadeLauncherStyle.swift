import SwiftUI

enum LauncherLibraryLayout: String, CaseIterable, Identifiable {
    case sidebar
    case grid
    var id: String { rawValue }
    var title: String { UIStrings.text(self == .sidebar ? "Sidebar list" : "Centered grid") }
    var symbol: String { self == .sidebar ? "list.bullet" : "square.grid.2x2" }
}

struct ArcadeGameTitle: View {
    let title: String
    let size: CGFloat
    let hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !hovering || reduceMotion)) { timeline in
            let pulse = hovering && !reduceMotion ? (sin(timeline.date.timeIntervalSinceReferenceDate * 5) + 1) / 2 : 0
            Text(title)
                .font(.custom("Menlo-Bold", size: size))
                .foregroundStyle(hovering ? ArcadePalette.amber : ArcadePalette.cream)
                .offset(x: pulse * 3)
                .shadow(color: ArcadePalette.amber.opacity(hovering ? 0.25 + pulse * 0.4 : 0), radius: 3)
        }
        .allowsHitTesting(false)
    }
}

enum ArcadePalette {
    static let ink = Color(red: 0.094, green: 0.11, blue: 0.14)
    static let amber = Color(red: 0.98, green: 0.76, blue: 0.36)
    static let cream = Color(red: 0.94, green: 0.925, blue: 0.86)
}

struct ArcadeBackground: View {
    var paused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appActive = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused || reduceMotion || !appActive)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ArcadePalette.ink))
                let wave = (sin(time * 0.24) + 1) * 0.5
                let pulse = (sin(time * 0.48) + 1) * 0.5
                let drift = reduceMotion ? 0 : CGFloat(time.truncatingRemainder(dividingBy: 48))
                // Use the demo runtime's RGB waves and checkerboard, dimmed behind the UI.
                for row in -1...(Int(size.height / 48) + 1) {
                    for column in -1...(Int(size.width / 48) + 1) {
                        let x = CGFloat(column) * 48 + drift
                        let y = CGFloat(row) * 48
                        let fx = Double(max(0, x) / max(1, size.width))
                        let fy = Double(max(0, y) / max(1, size.height))
                        let blue = (row + column).isMultiple(of: 2) ? 0.32 : 0.16
                        let color = Color(red: 0.20 + 0.55 * fx + 0.20 * wave,
                                          green: 0.18 + 0.45 * fy + 0.22 * pulse,
                                          blue: blue + 0.25 * (1 - fy))
                        context.fill(Path(CGRect(x: x, y: y, width: 47, height: 47)), with: .color(color.opacity(0.18)))
                    }
                }
                for row in stride(from: 0, to: Int(size.height), by: 4) {
                    context.fill(Path(CGRect(x: 0, y: CGFloat(row), width: size.width, height: 1)), with: .color(.black.opacity(0.12)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in appActive = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in appActive = false }
        .onAppear { appActive = NSApplication.shared.isActive }
    }
}

struct ArcadeButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        ArcadeButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct ArcadeButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if prominent {
                TimelineView(.animation(minimumInterval: 0.15, paused: !hovering || reduceMotion)) { timeline in
                    let step = reduceMotion ? 0 : Int(timeline.date.timeIntervalSinceReferenceDate * 6) % 4
                    Text(">").offset(x: hovering ? CGFloat(step < 2 ? step : 3 - step) * 2 : 0)
                }
            }
            configuration.label
        }
        .font(.custom("Menlo-Bold", size: 11))
        .foregroundStyle(prominent ? ArcadePalette.ink : ArcadePalette.amber)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(prominent ? ArcadePalette.amber : ArcadePalette.ink.opacity(hovering ? 1 : 0.85))
        .overlay(Rectangle().strokeBorder(ArcadePalette.amber.opacity(hovering || prominent ? 1 : 0.4), lineWidth: 1).allowsHitTesting(false))
        .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct ArcadePanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ArcadePalette.ink.opacity(0.94))
            .overlay(Rectangle().strokeBorder(ArcadePalette.amber.opacity(0.35), lineWidth: 1).allowsHitTesting(false))
    }
}
