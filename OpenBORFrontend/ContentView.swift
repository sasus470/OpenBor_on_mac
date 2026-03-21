import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    
    var body: some View {
        ZStack {
            NavigationSplitView {
                VStack(spacing: 12) {
                    HStack {
                        Label("Library", systemImage: "square.grid.2x2")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                model.showingSettings = true
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                    
                    TextField("Search games", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                    
                    List(selection: $model.selectedGameID) {
                        ForEach(model.filteredGames) { game in
                            GameRow(game: game)
                                .tag(game.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    model.launch(game: game)
                                }
                                .contextMenu {
                                    Button("Launch") { model.launch(game: game) }
                                    Button("Import Cover") { model.importCover(for: game) }
                                    Button("Reveal in Finder") { model.reveal(game) }
                                }
                        }
                    }
                    .listStyle(.sidebar)
                    
                    HStack {
                        Button("Open Paks") { model.openPaksFolder() }
                        Spacer()
                        Text(model.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(minWidth: 280)
            } detail: {
                GameDetailView(game: model.selectedGame, saves: model.saves(for: model.selectedGame))
                    .environmentObject(model)
            }
            
            if model.showingSettings {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.showingSettings = false
                        }
                    }
                
                SettingsOverlay()
                    .environmentObject(model)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }
}

private struct GameRow: View {
    @EnvironmentObject private var model: AppModel
    let game: GameEntry
    
    var body: some View {
        HStack(spacing: 12) {
            CoverThumbnail(url: model.coverURL(for: game), cornerRadius: 10)
                .frame(width: 42, height: 56)
                .id(model.coverRefreshToken(for: game))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(game.pakURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct GameDetailView: View {
    @EnvironmentObject private var model: AppModel
    let game: GameEntry?
    let saves: [SaveEntry]
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.92), .orange.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if let game {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 24) {
                            CoverThumbnail(url: model.coverURL(for: game), cornerRadius: 26)
                                .frame(width: 220, height: 308)
                                .id(model.coverRefreshToken(for: game))
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text(game.title)
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                Text(game.pakURL.lastPathComponent)
                                    .foregroundStyle(.white.opacity(0.7))
                                
                                HStack(spacing: 12) {
                                    Button {
                                        model.launch(game: game)
                                    } label: {
                                        Label("Play", systemImage: "play.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    
                                    Button {
                                        model.reveal(game)
                                    } label: {
                                        Label("Reveal", systemImage: "folder")
                                    }
                                    .buttonStyle(.bordered)
                                    
                                    Button {
                                        model.importCover(for: game)
                                    } label: {
                                        Label("Import Cover", systemImage: "photo")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                Text("Cover art")
                                    .font(.title3.weight(.semibold))
                                    .padding(.top, 10)
                                Text("Generated automatically and stored in the local cover library database.")
                                    .foregroundStyle(.white.opacity(0.72))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Saves")
                                .font(.title3.weight(.semibold))
                            
                            if saves.isEmpty {
                                Text("No saves yet for this game.")
                                    .foregroundStyle(.white.opacity(0.7))
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 14) {
                                        ForEach(saves) { save in
                                            Button {
                                                model.reveal(save)
                                            } label: {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Image(systemName: "externaldrive.fill")
                                                        .font(.system(size: 28))
                                                    Text(save.displayName)
                                                        .font(.headline)
                                                        .lineLimit(2)
                                                    Text(save.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                                        .font(.caption)
                                                        .foregroundStyle(.white.opacity(0.7))
                                                }
                                                .frame(width: 190, height: 120, alignment: .leading)
                                                .padding(16)
                                                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Controls")
                                .font(.title3.weight(.semibold))
                            Text("In game: pause with Start or Invio, then open Options > Control Options > Setup Player 1...")
                                .foregroundStyle(.white.opacity(0.75))
                            Text("Fullscreen: F11 or Alt+Invio")
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .padding(28)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 56))
                    Text("No games in library")
                        .font(.title2.bold())
                    Text("Use the settings gear or the Open Paks button to add `.pak` files.")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct CoverThumbnail: View {
    let url: URL?
    let cornerRadius: CGFloat
    
    var body: some View {
        ZStack {
            if let url,
               let data = try? Data(contentsOf: url),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(0.714, contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.92), .red.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
    }
}

struct SettingsOverlay: View {
    @EnvironmentObject private var model: AppModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings")
                    .font(.title.bold())
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                Button("Done") { close() }
                    .keyboardShortcut(.defaultAction)
            }
            
            settingsRow(title: "Paks", path: model.pakDirectory.path) {
                model.openPaksFolder()
            }
            settingsRow(title: "Saves", path: model.savesDirectory.path) {
                model.openSavesFolder()
            }
            settingsRow(title: "Logs", path: model.logsDirectory.path) {
                NSWorkspace.shared.open(model.logsDirectory)
            }
            settingsRow(title: "ScreenShots", path: model.screenshotsDirectory.path) {
                NSWorkspace.shared.open(model.screenshotsDirectory)
            }
            settingsRow(title: "Covers", path: model.coversDirectory.path) {
                model.openCoversFolder()
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("ScreenScraper")
                    .font(.headline)
                Text("Inserisci le credenziali API per scaricare cover reali e salvarle automaticamente nel database locale.")
                    .foregroundStyle(.secondary)
                
                TextField("Developer ID", text: $model.screenScraperDeveloperID)
                    .textFieldStyle(.roundedBorder)
                SecureField("Developer Password", text: $model.screenScraperDeveloperPassword)
                    .textFieldStyle(.roundedBorder)
                TextField("User ID (optional)", text: $model.screenScraperUserID)
                    .textFieldStyle(.roundedBorder)
                SecureField("User Password (optional)", text: $model.screenScraperUserPassword)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Button("Refresh Covers") {
                        model.refreshRemoteCovers()
                    }
                    .disabled(!model.hasScreenScraperDeveloperCredentials)
                    
                    if model.hasScreenScraperDeveloperCredentials {
                        Text("Cover online attive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Servono almeno Developer ID e Developer Password")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("ES-DE ready")
                    .font(.headline)
                Text("The frontend keeps your library in Application Support and the app executable supports `--launch <pak-path>`, which makes future frontend integration easier.")
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(24)
        .frame(width: 640, height: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 28, y: 16)
        .onExitCommand {
            close()
        }
    }
    
    private func settingsRow(title: String, path: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Open", action: action)
            }
            Text(path)
                .textSelection(.enabled)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private func close() {
        withAnimation(.easeInOut(duration: 0.18)) {
            model.showingSettings = false
        }
    }
}
