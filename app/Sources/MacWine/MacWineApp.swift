import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacWineCore

@main
struct MacWineApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateController()
    var body: some Scene {
        WindowGroup {
            AppRootView().environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
                .environment(\.locale, Locale(identifier: "en"))
                .onOpenURL { model.pendingFile = $0; model.showOpenFile = true }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheckForUpdates || model.runtimeInstalling)
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Bottle…") { model.showCreate = true }.keyboardShortcut("n").disabled(!model.runtimeReady)
                Button("Run EXE…") { model.chooseFile() }.keyboardShortcut("o").disabled(!model.runtimeReady)
            }
            CommandGroup(after: .newItem) {
                Button("Refresh Library") { Task { await model.refresh() } }.keyboardShortcut("r").disabled(!model.runtimeReady || model.busy)
            }
        }
        Settings {
            AppPreferencesView().environmentObject(updates)
                .environment(\.locale, Locale(identifier: "en"))
        }
    }
}

struct AppPreferencesView: View {
    @EnvironmentObject var updates: UpdateController
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }.pickerStyle(.segmented)
            Text("System follows your Mac’s appearance. Changes apply immediately.")
                .font(.caption).foregroundStyle(.secondary)
            Divider().padding(.vertical, 8)
            Toggle("Automatically check for updates", isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.setAutomaticallyChecks($0) }))
                .disabled(!updates.configured)
            if updates.configured {
                Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheckForUpdates)
            } else {
                Text("App updates are not configured for this build.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    }
}

struct GameArt: View {
    let game: Game
    @EnvironmentObject var model: AppModel
    @State private var localIcon: NSImage?
    var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.teal.opacity(0.7), .indigo.opacity(0.55), .black.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let localIcon { Image(nsImage: localIcon).resizable().scaledToFit().padding(25) }
            else { Image(systemName: "gamecontroller.fill").font(.system(size: 44)).foregroundStyle(.white.opacity(0.8)) }
        }
    }
    @State private var customImage: NSImage?
    var body: some View {
        Group {
            if let customImage {
                Image(nsImage: customImage).resizable().scaledToFit()
            } else if let artwork = game.artworkURL, let url = URL(string: artwork), url.scheme == "https" {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { placeholder }
            } else if game.store == .steam, game.storeID.allSatisfy(\.isNumber) {
                AsyncImage(url: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.storeID)/library_600x900.jpg")) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else if phase.error != nil {
                        AsyncImage(url: URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(game.storeID)/header.jpg")) { image in image.resizable().scaledToFit() } placeholder: { placeholder }
                    } else { placeholder }
                }
            } else { placeholder }
        }.frame(height: 190).frame(maxWidth: .infinity).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 12))
        .saturation(game.installed ? 1 : 0)
        .opacity(game.installed ? 1 : 0.64)
        .accessibilityLabel(game.installed ? "Installed game artwork" : "Not installed, grayscale artwork")
        .task(id: "\(game.id)#\(model.artworkVersion)") {
            customImage = model.customArtwork(game).flatMap { NSImage(contentsOf: $0) }
            guard customImage == nil, game.store != .steam, let executable = game.executable, FileManager.default.fileExists(atPath: executable) else { return }
            let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MacWine/Icons")
            // Stable filename, independent of unsafe store IDs.
            let filename = Data(game.id.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
            let output = cache.appendingPathComponent(String(filename.prefix(180)) + ".png")
            try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: output.path) { _ = try? await model.cli.run(["icon", executable, output.path, "--size", "512"]) }
            localIcon = NSImage(contentsOf: output)
        }
    }
}
struct GameCard: View {
    let game: Game
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { model.detail = game } label: { GameArt(game: game) }.buttonStyle(.plain).accessibilityLabel("Show details for " + game.name)
            Text(game.name).font(.headline).lineLimit(2).frame(height: 36, alignment: .topLeading)
            HStack(spacing: 6) {
                Text(game.store.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let rating = model.ratings[model.ratingKey(game)] {
                    StarsView(value: rating.average, size: 9)
                    Text("\(rating.count)").font(.caption2).foregroundStyle(.secondary)
                }
            }.help(model.ratings[model.ratingKey(game)].map { "Community rating \(String(format: "%.1f", $0.average)) of 5 from \($0.count) players" } ?? "")
            HStack {
                Label(game.installed ? "Installed" : "Not installed", systemImage: game.installed ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(game.installed ? "Play" : "Install") { Task { await model.launch(game) } }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(model.busy)
            }.padding(.top, 4)
        }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .contextMenu {
            Button("Details") { model.detail = game }
            Button("Create Shortcut…") { model.shortcut(game) }.disabled(model.busy)
        }
    }
}
struct GameDetailView: View {
    let game: Game
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var rating = false
    @State private var dsoal: Bool?        // nil = unknown / not applicable
    @State private var dsoalBusy = false
    @State private var dsoalError: String?
    private struct DsoalStatus: Decodable { let dsoal: Bool }
    private struct FpsStatus: Decodable { let fpscounter: Bool }
    @State private var fpsCounter: Bool?
    private var fpsBinding: Binding<Bool> {
        Binding(get: { fpsCounter ?? false }, set: { on in Task { await setFpsCounter(on) } })
    }
    func setFpsCounter(_ on: Bool) async {
        guard let exe = game.executable else { return }
        dsoalBusy = true; dsoalError = nil
        do { fpsCounter = try await model.cli.decode(FpsStatus.self, ["fpscounter", game.bottle, on ? "on" : "off", exe, "--json"]).fpscounter }
        catch { dsoalError = error.localizedDescription }
        dsoalBusy = false
    }
    private var dsoalBinding: Binding<Bool> {
        Binding(get: { dsoal ?? false }, set: { on in Task { await setDsoal(on) } })
    }
    func setDsoal(_ on: Bool) async {
        guard let exe = game.executable else { return }
        dsoalBusy = true; dsoalError = nil
        do { dsoal = try await model.cli.decode(DsoalStatus.self, ["dsoal", game.bottle, on ? "on" : "off", exe, "--json"]).dsoal }
        catch { dsoalError = error.localizedDescription }
        dsoalBusy = false
    }
    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            GameArt(game: game).frame(width: 155)
            VStack(alignment: .leading, spacing: 14) {
                Text(game.name).font(.title.bold())
                Text("\(game.store.title) · \(game.bottle)").foregroundStyle(.secondary)
                Text(game.installed ? "Installed" : "Not installed").font(.caption)
                Button(game.installed ? "Play" : "Install") {
                    model.pendingGameLaunch = game
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(model.busy)
                Button("Create Shortcut…") { model.shortcut(game) }.disabled(model.busy)
                Text("Choose where to save the shortcut.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Choose Image…") { model.chooseArtwork(game) }
                    if model.customArtwork(game) != nil { Button("Remove Image") { model.removeArtwork(game) } }
                }
                Text("Your own cover for games without one. Also used as the shortcut icon.").font(.caption).foregroundStyle(.secondary)
                if game.installed, let exe = game.executable {
                    Button("Show Game Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: exe)])
                    }.disabled(!FileManager.default.fileExists(atPath: exe))
                }
                if game.installed, game.executable != nil, fpsCounter != nil {
                    Toggle("Show FPS counter", isOn: fpsBinding).disabled(dsoalBusy || model.busy)
                }
                if game.installed, game.executable != nil, dsoal != nil {
                    Toggle("Better sound for older games", isOn: dsoalBinding).disabled(dsoalBusy || model.busy)
                    Text("Turn on if the sound is choppy or metallic. Replaces DirectSound for this game only (DSOAL, OpenAL Soft).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let dsoalError { Text(dsoalError).font(.caption).foregroundStyle(.red) }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Community rating").font(.headline)
                    if let rating = model.ratings[model.ratingKey(game)] {
                        HStack(spacing: 8) {
                            StarsView(value: rating.average, size: 14)
                            Text(String(format: "%.1f", rating.average)).bold()
                            Text("· \(rating.count) \(rating.count == 1 ? "player" : "players")").foregroundStyle(.secondary)
                        }
                        if let v = rating.latestVersion { Text("Latest report from MacWine \(v)").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text("No ratings yet.").foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Rate This Game…") { rating = true }.disabled(model.githubRepo == nil)
                        if let url = model.reportsURL(game) { Link("Read Reports", destination: url) }
                    }
                }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(30).frame(width: 600)
        .sheet(isPresented: $rating) { RateGameView(game: game) }
        .task(id: game.id) {
            guard game.installed, let exe = game.executable else { return }
            dsoal = (try? await model.cli.decode(DsoalStatus.self, ["dsoal", game.bottle, "status", exe, "--json"]))?.dsoal
            fpsCounter = (try? await model.cli.decode(FpsStatus.self, ["fpscounter", game.bottle, "status", exe, "--json"]))?.fpscounter
        }
    }
}

/// Five stars, filled to `value` (0...5, halves shown as half stars).
struct StarsView: View {
    let value: Double
    var size: CGFloat = 12
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                let d = value - Double(i - 1)
                Image(systemName: d >= 0.75 ? "star.fill" : d >= 0.25 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: size)).foregroundStyle(.orange)
            }
        }.accessibilityLabel(String(format: "%.1f of 5 stars", value))
    }
}

struct RateGameView: View {
    let game: Game
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var stars = 3
    static let meanings = ["Does not start", "Starts, but is not playable", "Playable with major problems",
                           "Playable with some problems", "Works well, minor issues", "Works perfectly"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rate \(game.name)").font(.title2.bold())
            Text("How well does this game run in MacWine on your Mac?").foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button { stars = 0 } label: { Image(systemName: stars == 0 ? "xmark.circle.fill" : "xmark.circle").font(.title2) }
                    .buttonStyle(.plain).foregroundStyle(stars == 0 ? .red : .secondary).help("0 – Does not start").accessibilityLabel("0 stars, does not start")
                ForEach(1...5, id: \.self) { i in
                    Button { stars = i } label: { Image(systemName: i <= stars ? "star.fill" : "star").font(.title) }
                        .buttonStyle(.plain).foregroundStyle(.orange).help("\(i) – \(Self.meanings[i])").accessibilityLabel("\(i) of 5 stars, \(Self.meanings[i])")
                }
            }
            Text("\(stars)/5 – \(Self.meanings[stars])").font(.headline)
            Text("Your rating is shared with all MacWine users through GitHub Discussions (a free GitHub account is needed). The next page is already filled in – add a note if you like and post it. Ratings appear in MacWine within about an hour.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue on GitHub") {
                    if let url = model.rateURL(game, stars: stars) { NSWorkspace.shared.open(url) }
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 460)
    }
}

struct CreateBottleView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    var valid: Bool { !name.isEmpty && name != "." && name != ".." && name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil && !model.bottles.contains { $0.name == name } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add a custom bottle").font(.title2.bold())
            Text("A bottle is a separate Windows environment for your own apps and installers.").foregroundStyle(.secondary)
            TextField("Name, for example my-games", text: $name).textFieldStyle(.roundedBorder)
            Text("Use letters, numbers, hyphens or underscores.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Create Bottle") {
                let value = name; dismiss()
                Task { await model.perform(["create", value, "--json"], message: "Creating bottle \(value)…", refreshAfter: true); if model.bottles.contains(where: { $0.name == value }) { model.selection = "bottle:" + value } }
            }.keyboardShortcut(.defaultAction).disabled(!valid || model.busy) }
        }.padding(28).frame(width: 430)
    }
}
struct OpenFileView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var bottle = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose a bottle").font(.title2.bold())
            Text(model.pendingFile?.lastPathComponent ?? "Choose a file").lineLimit(2)
            Picker("Bottle", selection: $bottle) { ForEach(model.bottles) { Text($0.name).tag($0.name) } }
            if model.bottles.isEmpty { Text("Create a custom bottle in the main window first.").foregroundStyle(.secondary) }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Run") {
                guard let url = model.pendingFile else { return }; dismiss()
                Task { await model.perform(["open", url.path, "--bottle", bottle, "--detach"], message: "Opening \(url.lastPathComponent)…") }
            }.buttonStyle(.borderedProminent).disabled(bottle.isEmpty || model.pendingFile == nil || model.busy) }
        }.padding(28).frame(width: 440)
        .onAppear { bottle = model.selectedBottle ?? model.customBottles.first?.name ?? model.bottles.first?.name ?? "" }
        .onChange(of: model.bottles) { bottles in
            if !bottles.contains(where: { $0.name == bottle }) { bottle = model.selectedBottle ?? bottles.first?.name ?? "" }
        }
    }
}
struct SettingsView: View {
    let bottle: Bottle
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var fps = 0
    @State private var graphics = "dxvk"
    @State private var windows = "win10"
    @State private var hud = false
    @State private var loaded = false
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings: \(bottle.name)").font(.title2.bold())
            Form {
                Picker("Graphics", selection: $graphics) { Text("DXVK (recommended)").tag("dxvk"); Text("WineD3D").tag("wined3d") }
                Picker("Windows version", selection: $windows) { Text("Windows 11").tag("win11"); Text("Windows 10").tag("win10"); Text("Windows 7").tag("win7") }
                TextField("FPS limit (0 = unlimited)", value: $fps, format: .number)
                Toggle("Show FPS and GPU usage", isOn: $hud)
            }.disabled(!loaded || saving)
            Text("Close games before changing settings. Changes apply on the next launch.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            if !loaded && error == nil || saving { ProgressView().controlSize(.small) }
            HStack { Button("Close") { dismiss() }.disabled(saving); Spacer(); Button("Save") { Task { await save() } }.buttonStyle(.borderedProminent).disabled(!loaded || saving || fps < 0 || fps > 1000) }
        }.padding(28).frame(width: 470)
        .task {
            do {
                let value = try await model.cli.decode(BottleSettings.self, ["settings", bottle.name, "--json"])
                fps = value.fps; graphics = value.graphics; windows = value.windows; hud = value.hud; loaded = true
            } catch { self.error = error.localizedDescription }
        }
    }
    func save() async {
        saving = true; error = nil
        do {
            for (key, value) in [("fps", String(fps)), ("graphics", graphics), ("windows", windows), ("hud", hud ? "1" : "0")] {
                _ = try await model.cli.run(["set", bottle.name, key, value])
            }
            saving = false; dismiss(); await model.refresh()
        } catch { self.error = "Some settings may have been saved. \(error.localizedDescription)"; saving = false }
    }
}
