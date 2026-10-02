import AppKit
import GameController
import SwiftUI

enum QuickMenuKeyboardShortcut: String, CaseIterable, Identifiable {
    case f1, f2, f3, f4, f5, f6, f7, f8, f10, f11, f12, commandShiftM
    var id: String { rawValue }
    var title: String { self == .commandShiftM ? "Cmd + Shift + M" : rawValue.uppercased() }
    var keyCode: UInt16 {
        switch self {
        case .f1: return 122
        case .f2: return 120
        case .f3: return 99
        case .f4: return 118
        case .f5: return 96
        case .f6: return 97
        case .f7: return 98
        case .f8: return 100
        case .f10: return 109
        case .f11: return 103
        case .f12: return 111
        case .commandShiftM: return 46
        }
    }
    func matches(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        return event.keyCode == keyCode && modifiers == (self == .commandShiftM ? [.command, .shift] : [])
    }
}

enum QuickMenuControllerShortcut: String, CaseIterable, Identifiable {
    case sticks, options, shouldersMenu
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sticks: return "L3 + R3"
        case .options: return "Options / Select"
        case .shouldersMenu: return "L1 + R1 + Menu"
        }
    }
    func isPressed(on pad: GCExtendedGamepad) -> Bool {
        switch self {
        case .sticks: return pad.leftThumbstickButton?.isPressed == true && pad.rightThumbstickButton?.isPressed == true
        case .options: return pad.buttonOptions?.isPressed == true
        case .shouldersMenu: return pad.leftShoulder.isPressed && pad.rightShoulder.isPressed && pad.buttonMenu.isPressed
        }
    }
}

final class QuickMenuPreferences: ObservableObject {
    static let shared = QuickMenuPreferences()
    @Published var keyboard: QuickMenuKeyboardShortcut {
        didSet { UserDefaults.standard.set(keyboard.rawValue, forKey: "quickMenuKeyboard") }
    }
    @Published var controller: QuickMenuControllerShortcut {
        didSet { UserDefaults.standard.set(controller.rawValue, forKey: "quickMenuController") }
    }
    @Published var rewindEnabled: Bool {
        didSet { UserDefaults.standard.set(rewindEnabled, forKey: "rewindEnabled"); publishRewind() }
    }
    @Published var rewindKey: QuickMenuKeyboardShortcut {
        didSet { UserDefaults.standard.set(rewindKey.rawValue, forKey: "rewindKey"); publishRewind() }
    }
    func publishRewind() {
        let text = "\(rewindEnabled ? 1 : 0) 0"
        try? text.write(to: V2LaunchConfigurationFactory.rewindCommandURL(), atomically: true, encoding: .utf8)
    }
    private init() {
        rewindEnabled = UserDefaults.standard.bool(forKey: "rewindEnabled")
        rewindKey = QuickMenuKeyboardShortcut(rawValue: UserDefaults.standard.string(forKey: "rewindKey") ?? "") ?? .f6
        keyboard = QuickMenuKeyboardShortcut(rawValue: UserDefaults.standard.string(forKey: "quickMenuKeyboard") ?? "") ?? .f1
        controller = QuickMenuControllerShortcut(rawValue: UserDefaults.standard.string(forKey: "quickMenuController") ?? "") ?? .sticks
    }
}

final class QuickMenuModel: ObservableObject {
    @Published var slots: [V2LiveSaveStateSlot] = []
    @Published var selectedSlotID: String?
    @Published var selectedAction = 0
    @Published private(set) var navigationRevision = 0
    private var selectionPointerLocation = NSEvent.mouseLocation
    @Published var status = ""
    @Published var isPresented = false
    @Published var shaderTitleKey = "Original"
    @Published var shaderScopeKey = "Global default"
    var shaderTitle: String { UIStrings.text(shaderTitleKey) }
    var shaderScope: String { UIStrings.text(shaderScopeKey) }
    @Published var hasGame = false
    var actions: [String] {
        [UIStrings.text("Resume game"), UIStrings.text("Capture in a new slot"), UIStrings.text("Load selected slot"), UIStrings.text("Suspend session"), UIStrings.text("Fullscreen / window"), UIStrings.text("Return to launcher"),
         UIStrings.text("Shader: %@", shaderTitle), UIStrings.text("Save shader for this game"), UIStrings.text("Save shader for all games"), UIStrings.text("Use global shader for this game"), UIStrings.text(QuickMenuPreferences.shared.rewindEnabled ? "Disable rewind" : "Enable rewind"), UIStrings.text("Rewind history")]
    }
    var onAction: ((Int) -> Void)?
    var onShaderDirection: ((Int) -> Void)?

    func moveAction(_ direction: Int) {
        selectionPointerLocation = NSEvent.mouseLocation
        selectedAction = (selectedAction + direction + actions.count) % actions.count
        navigationRevision += 1
    }
    func resetSelection() {
        selectionPointerLocation = NSEvent.mouseLocation
        selectedAction = 0
        navigationRevision += 1
    }
    func selectHoveredAction(_ action: Int, pointerLocation: NSPoint = NSEvent.mouseLocation) {
        // Scrolling rows can trigger hover without the user moving the mouse.
        let dx = pointerLocation.x - selectionPointerLocation.x
        let dy = pointerLocation.y - selectionPointerLocation.y
        guard dx * dx + dy * dy >= 1 else { return }
        selectionPointerLocation = pointerLocation
        selectedAction = action
    }
    func selectClickedAction(_ action: Int) {
        selectionPointerLocation = NSEvent.mouseLocation
        selectedAction = action
    }
    func moveSlot(_ direction: Int) {
        if selectedAction == 6 { onShaderDirection?(direction); return }
        guard !slots.isEmpty else { return }
        let current = slots.firstIndex { $0.id == selectedSlotID } ?? 0
        selectedSlotID = slots[(current + direction + slots.count) % slots.count].id
    }
}

struct QuickMenuView: View {
    @ObservedObject var model: QuickMenuModel
    @ObservedObject private var preferences = QuickMenuPreferences.shared
    @ObservedObject private var language = InterfaceLanguagePreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let amber = Color(red: 0.98, green: 0.76, blue: 0.36)
    private let ink = Color(red: 0.094, green: 0.11, blue: 0.14)
    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("OPENBOR / SYSTEM MENU").font(.custom("Menlo-Bold", size: 10)).tracking(2)
                                .foregroundStyle(amber)
                            Text(UIStrings.text("Quick menu").uppercased()).font(.custom("Menlo-Bold", size: 25)).tracking(1)
                        }
                        Spacer()
                        Text("32\nBIT").font(.custom("Menlo-Bold", size: 12))
                            .foregroundStyle(ink).padding(8).background(amber)
                    }
                    HStack(spacing: 8) {
                        Rectangle().fill(amber).frame(width: 6, height: 6)
                        Text(UIStrings.text("Paused / live session")).font(.custom("Menlo", size: 10)).tracking(1)
                    }.foregroundStyle(amber.opacity(0.8))
                    Rectangle().fill(amber.opacity(0.35)).frame(height: 1)
                    if !model.status.isEmpty {
                        Text(model.status).font(.custom("Menlo", size: 11)).foregroundStyle(amber)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    if model.slots.isEmpty {
                        Text(UIStrings.text("No live slots")).font(.custom("Menlo", size: 11))
                            .foregroundStyle(.white.opacity(0.6)).padding(.vertical, 4)
                    } else {
                        Picker(UIStrings.text("Live slot"), selection: $model.selectedSlotID) {
                            ForEach(model.slots) { slot in
                                Text(slot.title).tag(Optional(slot.id))
                            }
                        }
                        .tint(amber)
                    }
                    ForEach(Array(model.actions.enumerated()), id: \.offset) { index, title in
                        RetroQuickMenuAction(
                            title: title, index: index,
                            selected: model.selectedAction == index,
                            available: (index != 2 || model.selectedSlotID != nil) && (!(index == 7 || index == 9) || model.hasGame),
                            menuVisible: model.isPresented,
                            onHover: { model.selectHoveredAction(index) }
                        ) {
                            model.selectClickedAction(index)
                            model.onAction?(index)
                        }
                        .id(index)
                    }
                    Rectangle().fill(amber.opacity(0.35)).frame(height: 1)
                    Text(UIStrings.text("Shader: %@", model.shaderScope)).font(.custom("Menlo", size: 10)).foregroundStyle(amber)
                    RewindSettingsView()
                    Text(UIStrings.text("Navigation help"))
                        .font(.custom("Menlo", size: 10)).lineSpacing(5).foregroundStyle(.white.opacity(0.55))
                }
                .padding(22)
            }
            .onChange(of: model.navigationRevision) { _, _ in
                let action = model.selectedAction
                if reduceMotion { proxy.scrollTo(action) }
                else { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(action) } }
            }
            }
            .frame(maxWidth: 520, maxHeight: 590)
            .background {
                ZStack {
                    ink
                    Canvas { context, size in
                        for y in stride(from: 0, to: Int(size.height), by: 12) {
                            for x in stride(from: 0, to: Int(size.width), by: 12) where (x + y) % 24 == 0 {
                                context.fill(Path(CGRect(x: x, y: y, width: 12, height: 12)),
                                             with: .color(amber.opacity(0.025)))
                            }
                        }
                    }.allowsHitTesting(false)
                }
            }
            .overlay(Rectangle().strokeBorder(amber, lineWidth: 2).allowsHitTesting(false))
            .padding(5)
            .overlay(Rectangle().strokeBorder(amber.opacity(0.35), lineWidth: 1).allowsHitTesting(false))
            .compositingGroup()
            .shadow(color: .black.opacity(0.7), radius: 0, x: 8, y: 8)
            .padding(18)
            .foregroundStyle(Color(red: 0.94, green: 0.925, blue: 0.86))
            .environment(\.colorScheme, .dark)
        }
    }
}

private struct RetroQuickMenuAction: View {
    let title: String
    let index: Int
    let selected: Bool
    let available: Bool
    let menuVisible: Bool
    let onHover: () -> Void
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let amber = Color(red: 0.98, green: 0.76, blue: 0.36)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Text(String(format: "%02d", index + 1))
                        .foregroundStyle(.white.opacity(0.3)).opacity(selected ? 0 : 1)
                    if selected {
                        TimelineView(.animation(minimumInterval: 0.12, paused: !menuVisible || reduceMotion)) { timeline in
                            let step = reduceMotion ? 0 : Int(timeline.date.timeIntervalSinceReferenceDate * 8) % 6
                            let shift = CGFloat(step < 3 ? step : 5 - step) * 2
                            Canvas { context, _ in
                                // Square pixels form an arcade-style selection arrow.
                                for row in 0..<5 {
                                    let width = row <= 2 ? row + 1 : 5 - row
                                    context.fill(Path(CGRect(x: shift, y: CGFloat(row) * 3,
                                                             width: CGFloat(width) * 3, height: 3)),
                                                 with: .color(amber))
                                }
                            }.frame(width: 18, height: 15).allowsHitTesting(false)
                        }
                    }
                }.frame(width: 24)
                Text(title).font(.custom("Menlo-Bold", size: 12))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 2)
                if selected { Rectangle().fill(amber).frame(width: 4, height: 18) }
            }
            .font(.custom("Menlo", size: 11))
            .padding(.horizontal, 12).padding(.vertical, 12)
            .foregroundStyle(selected ? amber : .white.opacity(0.85))
            .background(selected ? amber.opacity(0.12) : Color.black.opacity(0.15))
            .overlay(Rectangle().strokeBorder(selected ? amber : .white.opacity(0.12), lineWidth: 1).allowsHitTesting(false))
            .opacity(available ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .onHover { hovering in if hovering { onHover() } }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct QuickMenuSettingsView: View {
    var retroStyle = false
    @ObservedObject private var preferences = QuickMenuPreferences.shared
    @ObservedObject private var language = InterfaceLanguagePreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UIStrings.text("Quick menu settings")).font(.headline)
            Picker(UIStrings.text("Language"), selection: $language.language) {
                ForEach(InterfaceLanguage.allCases) { Text($0.title).tag($0) }
            }
            Picker(UIStrings.text("Keyboard"), selection: $preferences.keyboard) {
                ForEach(QuickMenuKeyboardShortcut.allCases) { shortcut in
                    Text(shortcut.title).tag(shortcut)
                }
            }
            Picker(UIStrings.text("Controller"), selection: $preferences.controller) {
                ForEach(QuickMenuControllerShortcut.allCases) { shortcut in
                    Text(shortcut.title).tag(shortcut)
                }
            }
            Text(UIStrings.text("Shortcut help"))
                .font(.caption).foregroundStyle(.secondary)
            RewindSettingsView()
        }
        .padding(14)
        .background {
            if retroStyle {
                Rectangle().fill(Color(red: 0.094, green: 0.11, blue: 0.14))
                    .overlay(Rectangle().strokeBorder(Color(red: 0.98, green: 0.76, blue: 0.36).opacity(0.35), lineWidth: 1).allowsHitTesting(false))
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor))
            }
        }
    }
}

struct RewindSettingsView: View {
    @ObservedObject private var preferences = QuickMenuPreferences.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(UIStrings.text("Enable rewind"), isOn: $preferences.rewindEnabled)
            Picker(UIStrings.text("Rewind key"), selection: $preferences.rewindKey) {
                ForEach(QuickMenuKeyboardShortcut.allCases.filter { $0 != preferences.keyboard }) {
                    Text($0.title).tag($0)
                }
            }
            Text(UIStrings.text("Rewind help")).font(.caption).foregroundStyle(.secondary)
            if preferences.rewindKey == preferences.keyboard {
                Text(UIStrings.text("Rewind conflict")).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
