import SwiftUI
import AppKit
import MacWineCore

private struct LoginResponse: Decodable { let loginURL: String }

struct StoreView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var bottle = ""
    @State private var store = Store.steam
    @State private var working = false
    @State private var error: String?
    @State private var notice: String?
    @State private var authCode = ""
    @State private var steamKey = ""
    @State private var awaitingEpicCode = false
    @State private var loginURL: URL?
    @State private var showLogin = false
    @State private var confirmDisconnect = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect a Store").font(.title2.bold())
            Text("Sign in with the store. MacWine never asks for your account password.").foregroundStyle(.secondary)
            Picker("Store", selection: $store) {
                ForEach(Store.allCases.filter { $0 != .exe }) { Text($0.title).tag($0) }
            }.disabled(working).onChange(of: store) { value in
                bottle = value.rawValue
                authCode = ""; steamKey = ""; awaitingEpicCode = false; error = nil; notice = nil
            }
            Text(model.bottles.contains(where: { $0.name == bottle })
                 ? "\(store.title) games use their own Windows environment “\(bottle)”."
                 : "A Windows environment “\(bottle)” will be created for \(store.title) games.").font(.caption).foregroundStyle(.secondary)
            if store == .ubisoft {
                Label("Sign in once in Ubisoft Connect. MacWine then shows your Ubisoft library; games download and start through Ubisoft Connect, which MacWine opens for you.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button(store == .epic || store == .gog ? "Sign In with \(store.title)" : "Open \(store.title) to Sign In") { Task { await connect() } }
                .buttonStyle(.borderedProminent).disabled(working || model.busy)
            if store == .steam {
                DisclosureGroup("Sync owned games from Steam") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("After signing in to Steam, add your Steam Web API key to load owned games that are not installed. Your game details must be visible to the API.").font(.caption).foregroundStyle(.secondary)
                        Link("Get your Steam Web API key", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                        SecureField("Steam Web API key", text: $steamKey).textFieldStyle(.roundedBorder)
                        Text("Stored in macOS Keychain. Never added to the project or sent in process arguments.").font(.caption2).foregroundStyle(.secondary)
                        Button("Save Key and Sync") { Task { await saveKey() } }.disabled(working || steamKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(.top, 8)
                }
            }
            if (store == .epic || store == .gog) && awaitingEpicCode {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store == .epic
                         ? "Sign in in your browser. Epic then shows a page of text with \"authorizationCode\". Select all of it (⌘A), copy it (⌘C) and click the button below."
                         : "Sign in in your browser. When the page says you are signed in, copy the address from the address bar (⌘L, ⌘C) and click the button below.").font(.callout)
                    Button("Paste from Clipboard and Sign In") {
                        authCode = NSPasteboard.general.string(forType: .string) ?? ""
                        Task { await finishEpic() }
                    }.buttonStyle(.borderedProminent).disabled(working)
                    HStack {
                        SecureField("Or paste the code or page text here", text: $authCode).textFieldStyle(.roundedBorder)
                        Button("Sign In") { Task { await finishEpic() } }.disabled(working || authCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("The code works only once and for a few minutes. Never share it with anyone.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled).lineLimit(6) }
            if working { ProgressView("Working…").controlSize(.small) }
            Divider()
            HStack {
                if model.account(store)?.connected == true {
                    Button("Disconnect", role: .destructive) { confirmDisconnect = true }.disabled(working)
                }
                Spacer()
                Button("Refresh Library") { Task { await model.refresh(); notice = "Library refreshed. If sign-in is still in progress, refresh again when it finishes." } }.disabled(working || model.busy)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
            }
        }.padding(28).frame(width: 510)
        .onAppear {
            store = model.selectedStore ?? .steam
            bottle = store.rawValue
        }
        .onDisappear { authCode = ""; steamKey = "" }
        .sheet(isPresented: $showLogin) {
            if let loginURL {
                LoginSheet(store: store, url: loginURL,
                           onCode: { code in authCode = code; Task { await finishEpic() } },
                           onBrowser: { NSWorkspace.shared.open(loginURL); awaitingEpicCode = true })
            }
        }
        .confirmationDialog("Disconnect \(store.title) from MacWine?", isPresented: $confirmDisconnect) {
            Button("Disconnect", role: .destructive) { Task {
                working = true
                do {
                    _ = try await model.cli.run(["disconnect", store.rawValue]); await model.refresh()
                    notice = "Disconnected from MacWine. Your store account and installed games are unchanged."
                } catch { self.error = error.localizedDescription }
                working = false
            } }
        } message: { Text("This removes the local account link and saved sign-in data. It does not delete your store account or games.") }
    }
    func connect() async {
        working = true; error = nil; notice = nil
        do {
            if store == .epic || store == .gog {
                let result = try await model.cli.decode(LoginResponse.self, ["connect", store.rawValue, "--bottle", bottle, "--json"])
                let domain = store == .epic ? "epicgames.com" : "gog.com"
                guard let url = URL(string: result.loginURL), url.scheme == "https",
                      let host = url.host, host == domain || host.hasSuffix("." + domain) else {
                    throw CLIError(message: "MacWine returned an unexpected \(store.title) sign-in address.")
                }
                loginURL = url; showLogin = true
            } else {
                _ = try await model.cli.run(["connect", store.rawValue, "--bottle", bottle, "--detach"])
                notice = "Finish signing in in \(store.title), then refresh your library here."
            }
            model.selection = "store:" + store.rawValue
            await model.refresh()
        } catch { self.error = error.localizedDescription }
        working = false
    }
    func saveKey() async {
        let key = steamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty && key.utf8.count < 4096 else { error = "Enter a valid Steam Web API key."; return }
        working = true; error = nil
        do {
            _ = try await model.cli.run(["set-key", "steam"], input: Data((key + "\n").utf8))
            steamKey = ""
            _ = try await model.cli.run(["sync", "steam", "--bottle", bottle])
            await model.refresh(); notice = "Steam library synced."
        } catch { self.error = error.localizedDescription.replacingOccurrences(of: key, with: "[redacted]") }
        working = false
    }
    func finishEpic() async {
        let code = authCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty && code.utf8.count < 8192 else { error = "Copy the sign-in result from \(store.title) first."; return }
        working = true; error = nil
        do {
            _ = try await model.cli.run(["connect", store.rawValue, "--bottle", bottle, "--code-stdin"], input: Data((code + "\n").utf8))
            authCode = ""; awaitingEpicCode = false
            notice = "\(store.title) connected. Loading your library…"
            await model.refresh(); notice = "\(store.title) connected."
        } catch { authCode = ""; self.error = error.localizedDescription.replacingOccurrences(of: code, with: "[redacted]") }
        working = false
    }
}
