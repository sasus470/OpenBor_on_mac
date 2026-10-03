import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var language = InterfaceLanguagePreferences.shared

    var body: some View {
        ZStack {
            ArcadeBackground(paused: !model.animatedBackground || (model.runtimeCoordinator.runtimeState == .running && !model.runtimeCoordinator.resumeSessionAvailable))
            HStack(spacing: 0) {
                if model.libraryLayout == .sidebar {
                    library.frame(width: 300)
                } else {
                    gridLibrary.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Rectangle().fill(ArcadePalette.amber.opacity(0.35)).frame(width: 1)
                GameDetailView(game: model.selectedGame, saves: model.saves(for: model.selectedGame), compact: model.libraryLayout == .grid)
                    .frame(maxWidth: model.libraryLayout == .grid ? 420 : .infinity, maxHeight: .infinity)
            }
            if model.showingSettings {
                Color.black.opacity(0.72).ignoresSafeArea().onTapGesture { model.showingSettings = false }
                SettingsOverlay().transition(.opacity).zIndex(1)
            }
        }
        .foregroundStyle(ArcadePalette.cream)
        .font(.custom("Menlo", size: 12))
        .tint(ArcadePalette.amber)
        .environment(\.colorScheme, .dark)
        .buttonStyle(ArcadeButtonStyle())
        .onAppear { model.runtimeCoordinator.selectedPakURL = model.selectedGame?.pakURL }
        .onChange(of: model.selectedGame?.id) { _, _ in model.runtimeCoordinator.selectedPakURL = model.selectedGame?.pakURL }
        .onChange(of: language.language) { _, _ in model.statusText = model.localizedRuntimeStatus }
        .sheet(item: $model.coverBrowserGame) { game in
            CoverBrowserView(game: game) { data in try model.storeCoverData(data, for: game) }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OPENBOR / FRONTEND").font(.custom("Menlo-Bold", size: 10)).tracking(1).foregroundStyle(ArcadePalette.amber)
                    Text(UIStrings.text("Library").uppercased()).font(.custom("Menlo-Bold", size: 22))
                }
                Spacer()
                Button { model.showingSettings = true } label: { Image(systemName: "gearshape.fill") }
                    .help(UIStrings.text("Settings"))
            }
            TextField(UIStrings.text("Search games"), text: $model.searchText).textFieldStyle(.roundedBorder)
            layoutPicker
            List(selection: $model.selectedGameID) {
                ForEach(model.filteredGames) { game in
                    GameRow(game: game).tag(game.id)
                        .listRowBackground(model.selectedGameID == game.id ? ArcadePalette.amber.opacity(0.12) : Color.clear)
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture(count: 2).onEnded { model.launch(game: game) })
                        .contextMenu {
                            Button(UIStrings.text("Launch")) { model.launch(game: game) }
                            Button(UIStrings.text("Import Cover")) { model.importCover(for: game) }
                            Button(UIStrings.text("Search covers online")) { model.coverBrowserGame = game }
                            Button(UIStrings.text("Reveal in Finder")) { model.reveal(game) }
                        }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            Rectangle().fill(ArcadePalette.amber.opacity(0.35)).frame(height: 1)
            Text(model.runtimeCoordinator.runtimeState == .idle ? model.statusText : model.localizedRuntimeStatus)
                .font(.custom("Menlo", size: 10)).foregroundStyle(ArcadePalette.cream.opacity(0.65))
            Button(UIStrings.text("Open Paks")) { model.openPaksFolder() }
        }
        .padding(18).background(ArcadePalette.ink.opacity(0.92))
    }

    private var layoutPicker: some View {
        Picker(UIStrings.text("Library layout"), selection: $model.libraryLayout) {
            ForEach(LauncherLibraryLayout.allCases) { layout in
                Label(layout.title, systemImage: layout.symbol).tag(layout)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .id(language.language)
    }

    private var gridLibrary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("OPENBOR / SELECT GAME").font(.custom("Menlo-Bold", size: 10)).tracking(1).foregroundStyle(ArcadePalette.amber)
                    Text(UIStrings.text("Library").uppercased()).font(.custom("Menlo-Bold", size: 22))
                }
                Spacer()
                Button { model.reloadGames() } label: { Image(systemName: "arrow.clockwise") }
                    .help(UIStrings.text("Refresh library"))
                Button { model.showingSettings = true } label: { Image(systemName: "gearshape.fill") }
                    .help(UIStrings.text("Settings"))
            }
            HStack(spacing: 12) {
                TextField(UIStrings.text("Search games"), text: $model.searchText).textFieldStyle(.roundedBorder)
                layoutPicker.frame(width: 210)
            }
            ScrollView {
                if model.filteredGames.isEmpty {
                    Text(UIStrings.text(model.games.isEmpty ? "No games in library" : "No matching games"))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 18)], spacing: 22) {
                    ForEach(model.filteredGames) { game in
                        GameGridCard(game: game)
                    }
                }.padding(4)
            }
            HStack {
                Text(model.runtimeCoordinator.runtimeState == .idle ? model.statusText : model.localizedRuntimeStatus)
                    .font(.custom("Menlo", size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(UIStrings.text("Open Paks")) { model.openPaksFolder() }
            }
        }.padding(24)
    }
}

private struct GameRow: View {
    @EnvironmentObject private var model: AppModel
    let game: GameEntry
    @State private var hovering = false
    var body: some View {
        Button { model.selectedGameID = game.id } label: {
            HStack(spacing: 10) {
                CoverThumbnail(url: model.coverURL(for: game)).frame(width: 38, height: 52).id(model.coverRefreshToken(for: game))
                VStack(alignment: .leading, spacing: 5) {
                    ArcadeGameTitle(title: game.title, size: 11, hovering: hovering).lineLimit(2)
                    Text(game.pakURL.lastPathComponent).font(.custom("Menlo", size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct GameGridCard: View {
    @EnvironmentObject private var model: AppModel
    let game: GameEntry
    @State private var hovering = false

    var body: some View {
        Button { model.selectedGameID = game.id } label: {
            VStack(alignment: .leading, spacing: 10) {
                CoverThumbnail(url: model.coverURL(for: game))
                    .aspectRatio(0.714, contentMode: .fit)
                    .id(model.coverRefreshToken(for: game))
                ArcadeGameTitle(title: game.title, size: 12, hovering: hovering)
                    .lineLimit(2).frame(height: 34, alignment: .topLeading)
            }
            .padding(10)
            .background(ArcadePalette.ink.opacity(model.selectedGameID == game.id ? 0.98 : 0.75))
            .overlay(Rectangle().strokeBorder(ArcadePalette.amber.opacity(model.selectedGameID == game.id ? 1 : hovering ? 0.65 : 0.2), lineWidth: model.selectedGameID == game.id ? 2 : 1).allowsHitTesting(false))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.selectedGameID = game.id; model.launch(game: game) })
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(model.selectedGameID == game.id ? UIStrings.text("Selected game") : "")
        .accessibilityAction { model.selectedGameID = game.id }
        .contextMenu {
            Button(UIStrings.text("Launch")) { model.selectedGameID = game.id; model.launch(game: game) }
            Button(UIStrings.text("Import Cover")) { model.importCover(for: game) }
            Button(UIStrings.text("Search covers online")) { model.coverBrowserGame = game }
            Button(UIStrings.text("Reveal in Finder")) { model.reveal(game) }
        }
    }
}

private struct GameDetailView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var language = InterfaceLanguagePreferences.shared
    @ObservedObject private var menuPreferences = QuickMenuPreferences.shared
    let game: GameEntry?
    let saves: [SaveEntry]
    var compact = false
    @State private var hovering = false

    var body: some View {
        ScrollView {
            if let game {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("PLAYER ONE / SELECT GAME").font(.custom("Menlo-Bold", size: 10)).tracking(1).foregroundStyle(ArcadePalette.amber)
                        Spacer()
                        Text("32 BIT").font(.custom("Menlo-Bold", size: 11)).padding(8).foregroundStyle(ArcadePalette.ink).background(ArcadePalette.amber)
                    }
                    HStack(alignment: .top, spacing: 20) {
                        CoverThumbnail(url: model.coverURL(for: game)).frame(width: compact ? 94 : 156, height: compact ? 132 : 218).id(model.coverRefreshToken(for: game))
                            .onTapGesture { model.selectedGameID = game.id }
                            .onHover { hovering = $0 }
                        VStack(alignment: .leading, spacing: 14) {
                            ArcadeGameTitle(title: game.title, size: compact ? 18 : 23, hovering: hovering).fixedSize(horizontal: false, vertical: true)
                                .contentShape(Rectangle())
                                .allowsHitTesting(true)
                                .onTapGesture { model.selectedGameID = game.id }
                                .onHover { hovering = $0 }
                            Text(game.pakURL.lastPathComponent).font(.custom("Menlo", size: 10)).foregroundStyle(.secondary).lineLimit(2)
                            Text(model.renderBackend.title).foregroundStyle(ArcadePalette.amber)
                            Button(UIStrings.text("Play")) { model.launch(game: game) }
                                .buttonStyle(ArcadeButtonStyle(prominent: true)).disabled(!model.runtimeCoordinator.canLaunchSelectedGame)
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Button(UIStrings.text("Reveal")) { model.reveal(game) }
                                    Button(UIStrings.text("Import Cover")) { model.importCover(for: game) }
                                }
                                VStack(alignment: .leading) {
                                    Button(UIStrings.text("Reveal")) { model.reveal(game) }
                                    Button(UIStrings.text("Import Cover")) { model.importCover(for: game) }
                                }
                            }
                            Button(UIStrings.text("Search covers online")) { model.coverBrowserGame = game }
                        }
                        Spacer(minLength: 0)
                    }.modifier(ArcadePanel())
                    LauncherSessionView(coordinator: model.runtimeCoordinator)
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Recent Saves")
                        if saves.isEmpty {
                            Text(UIStrings.text("No saves yet for this game.")).foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal) {
                                HStack(spacing: 12) {
                                    ForEach(saves) { save in
                                        Button { model.reveal(save) } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Image(systemName: "externaldrive.fill")
                                                Text(save.displayName).lineLimit(2)
                                                Text(save.modifiedAt.formatted(date: .abbreviated, time: .shortened)).font(.custom("Menlo", size: 9)).foregroundStyle(.secondary)
                                            }.frame(width: 165, height: 75, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                    }.modifier(ArcadePanel())
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Controls")
                        Text(UIStrings.text("Controls help")).foregroundStyle(.secondary)
                        Text("\(menuPreferences.keyboard.title) / \(menuPreferences.controller.title)").foregroundStyle(ArcadePalette.amber)
                    }.modifier(ArcadePanel())
                }.padding(24)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("OPENBOR / SYSTEM READY").font(.custom("Menlo-Bold", size: 12)).foregroundStyle(ArcadePalette.amber)
                    Text(UIStrings.text("No games in library")).font(.custom("Menlo-Bold", size: 22))
                    Text(UIStrings.text("Add games help"))
                }.modifier(ArcadePanel()).padding(24)
            }
        }
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(UIStrings.text(key).uppercased()).font(.custom("Menlo-Bold", size: 12)).tracking(1).foregroundStyle(ArcadePalette.amber)
    }
}

private struct CoverThumbnail: View {
    let url: URL?
    var body: some View {
        ZStack {
            if let url, let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(0.714, contentMode: .fill)
            } else {
                ArcadePalette.ink
                Image(systemName: "gamecontroller.fill").font(.system(size: 24)).foregroundStyle(ArcadePalette.amber)
            }
        }
        .clipped()
        .overlay(Rectangle().strokeBorder(ArcadePalette.amber.opacity(0.55), lineWidth: 1).allowsHitTesting(false))
    }
}

struct SettingsOverlay: View {
    @ObservedObject private var language = InterfaceLanguagePreferences.shared
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(UIStrings.text("Settings").uppercased()).font(.custom("Menlo-Bold", size: 23))
                    Spacer()
                    Button(UIStrings.text("Done")) { model.showingSettings = false }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(UIStrings.text("Engine").uppercased()).font(.custom("Menlo-Bold", size: 12)).foregroundStyle(ArcadePalette.amber)
                    Picker(UIStrings.text("Engine"), selection: $model.renderBackend) {
                        ForEach(LauncherRenderBackend.allCases) { Text($0.title).tag($0) }
                    }
                    Text(UIStrings.text("Renderer help")).foregroundStyle(.secondary)
                    Toggle(UIStrings.text("Animated background"), isOn: $model.animatedBackground)
                    Toggle(UIStrings.text("Start games fullscreen"), isOn: $model.launchFullscreen)
                }.modifier(ArcadePanel())
                QuickMenuSettingsView(retroStyle: true)
                VStack(alignment: .leading, spacing: 12) {
                    Text(UIStrings.text("Library layout").uppercased()).font(.custom("Menlo-Bold", size: 12)).foregroundStyle(ArcadePalette.amber)
                    Picker(UIStrings.text("Library layout"), selection: $model.libraryLayout) {
                        ForEach(LauncherLibraryLayout.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().id(language.language)
                }.modifier(ArcadePanel())
                VStack(alignment: .leading, spacing: 10) {
                    Text("PAKS").font(.custom("Menlo-Bold", size: 12)).foregroundStyle(ArcadePalette.amber)
                    Text(model.pakDirectory.path).textSelection(.enabled).font(.custom("Menlo", size: 10)).foregroundStyle(.secondary)
                    Text(UIStrings.text("PAK folder help")).foregroundStyle(.secondary)
                    HStack {
                        Button(UIStrings.text("Choose PAK folder")) { model.choosePaksFolder() }
                        Button(UIStrings.text("Open")) { model.openPaksFolder() }
                        Button(UIStrings.text("Default folder")) { model.resetPaksFolder() }.disabled(model.usesDefaultPakDirectory)
                    }
                }.modifier(ArcadePanel())
                settingsRow(title: "Saves", path: model.savesDirectory.path, action: model.openSavesFolder)
                settingsRow(title: "Logs", path: model.logsDirectory.path) { NSWorkspace.shared.open(model.logsDirectory) }
                settingsRow(title: "ScreenShots", path: model.screenshotsDirectory.path) { NSWorkspace.shared.open(model.screenshotsDirectory) }
                settingsRow(title: "Covers", path: model.coversDirectory.path, action: model.openCoversFolder)
                VStack(alignment: .leading, spacing: 10) {
                    Text("SCREENSCRAPER").font(.custom("Menlo-Bold", size: 12)).foregroundStyle(ArcadePalette.amber)
                    Text(UIStrings.text("ScreenScraper help")).foregroundStyle(.secondary)
                    TextField(UIStrings.text("Developer ID"), text: $model.screenScraperDeveloperID).textFieldStyle(.roundedBorder)
                    SecureField(UIStrings.text("Developer Password"), text: $model.screenScraperDeveloperPassword).textFieldStyle(.roundedBorder)
                    TextField(UIStrings.text("User ID (optional)"), text: $model.screenScraperUserID).textFieldStyle(.roundedBorder)
                    SecureField(UIStrings.text("User Password (optional)"), text: $model.screenScraperUserPassword).textFieldStyle(.roundedBorder)
                    Button(UIStrings.text("Refresh Covers")) { model.refreshRemoteCovers() }.disabled(!model.hasScreenScraperDeveloperCredentials)
                    Text(UIStrings.text(model.hasScreenScraperDeveloperCredentials ? "Online covers enabled" : "Credentials needed")).foregroundStyle(.secondary)
                }.modifier(ArcadePanel())
                Text(UIStrings.text("Integration help")).foregroundStyle(.secondary)
            }.padding(24)
        }
        .frame(width: 680, height: 560)
        .background(ArcadePalette.ink)
        .overlay(Rectangle().strokeBorder(ArcadePalette.amber, lineWidth: 2).allowsHitTesting(false))
        .padding(5)
        .overlay(Rectangle().strokeBorder(ArcadePalette.amber.opacity(0.35), lineWidth: 1).allowsHitTesting(false))
        .compositingGroup()
        .shadow(color: .black.opacity(0.7), radius: 0, x: 8, y: 8)
        .onExitCommand { model.showingSettings = false }
    }

    private func settingsRow(title: String, path: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(UIStrings.text(title).uppercased()).font(.custom("Menlo-Bold", size: 12)).foregroundStyle(ArcadePalette.amber)
                Spacer()
                Button(UIStrings.text("Open"), action: action)
            }
            Text(path).textSelection(.enabled).font(.custom("Menlo", size: 10)).foregroundStyle(.secondary)
        }.modifier(ArcadePanel())
    }
}
