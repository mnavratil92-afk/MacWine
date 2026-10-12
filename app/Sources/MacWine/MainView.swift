import SwiftUI
import AppKit
import MacWineCore

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @State private var confirmKill = false
    @State private var bottleToDelete: Bottle?
    @State private var showDonationInfo = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    // Logo without background (tools/make-icon.swift, Resources/Logo.png); app icon in dev builds
                    Image(nsImage: Bundle.main.image(forResource: "Logo") ?? NSApp.applicationIconImage)
                        .resizable().interpolation(.high).scaledToFit().frame(width: 52, height: 62)
                    VStack(alignment: .leading) {
                        Text("MacWine").font(.title2.bold())
                    }.fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 18).padding(.horizontal, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        navigationRow("All Games", icon: "square.grid.2x2", value: "all", count: model.games.count)
                        sidebarHeading("STORES")
                        ForEach(Store.allCases.filter { $0 != .exe }) { store in
                            navigationRow(store.title, icon: storeIcon(store), value: "store:" + store.rawValue,
                                          count: model.games.filter { $0.store == store }.count)
                        }
                        sidebarHeading("CUSTOM BOTTLES")
                        ForEach(model.customBottles) { bottle in
                            navigationRow(bottle.name, icon: "shippingbox", value: "bottle:" + bottle.name,
                                          count: model.games.filter { $0.bottle == bottle.name }.count)
                                .contextMenu {
                                    Button("Delete Bottle…", role: .destructive) { bottleToDelete = bottle }.disabled(model.busy)
                                }
                        }
                        Button { model.showCreate = true } label: {
                            Label("Add Bottle…", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }.buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(model.busy)
                    }.padding(.horizontal, 12)
                }
                Button {
                    if let raw = Bundle.main.object(forInfoDictionaryKey: "MacWineDonationURL") as? String,
                       let url = URL(string: raw), url.scheme == "https", url.host != nil { NSWorkspace.shared.open(url) }
                    else { showDonationInfo = true }
                } label: { Label("Buy me a coffee", systemImage: "cup.and.saucer") }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.bottom, 18).help("Support the development of MacWine")
            }.navigationSplitViewColumnWidth(min: 205, ideal: 230, max: 280)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.title).font(.system(size: 28, weight: .bold))
                        Text(subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isCustomBottle {
                        Button("Delete Bottle…", role: .destructive) { bottleToDelete = model.currentBottle }.disabled(model.busy)
                        Button { model.chooseFile() } label: { Label("Run EXE…", systemImage: "play.fill") }.buttonStyle(.borderedProminent).tint(.teal).disabled(model.busy)
                    } else if let store = model.selectedStore {
                        Button(model.account(store)?.connected == true ? "Manage Connection" : "Connect \(store.title)") { model.showInstall = true }
                            .buttonStyle(.borderedProminent).tint(.teal).disabled(model.busy)
                    } else {
                        Button { model.showInstall = true } label: { Label("Connect a Store", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(.teal).disabled(model.busy)
                    }
                }
                if let store = model.selectedStore {
                    StoreStatusView(store: store)
                } else if model.isCustomBottle {
                    Text("Install your own Windows apps here. Use Run EXE to choose an .exe or .msi file.").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search games", text: $model.query).textFieldStyle(.roundedBorder)
                    Toggle("Installed only", isOn: $model.installedOnly).toggleStyle(.checkbox)
                }
                HStack {
                    Text("Library").font(.headline)
                    Text("\(model.visibleGames.count) \(model.visibleGames.count == 1 ? "game" : "games")").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                if model.visibleGames.isEmpty {
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: model.isCustomBottle ? "shippingbox" : "gamecontroller").font(.system(size: 48)).foregroundStyle(.secondary)
                        Text(emptyTitle).font(.title2.bold())
                        Text(emptyMessage).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                        if model.isCustomBottle {
                            Button("Install or Run EXE…") { model.chooseFile() }.disabled(model.busy)
                        } else if let store = model.selectedStore, model.account(store)?.connected == true {
                            Button("Open \(store.title)") { Task { await model.openStore(store) } }.disabled(model.busy)
                        } else {
                            Button(model.selectedStore.map { "Connect " + $0.title } ?? "Connect a Store") { model.showInstall = true }.buttonStyle(.borderedProminent).disabled(model.busy)
                        }
                    }.frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 245), spacing: 18)], spacing: 18) {
                            ForEach(model.visibleGames) { game in
                                GameCard(game: game)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                if !model.warnings.isEmpty {
                    DisclosureGroup("Library notices (\(model.warnings.count))") {
                        ScrollView { Text(model.warnings.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
                    }.foregroundStyle(.secondary)
                }
                HStack {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Button {
                            Task { await model.refresh() }
                        } label: { Label("Refresh Library", systemImage: "arrow.clockwise") }
                        .disabled(model.busy)
                        .help("Reload games and installation status from all connected stores.")
                        Divider()
                        Toggle("Create shortcuts automatically", isOn: $model.autoShortcuts)
                    } label: { Label("Library Options", systemImage: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().font(.caption)
                }
            }.padding(28)
            .background(Color(nsColor: .windowBackgroundColor))
            .toolbar {
                ToolbarItemGroup {
                    Button { Task { await model.sync() } } label: { Label("Refresh Library", systemImage: "arrow.clockwise") }.disabled(model.busy)
                    Button { model.showSettings = true } label: { Label("Bottle Settings", systemImage: "slider.horizontal.3") }.disabled(model.currentBottle == nil || model.busy)
                    Button { confirmKill = true } label: { Label("Stop Apps", systemImage: "stop.circle") }.disabled(model.currentBottle == nil || model.busy)
                }
            }
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .tint(.indigo)
        .task { await model.refresh() }
        .sheet(isPresented: $model.showCreate) { CreateBottleView().environmentObject(model) }
        .sheet(isPresented: $model.showOpenFile) { OpenFileView().environmentObject(model) }
        .sheet(isPresented: $model.showSettings) { if let bottle = model.currentBottle { SettingsView(bottle: bottle).environmentObject(model) } }
        .sheet(isPresented: $model.showInstall) { StoreView().environmentObject(model) }
        .sheet(item: $model.detail, onDismiss: {
            if let game = model.pendingGameLaunch {
                model.pendingGameLaunch = nil
                Task { await model.launch(game) }
            }
        }) { game in GameDetailView(game: game).environmentObject(model) }
        .alert("Could not complete the operation", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .alert("Delete bottle “\(bottleToDelete?.name ?? "")”?", isPresented: Binding(get: { bottleToDelete != nil }, set: { if !$0 { bottleToDelete = nil } })) {
            Button("Cancel", role: .cancel) { bottleToDelete = nil }
            Button("Move to Trash", role: .destructive) {
                if let bottle = bottleToDelete { Task { await model.deleteBottle(bottle) } }
                bottleToDelete = nil
            }
        } message: {
            Text("All apps, settings and saved files inside this bottle will be moved to the Trash. Close its running apps first. You can restore the bottle folder from the Trash.")
        }
        .alert("Support MacWine", isPresented: $showDonationInfo) { Button("Got It", role: .cancel) {} }
        message: { Text("Thank you for supporting the project. The author is still setting up a contribution link.") }
        .confirmationDialog("Stop all apps in \(model.selectedBottle ?? "this bottle")?", isPresented: $confirmKill) {
            Button("Stop Apps", role: .destructive) {
                if let bottle = model.selectedBottle { Task { await model.perform(["kill", bottle], message: "Stopping apps…", refreshAfter: true) } }
            }
        } message: { Text("Unsaved changes in these apps may be lost.") }
    }
    func sidebarHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(1)
            .foregroundStyle(.secondary).padding(.top, 22).padding(.bottom, 6).padding(.leading, 10)
    }
    func storeIcon(_ store: Store) -> String {
        switch store {
        case .steam: return "gamecontroller"
        case .epic: return "bolt"
        case .gog: return "square.stack.3d.up"
        case .ubisoft: return "circle.hexagongrid"
        case .exe: return "shippingbox"
        }
    }
    func navigationRow(_ title: String, icon: String, value: String, count: Int) -> some View {
        let selected = model.selection == value
        return Button {
            model.selection = value
            model.query = ""
            model.installedOnly = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 20)
                Text(title).fontWeight(selected ? .semibold : .regular)
                Spacer(minLength: 4)
                if count > 0 { Text(String(count)).font(.caption).monospacedDigit() }
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(selected ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(value)
    }
    var subtitle: String {
        if model.isCustomBottle { return "Your own Windows apps and installers" }
        if let store = model.selectedStore, model.completeStores.contains(store) { return "Your library · Ready to play or install" }
        if let store = model.selectedStore { return "Games from \(store.title)" }
        return "All your games in one place"
    }
    var emptyTitle: String {
        if !model.query.isEmpty || model.installedOnly { return "No matching games" }
        if model.isCustomBottle { return "Your bottle is ready" }
        if let store = model.selectedStore { return model.account(store)?.connected == true ? "No games to show yet" : "Connect \(store.title)" }
        return "Build your library"
    }
    var emptyMessage: String {
        if !model.query.isEmpty || model.installedOnly { return "Try another search or turn off the installed-only filter." }
        if model.isCustomBottle { return "Choose a Windows installer or app to get started." }
        if let store = model.selectedStore {
            return model.account(store)?.connected == true
                ? "Refresh your library after signing in or installing games in \(store.title)."
                : "Sign in to \(store.title) to get started. Your available games will appear here."
        }
        return "Connect a store to access its library, or add a custom bottle for your own Windows apps."
    }
}

struct StoreStatusView: View {
    let store: Store
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.completeStores.contains(store) ? "checkmark.circle" : "info.circle").foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.completeStores.contains(store) ? "Account library" : (model.account(store)?.connected == true ? "Loading your library" : "Not signed in")).font(.callout.bold())
                Text(model.storeMessages[store] ?? model.account(store)?.message ?? "Connect your account to check library availability. Installed games already on this Mac appear below.")
                    .font(.caption).foregroundStyle(.secondary)
                if let name = model.account(store)?.accountName, !name.isEmpty { Text(name).font(.caption) }
            }
            Spacer()
            if model.account(store)?.connected == true {
                Button("Open Store") { Task { await model.openStore(store) } }.disabled(model.busy)
            }
        }.padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

