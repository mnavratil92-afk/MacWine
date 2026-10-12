import SwiftUI
import Sparkle
import Combine

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    let configured: Bool
    private let controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        let feed = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:))
        let key = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).flatMap { Data(base64Encoded: $0) }
        configured = feed?.scheme == "https" && feed?.host != nil && key?.count == 32
        guard configured else { controller = nil; return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main).assign(to: &$automaticallyChecks)
        // Packaging sets SUEnableAutomaticChecks=true as the default. Sparkle owns the saved preference.
        controller.startUpdater()
    }
    func check() { controller?.checkForUpdates(nil) }
    func setAutomaticallyChecks(_ value: Bool) { controller?.updater.automaticallyChecksForUpdates = value }
}
