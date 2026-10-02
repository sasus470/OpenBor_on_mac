import SwiftUI

@main
struct OpenBORMacV2App: App {
    @StateObject private var windowCoordinator = HostWindowCoordinator()

    var body: some Scene {
        WindowGroup("OpenBOR Mac V2") {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OpenBOR Mac V2")
                            .font(.largeTitle.weight(.semibold))
                        Text("Native macOS host runtime scaffold.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Runtime", selection: $windowCoordinator.runtimeMode) {
                            ForEach(EngineRuntimeMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(windowCoordinator.runtimeMode.detailText)
                            .font(.callout)
                            .foregroundStyle(windowCoordinator.runtimeMode == .mock ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Game")
                                .font(.headline)
                            Spacer()
                            Button("Refresh Library") {
                                windowCoordinator.refreshAvailablePaks()
                            }
                        }

                        if windowCoordinator.availablePakURLs.isEmpty {
                            Text("No .pak files found in the V2 library folder yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Selected Game", selection: $windowCoordinator.selectedPakURL) {
                                ForEach(windowCoordinator.availablePakURLs, id: \.self) { pakURL in
                                    Text(pakURL.deletingPathExtension().lastPathComponent).tag(Optional(pakURL))
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sessione")
                            .font(.headline)

                        Picker("Modalita Sessione", selection: $windowCoordinator.sessionLaunchMode) {
                            ForEach(V2SessionLaunchMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(windowCoordinator.sessionLaunchMode.detailText)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Text(windowCoordinator.sessionModeSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if windowCoordinator.sessionLaunchMode == .loadSaveState {
                            if !windowCoordinator.manualSaveStates.isEmpty {
                                Picker("Save State", selection: $windowCoordinator.selectedSaveStateID) {
                                    ForEach(windowCoordinator.manualSaveStates) { slot in
                                        Text("\(slot.title) (\(slot.fileCount) file)")
                                            .tag(Optional(slot.id))
                                    }
                                }
                                .labelsHidden()
                            }

                            Text(windowCoordinator.liveSaveStateSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if windowCoordinator.sessionLaunchMode == .loadLiveSaveState {
                            if !windowCoordinator.liveSaveStates.isEmpty {
                                Picker("Live Savestate", selection: $windowCoordinator.selectedLiveSaveStateID) {
                                    ForEach(windowCoordinator.liveSaveStates) { slot in
                                        Text("\(slot.title) (\(slot.engineVersion))")
                                            .tag(Optional(slot.id))
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        HStack(spacing: 10) {
                            Button("Crea Snapshot Disco") {
                                windowCoordinator.createManualSaveState()
                            }
                            .disabled(!windowCoordinator.canCreateManualSaveState)

                            Button("Elimina Snapshot") {
                                windowCoordinator.deleteSelectedSaveState()
                            }
                            .disabled(!windowCoordinator.canDeleteSelectedSaveState)
                        }

                        Divider()

                        Text("Live Savestate")
                            .font(.subheadline.weight(.semibold))

                        Text(windowCoordinator.liveSaveStateSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button("Cattura Live Savestate") {
                            windowCoordinator.captureLiveSaveState()
                        }
                        .disabled(!windowCoordinator.canCaptureLiveSaveState)

                        Text(windowCoordinator.liveSaveStateStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )

                    QuickMenuSettingsView()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 10, height: 10)
                            Text(windowCoordinator.runtimeState.displayName)
                                .font(.headline)
                            Spacer()
                            Text(windowCoordinator.runtimeDiagnostics.rendererName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        Text(windowCoordinator.runtimeStatusSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        statusRow("Game", value: windowCoordinator.selectedGameDisplayName)
                        statusRow("Sessione", value: windowCoordinator.lastLaunchedSessionMode.displayName)
                        statusRow("Executable", value: windowCoordinator.runtimeExecutableName)
                        statusRow("Arguments", value: windowCoordinator.runtimeArgumentsSummary)

                        if let lastError = windowCoordinator.runtimeDiagnostics.lastErrorMessage, !lastError.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last Error")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(lastError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(nsColor: .windowBackgroundColor),
                                        Color(nsColor: .underPageBackgroundColor)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                    HStack(spacing: 12) {
                        Button(primaryActionTitle) {
                            windowCoordinator.showHostWindow()
                        }
                        .disabled(!windowCoordinator.canLaunchSelectedGame)

                        Button("Toggle Fullscreen") {
                            windowCoordinator.toggleFullscreen()
                        }
                        .disabled(windowCoordinator.runtimeMode == .process)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 620, minHeight: 470)
        }
        .commands {
            CommandMenu("OpenBOR V2") {
                Button("Open Host Window") {
                    windowCoordinator.showHostWindow()
                }
                Button("Toggle Fullscreen") {
                    windowCoordinator.toggleFullscreen()
                }
            }
        }
    }

    private var statusColor: Color {
        switch windowCoordinator.runtimeState.accentName {
        case "yellow":
            return .yellow
        case "green":
            return .green
        case "orange":
            return .orange
        case "red":
            return .red
        default:
            return Color(nsColor: .secondaryLabelColor)
        }
    }

    private var primaryActionTitle: String {
        switch windowCoordinator.runtimeMode {
        case .mock:
            return "Open Host Window"
        case .process:
            return "Launch Selected Game"
        case .bridge:
            return "Launch Bridge Runtime"
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
