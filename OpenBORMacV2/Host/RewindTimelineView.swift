import AppKit
import SwiftUI

struct RewindCheckpoint: Identifiable {
    let id: UInt64
    let age: Double
    let image: NSImage?

    static func loadHistory(directory: URL = V2LaunchConfigurationFactory.rewindDirectoryURL()) -> [Self] {
        guard let text = try? String(contentsOf: directory.appendingPathComponent("index.txt")) else { return [] }
        let rows = text.split(separator: "\n").map { $0.split(separator: " ") }
        guard let header = rows.first, header.count == 2,
              let now = Double(header[0]), let speed = Double(header[1]), speed > 0 else { return [] }
        let history: [Self] = rows.dropFirst().prefix(30).compactMap { fields in
            guard fields.count == 3, let id = UInt64(fields[0]), let slot = Int(fields[1]),
                  (0..<30).contains(slot), let time = Double(fields[2]) else { return nil }
            let path = directory.appendingPathComponent(String(format: "frame-%02d", slot))
            return Self(id: id, age: max(0, (now - time) / speed), image: preview(path))
        }
        return history.sorted { $0.id < $1.id }
    }

    private static func preview(_ path: URL) -> NSImage? {
        // OpenBOR's high byte is unused, not transparency.
        guard let info = try? String(contentsOfFile: path.path + ".info") else { return nil }
        let fields = info.split(whereSeparator: \.isWhitespace)
        guard fields.count == 4, let width = Int(fields[0]), let height = Int(fields[1]),
              (1...4096).contains(width), (1...4096).contains(height), fields[2] == "4", fields[3] == "BGRA8",
              let data = try? Data(contentsOf: URL(fileURLWithPath: path.path + ".preview")), data.count >= width * height * 4,
              let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}

final class RewindTimelineModel: ObservableObject {
    @Published var checkpoints: [RewindCheckpoint] = []
    @Published var selectedID: UInt64?
    @Published var isPresented = false
    @Published var isApplying = false
    @Published var isLoadingHistory = false
    @Published var isFullscreen = false
    @Published var status = ""
    @Published private(set) var navigationRevision = 0
    var onSelect: ((UInt64) -> Void)?
    var onCancel: (() -> Void)?
    var playsSounds = true
    private var lastPointerPosition = NSEvent.mouseLocation
    private lazy var openingSound = RewindMenuSound.make(duration: 0.38, start: 880, end: 220)
    private lazy var navigationSound = RewindMenuSound.make(duration: 0.09, start: 740, end: 980)
    var selectedCheckpoint: RewindCheckpoint? { checkpoints.first { $0.id == selectedID } }
    var showsEmptyHistory: Bool { !isLoadingHistory && checkpoints.isEmpty }
    func opened() {
        lastPointerPosition = NSEvent.mouseLocation
        if playsSounds { openingSound?.stop(); openingSound?.play() }
    }
    func hover(_ id: UInt64) {
        let position = NSEvent.mouseLocation
        guard position != lastPointerPosition else { return }
        lastPointerPosition = position
        select(id)
    }
    private func playNavigationSound() {
        if playsSounds { navigationSound?.stop(); navigationSound?.play() }
    }
    func select(_ id: UInt64, scroll: Bool = false, sound: Bool = true) {
        guard !isApplying, id != selectedID, checkpoints.contains(where: { $0.id == id }) else { return }
        selectedID = id
        if scroll { navigationRevision += 1 }
        if sound { playNavigationSound() }
    }
    func move(_ delta: Int) {
        guard !checkpoints.isEmpty, !isApplying else { return }
        // Scrolling under a stationary mouse must not override keyboard focus.
        lastPointerPosition = NSEvent.mouseLocation
        let index = checkpoints.firstIndex { $0.id == selectedID } ?? checkpoints.count - 1
        playNavigationSound()
        select(checkpoints[min(checkpoints.count - 1, max(0, index + delta))].id, scroll: true, sound: false)
    }
    func applySelected() {
        guard !isApplying, !isLoadingHistory, let checkpoint = selectedCheckpoint else { return }
        onSelect?(checkpoint.id)
    }
}

enum RewindMenuSound {
    // Small synthesized PCM cues need no external assets or system alert sound.
    static func make(duration: Double, start: Double, end: Double) -> NSSound? {
        let rate = 22050
        let count = Int(duration * Double(rate))
        var data = Data()
        func word(_ value: UInt16) { data.append(UInt8(value & 255)); data.append(UInt8(value >> 8)) }
        func dword(_ value: UInt32) { word(UInt16(value & 65535)); word(UInt16(value >> 16)) }
        data.append(Data("RIFF".utf8)); dword(UInt32(36 + count * 2))
        data.append(Data("WAVEfmt ".utf8)); dword(16); word(1); word(1)
        dword(UInt32(rate)); dword(UInt32(rate * 2)); word(2); word(16)
        data.append(Data("data".utf8)); dword(UInt32(count * 2))
        var phase = 0.0
        for sample in 0..<count {
            let progress = Double(sample) / Double(count)
            phase += 2 * .pi * (start + (end - start) * progress) / Double(rate)
            let envelope = min(1, Double(sample) / 160) * pow(1 - progress, 2)
            word(UInt16(bitPattern: Int16(sin(phase) * envelope * 4200)))
        }
        return NSSound(data: data)
    }
}

struct RewindTimelineView: View {
    @ObservedObject var model: RewindTimelineModel
    @ObservedObject private var language = InterfaceLanguagePreferences.shared
    private let amber = Color(red: 0.98, green: 0.76, blue: 0.36)
    @State private var positionedHistory: [UInt64] = []
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            GeometryReader { previewGeometry in
                if let image = model.selectedCheckpoint?.image {
                    ZStack {
                        Color.black
                        Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                            .frame(width: previewGeometry.size.width, height: previewGeometry.size.height)
                    }.allowsHitTesting(false)
                }
            }
            VStack(alignment: .leading, spacing: model.isFullscreen ? 8 : 6) {
                HStack {
                    Text(UIStrings.text("Rewind history").uppercased()).font(.custom("Menlo-Bold", size: model.isFullscreen ? 14 : 12))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    Button { model.applySelected() } label: {
                        Text(UIStrings.text("Resume here")).font(.custom("Menlo-Bold", size: model.isFullscreen ? 12 : 11))
                            .padding(model.isFullscreen ? 8 : 5).background(amber).foregroundStyle(Color.black)
                    }.buttonStyle(.plain).disabled(model.isApplying || model.isLoadingHistory || model.selectedCheckpoint == nil)
                    Button { model.onCancel?() } label: {
                        Text(UIStrings.text("Cancel")).font(.custom("Menlo-Bold", size: model.isFullscreen ? 12 : 11))
                            .padding(model.isFullscreen ? 8 : 5).foregroundStyle(amber)
                            .overlay(Rectangle().strokeBorder(amber.opacity(0.5), lineWidth: 1).allowsHitTesting(false))
                    }.buttonStyle(.plain).disabled(model.isApplying)
                }
                if model.isFullscreen {
                    Text(UIStrings.text("Timeline help")).font(.custom("Menlo", size: 10)).lineLimit(2)
                }
                if !model.status.isEmpty { Text(model.status).font(.custom("Menlo", size: 11)).foregroundStyle(amber) }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(model.checkpoints) { checkpoint in
                                Button {
                                    model.select(checkpoint.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: model.isFullscreen ? 6 : 3) {
                                        if let image = checkpoint.image {
                                            Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
                                                .frame(width: thumbnailHeight(geometry) * 1.55, height: thumbnailHeight(geometry))
                                        } else {
                                            Rectangle().fill(Color.black)
                                                .frame(width: thumbnailHeight(geometry) * 1.55, height: thumbnailHeight(geometry))
                                                .overlay(Image(systemName: "photo"))
                                        }
                                        Text(String(format: "- %.1f s", checkpoint.age)).font(.custom("Menlo-Bold", size: model.isFullscreen ? 12 : 10))
                                    }
                                    .padding(cardPadding)
                                    .background(model.selectedID == checkpoint.id ? amber.opacity(0.15) : Color.black.opacity(0.25))
                                    .overlay(Rectangle().strokeBorder(model.selectedID == checkpoint.id ? amber : amber.opacity(0.3), lineWidth: 1))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).disabled(model.isApplying).id(checkpoint.id)
                                .accessibilityHint(UIStrings.text("Timeline help"))
                                .onHover { hovering in if hovering { model.hover(checkpoint.id) } }
                            }
                        }
                        .frame(height: thumbnailHeight(geometry) + cardExtraHeight)
                        .padding(.horizontal, timelineEndPadding(geometry))
                        .padding(.vertical, 4)
                    }
                    .frame(height: thumbnailHeight(geometry) + cardExtraHeight + 8)
                    .overlay {
                        if model.showsEmptyHistory {
                            Text(UIStrings.text("No rewind history")).font(.custom("Menlo", size: 12))
                                .multilineTextAlignment(.center).frame(maxWidth: 420).padding(12)
                        }
                    }
                    .opacity(positionedHistory == model.checkpoints.map(\.id) ? 1 : 0)
                    .task(id: model.checkpoints.map(\.id)) {
                        let history = model.checkpoints.map(\.id)
                        guard model.isPresented, !history.isEmpty else { positionedHistory = []; return }
                        // The host replaces history while this persistent view is
                        // hidden. Wait for the new cards to have scroll targets.
                        do { try await Task.sleep(nanoseconds: 50_000_000) }
                        catch { return }
                        guard !Task.isCancelled, model.isPresented,
                              history == model.checkpoints.map(\.id), let id = model.selectedID else { return }
                        proxy.scrollTo(id, anchor: .center)
                        await Task.yield()
                        positionedHistory = history
                    }
                    .onChange(of: geometry.size) { _, _ in
                        if model.isPresented, let id = model.selectedID { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: model.isFullscreen) { _, _ in
                        if model.isPresented, let id = model.selectedID { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: model.navigationRevision) { _, _ in
                        if let id = model.selectedID {
                            withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
            .padding(panelPadding).frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(red: 0.055, green: 0.07, blue: 0.09).opacity(0.96))
            .overlay(alignment: .top) { Rectangle().fill(amber).frame(height: 2).allowsHitTesting(false) }
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        .foregroundStyle(Color(red: 0.94, green: 0.925, blue: 0.86))
        .tint(amber).environment(\.colorScheme, .dark)
        }
    }
    private var panelPadding: CGFloat { model.isFullscreen ? 12 : 8 }
    private var cardPadding: CGFloat { model.isFullscreen ? 6 : 4 }
    private var cardExtraHeight: CGFloat { model.isFullscreen ? 36 : 24 }
    private func thumbnailHeight(_ geometry: GeometryProxy) -> CGFloat {
        model.isFullscreen ? min(110, max(52, geometry.size.height * 0.19)) : min(64, max(32, geometry.size.height * 0.13))
    }
    private func timelineEndPadding(_ geometry: GeometryProxy) -> CGFloat {
        // Real empty space at either end lets even the newest/oldest card
        // reach the center; newer checkpoints fill the right side on rewind.
        max(0, (geometry.size.width - panelPadding * 2 - (thumbnailHeight(geometry) * 1.55 + cardPadding * 2)) / 2)
    }
}
