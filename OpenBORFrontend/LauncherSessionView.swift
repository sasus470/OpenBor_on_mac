import SwiftUI

struct LauncherSessionView: View {
    @ObservedObject var coordinator: HostWindowCoordinator
    @ObservedObject private var language = InterfaceLanguagePreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UIStrings.text("Session").uppercased()).font(.custom("Menlo-Bold", size: 12)).foregroundStyle(ArcadePalette.amber)
            Picker(UIStrings.text("Session"), selection: $coordinator.sessionLaunchMode) {
                ForEach(V2SessionLaunchMode.allCases) { mode in
                    Text(title(for: mode)).tag(mode)
                }
            }
            .labelsHidden()
            if coordinator.sessionLaunchMode == .loadLiveSaveState {
                if coordinator.liveSaveStates.isEmpty {
                    Text(UIStrings.text("No savestates")).font(.callout)
                } else {
                    Picker(UIStrings.text("Live slot"), selection: $coordinator.selectedLiveSaveStateID) {
                        ForEach(coordinator.liveSaveStates) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
            }
            if coordinator.sessionLaunchMode == .loadSaveState {
                Picker(UIStrings.text("Load disk snapshot"), selection: $coordinator.selectedSaveStateID) {
                    ForEach(coordinator.manualSaveStates) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            if coordinator.sessionLaunchMode == .resumeSession && !coordinator.resumeSessionAvailable {
                Text(UIStrings.text("No suspended session")).font(.callout)
            }
            if let error = coordinator.runtimeDiagnostics.lastErrorMessage {
                Text(error).foregroundStyle(.orange).textSelection(.enabled)
            }
        }
        .modifier(ArcadePanel())
    }

    private func title(for mode: V2SessionLaunchMode) -> String {
        switch mode {
        case .newSession: return UIStrings.text("New session")
        case .resumeSession: return UIStrings.text("Resume session")
        case .resumeProgress: return UIStrings.text("Resume progress")
        case .loadSaveState: return UIStrings.text("Load disk snapshot")
        case .loadLiveSaveState: return UIStrings.text("Load savestate")
        }
    }
}
