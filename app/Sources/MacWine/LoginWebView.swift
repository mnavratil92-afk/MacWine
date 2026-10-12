import SwiftUI
import WebKit
import MacWineCore

/// Store sign-in inside MacWine: the store's own web page in a private web view. MacWine never sees the
/// password - it only picks up the one-time authorization code the store hands out after sign-in.
struct LoginWebView: NSViewRepresentable {
    let store: Store
    let url: URL
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(store: store, onCode: onCode) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()   // no cookies or sessions kept after the sheet closes
        let view = WKWebView(frame: .zero, configuration: config)
        // Store sign-in pages reject unknown embedded browsers; present as Safari.
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let store: Store
        let onCode: (String) -> Void
        private var done = false
        init(store: Store, onCode: @escaping (String) -> Void) { self.store = store; self.onCode = onCode }

        private func deliver(_ code: String) {
            guard !done, !code.isEmpty else { return }
            done = true
            DispatchQueue.main.async { self.onCode(code) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // GOG: the final redirect carries ?code=... - take it and stop loading.
            if store == .gog, let url = action.request.url, url.host == "embed.gog.com", url.path == "/on_login_success",
               let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value {
                decisionHandler(.cancel); deliver(code); return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Epic: the redirect endpoint shows JSON with "authorizationCode".
            guard store == .epic, let url = webView.url, url.host?.hasSuffix("epicgames.com") == true, url.path.hasSuffix("/id/api/redirect") else { return }
            webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
                guard let text = result as? String, let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let code = json["authorizationCode"] as? String else { return }
                self?.deliver(code)
            }
        }
    }
}

struct LoginSheet: View {
    let store: Store
    let url: URL
    let onCode: (String) -> Void
    let onBrowser: () -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                Text("Sign in to \(store.title)").font(.headline)
                Spacer()
                Button("Use My Browser Instead") { dismiss(); onBrowser() }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(12)
            Divider()
            LoginWebView(store: store, url: url) { code in dismiss(); onCode(code) }
        }.frame(width: 720, height: 760)
    }
}
