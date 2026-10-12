import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MacWineCore

@MainActor
final class AppModel: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var artworkVersion = 0   // bumped when a custom game image changes
    @Published var games: [Game] = []
    @Published var accounts: [StoreAccount] = []
    @Published var selection: String? = "all"
    @Published var query = ""
    @Published var installedOnly = false
    @Published var busy = false
    @Published var status = ""
    @Published var error: String?
    @Published var warnings: [String] = []
    @Published var storeMessages: [Store: String] = [:]
    @Published var completeStores = Set<Store>()
    @Published var showCreate = false
    @Published var showOpenFile = false
    @Published var showSettings = false
    @Published var pendingFile: URL?
    @Published var detail: Game?
    var pendingGameLaunch: Game?
    @Published var showInstall = false
    @Published var autoShortcuts = UserDefaults.standard.bool(forKey: "automaticShortcuts") {
        didSet { UserDefaults.standard.set(autoShortcuts, forKey: "automaticShortcuts") }
    }
    @Published var runtimeReady = false
    @Published var runtimeChecking = false
    @Published var runtimeInstalling = false
    @Published var runtimeProgress: Double = 0
    @Published var runtimeError: String?
    @Published var runtimeStatus: RuntimeStatus?
    let cli = CLI.locate()
    func prepareRuntime() async {
        guard !runtimeChecking && !runtimeInstalling else { return }
        runtimeChecking = true; runtimeError = nil
        defer { runtimeChecking = false }
        do {
            let value = try await cli.decode(RuntimeStatus.self, ["runtime", "status", "--json"])
            runtimeStatus = value; runtimeReady = value.isReady
        } catch { runtimeReady = false; runtimeError = error.localizedDescription }
    }
    func installRuntime() async {
        guard !runtimeChecking && !runtimeInstalling else { return }
        runtimeInstalling = true; runtimeError = nil; runtimeProgress = 0
        defer { runtimeInstalling = false }
        do {
            _ = try await cli.run(["runtime", "install", "--json"], onStderrLine: { [weak self] line in
                guard let percent = RuntimeProgress.percent(from: line) else { return }
                await self?.updateRuntimeProgress(percent)
            })
            let value = try await cli.decode(RuntimeStatus.self, ["runtime", "status", "--json"])
            runtimeStatus = value
            guard value.isReady else { throw CLIError(message: "The required components are not ready yet. Please try again.") }
            runtimeReady = true
        } catch { runtimeError = error.localizedDescription; runtimeReady = false }
    }
    private func updateRuntimeProgress(_ value: Double) { runtimeProgress = max(runtimeProgress, value) }

    var selectedStore: Store? {
        guard let selection, selection.hasPrefix("store:") else { return nil }
        return Store(rawValue: String(selection.dropFirst(6)))
    }
    var selectedBottle: String? {
        if let selection, selection.hasPrefix("bottle:") { return String(selection.dropFirst(7)) }
        if let selectedStore { return account(selectedStore)?.bottle }
        return nil
    }
    var isCustomBottle: Bool { selection?.hasPrefix("bottle:") == true }
    var title: String { selectedStore?.title ?? (isCustomBottle ? selectedBottle ?? "Custom Bottle" : "All Games") }
    var currentBottle: Bottle? { bottles.first { $0.name == selectedBottle } }
    func account(_ store: Store) -> StoreAccount? { accounts.first { $0.store == store } }
    var customBottles: [Bottle] {
        // Store bottles (named after the store, or linked to a store account) belong under Stores
        let stores = Set(Store.allCases.filter { $0 != .exe }.map(\.rawValue))
        let linked = Set(accounts.compactMap(\.bottle))
        return bottles.filter { !linked.contains($0.name) && !stores.contains($0.name) }
    }
    var visibleGames: [Game] {
        games.filter { game in
            (selectedStore == nil || game.store == selectedStore) &&
            (!isCustomBottle || game.bottle == selectedBottle) &&
            (!installedOnly || game.installed) &&
            (query.isEmpty || game.name.localizedCaseInsensitiveContains(query))
        }
    }
    func refresh() async {
        guard !busy else { return }
        busy = true; status = "Refreshing library…"
        defer { busy = false }
        do {
            let list = try await cli.decode([Bottle].self, ["list", "--json"])
            let result = await Task.detached { LibraryScanner().scan(list) }.value
            bottles = list; warnings = result.warnings; storeMessages = [:]; completeStores = []
            var merged = result.games
            var loadedStores = Set<Store>()
            do { accounts = try await cli.decode([StoreAccount].self, ["accounts", "--json"]) }
            catch { accounts = []; warnings.append("Account services are unavailable. Showing local installations only.") }
            for account in accounts where account.connected {
                do {
                    let library = try await cli.decode(StoreLibrary.self, ["library", account.store.rawValue, "--json"])
                    loadedStores.insert(account.store)
                    merged = LibraryMerge.merge(local: merged, owned: library.games, store: account.store, bottle: account.bottle ?? "")
                    if library.complete || account.fullLibrary == true { completeStores.insert(account.store) }
                    storeMessages[account.store] = library.message ?? account.message
                } catch { storeMessages[account.store] = "Could not refresh your account library. Local installations are still available. " + error.localizedDescription }
            }
            if accounts.contains(where: { $0.status == "needs-sync" }),
               let latest = try? await cli.decode([StoreAccount].self, ["accounts", "--json"]) {
                accounts = latest
                for account in latest where loadedStores.contains(account.store) && account.fullLibrary == true {
                    completeStores.insert(account.store)
                }
            }
            games = merged.map { game in
                guard let exe = game.executable, !exe.hasPrefix("/"), let bottle = list.first(where: { $0.name == game.bottle }),
                      let path = LibraryScanner().windowsURL(exe, bottle: URL(fileURLWithPath: bottle.path))?.path else { return game }
                return Game(bottle: game.bottle, store: game.store, storeID: game.storeID, name: game.name, installed: game.installed, executable: path, artworkURL: game.artworkURL)
            }
            if isCustomBottle, !list.contains(where: { $0.name == selectedBottle }) { selection = "all" }
            status = "\(games.count) games · \(games.filter(\.installed).count) installed"
            if autoShortcuts {
                var saved = Set(UserDefaults.standard.stringArray(forKey: "createdShortcuts") ?? [])
                for game in games where game.installed && !game.bottle.isEmpty && !saved.contains(game.id) {
                    do {
                        _ = try await cli.run(shortcutArguments(game)); saved.insert(game.id)
                        UserDefaults.standard.set(Array(saved), forKey: "createdShortcuts")
                    } catch { warnings.append("Shortcut for \(game.name): \(error.localizedDescription)") }
                }
            }
        } catch { self.error = error.localizedDescription; status = "Could not load the library" }
    }
    func perform(_ args: [String], message: String, refreshAfter: Bool = false) async {
        guard !busy else { return }
        busy = true; status = message; error = nil
        do { _ = try await cli.run(args); status = "Done" }
        catch { self.error = error.localizedDescription; status = "Operation failed" }
        busy = false
        if refreshAfter { await refresh() }
    }
    func deleteBottle(_ bottle: Bottle) async {
        guard !busy else { return }
        busy = true; error = nil
        do {
            let latest = try await cli.decode([Bottle].self, ["list", "--json"])
            let linked = try await cli.decode([StoreAccount].self, ["accounts", "--json"])
            guard let current = latest.first(where: { $0.name == bottle.name && $0.path == bottle.path }),
                  !Store.allCases.contains(where: { $0.rawValue == bottle.name }),
                  !linked.contains(where: { $0.bottle == bottle.name }) else {
                throw CLIError(message: "This bottle is connected to a store or is no longer available. Refresh your library first.")
            }
            guard !current.running else { throw CLIError(message: "Close all apps in this bottle before deleting it.") }
            let folder = URL(fileURLWithPath: current.path).standardizedFileURL
            guard folder.lastPathComponent == current.name, folder.deletingLastPathComponent().lastPathComponent == "bottles",
                  folder.resolvingSymlinksInPath() == folder else {
                throw CLIError(message: "This bottle has an unexpected folder location and cannot be moved to the Trash.")
            }
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            if selectedBottle == current.name { selection = "all" }
            busy = false
            await refresh()
            status = "Bottle moved to Trash"
        } catch { self.error = error.localizedDescription; busy = false }
    }
    func sync() async {
        if let store = selectedStore, account(store)?.connected == true {
            await perform(["sync", store.rawValue], message: "Syncing \(store.title)…", refreshAfter: true)
        } else { await refresh() }
    }
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Windows app or installer"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [UTType(filenameExtension: "exe"), UTType(filenameExtension: "msi")].compactMap { $0 }
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { pendingFile = url; showOpenFile = true }
    }
    func launch(_ game: Game) async {
        guard !game.bottle.isEmpty else { selection = "store:" + game.store.rawValue; showInstall = true; return }
        await perform([game.installed ? "launch" : "install", game.bottle, game.store.rawValue, game.launchID, "--detach"], message: game.installed ? "Launching \(game.name)…" : "Opening installation for \(game.name)…")
        if !game.installed && error == nil { status = "Installation requested. Refresh the library after it finishes." }
    }
    func openStore(_ store: Store) async {
        guard let bottle = account(store)?.bottle, !bottle.isEmpty else { showInstall = true; return }
        await perform(["setup-store", bottle, store.rawValue, "--detach"], message: "Opening \(store.title)…")
    }
    func shortcutArguments(_ game: Game, destination: String? = nil) -> [String] {
        let title = "\(game.name) (\(game.bottle))".components(separatedBy: .controlCharacters).joined(separator: " ").replacingOccurrences(of: "/", with: "-")
        var args = ["shortcut", game.bottle, game.store.rawValue, game.launchID, "--name", String(title.prefix(150)), "--dest", destination ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path, "--json"]
        if let custom = customArtwork(game) { args += ["--icon", custom.path] }
        else if let executable = game.executable { args += ["--icon", executable] }
        return args
    }
    // Custom game images (for games without cover art): ~/Library/Application Support/MacWine/Artwork
    func customArtworkURL(_ game: Game) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacWine/Artwork")
        let name = Data("\(game.store.rawValue)/\(game.storeID)".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return dir.appendingPathComponent(String(name.prefix(180)) + ".png")
    }
    func customArtwork(_ game: Game) -> URL? {
        let url = customArtworkURL(game)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func chooseArtwork(_ game: Game) {
        let panel = NSOpenPanel(); panel.title = "Choose an image for \(game.name)"; panel.prompt = "Use Image"
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard let image = NSImage(contentsOf: source), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            error = "This image could not be read."; return
        }
        let target = customArtworkURL(game)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: target, options: .atomic)
            artworkVersion += 1
        } catch { self.error = "Could not save the image: \(error.localizedDescription)" }
    }
    func removeArtwork(_ game: Game) {
        try? FileManager.default.removeItem(at: customArtworkURL(game))
        artworkVersion += 1
    }
    func shortcut(_ game: Game) {
        let panel = NSOpenPanel(); panel.title = "Save game shortcut"; panel.prompt = "Save Here"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        if panel.runModal() == .OK, let url = panel.url {
            Task { await perform(shortcutArguments(game, destination: url.path), message: "Creating shortcut…") }
        }
    }
}
