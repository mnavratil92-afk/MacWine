import SwiftUI

struct AppRootView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Group {
            if model.runtimeReady { MainView() }
            else { RuntimeSetupView() }
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .task { await model.prepareRuntime() }
    }
}

struct RuntimeSetupView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "desktopcomputer").font(.system(size: 48)).foregroundStyle(.indigo)
            Text(title).font(.title.bold())
            Text("MacWine needs Windows compatibility components to run your games. Your games and saved data stay in place.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.runtimeChecking {
                ProgressView("Checking components…")
            } else if model.runtimeInstalling {
                VStack(spacing: 10) {
                    ProgressView(value: model.runtimeProgress, total: 100)
                    Text(model.runtimeProgress >= 100 ? "Verifying and preparing components…" : "Downloading… \(Int(model.runtimeProgress))%")
                        .font(.callout).monospacedDigit()
                    Text("Keep MacWine open until setup finishes.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                if let error = model.runtimeError {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).lineLimit(8)
                }
                if model.runtimeStatus != nil {
                    Text("About 200 MB to download. An internet connection is required.").font(.caption).foregroundStyle(.secondary)
                    Button(model.runtimeError == nil ? "Download Components" : "Retry Download") {
                        Task { await model.installRuntime() }
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Button("Retry") { Task { await model.prepareRuntime() } }.buttonStyle(.borderedProminent)
                }
            }
        }.frame(maxWidth: 460).padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    var title: String {
        if model.runtimeInstalling { return "Setting up MacWine" }
        if model.runtimeError != nil { return "Setup needs attention" }
        return "Get ready to play"
    }
}
