import SwiftUI
import WebKit

final class WebDetailCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var onDismiss: (() -> Void)?
    var onLoadingChange: ((Bool) -> Void)?
    /// Quando `true`, permite carregar a URL de logout do Bunker e fecha ao terminar.
    var isLogoutFlow = false
    private var hasDismissed = false

    // MARK: - Script Message Handler (Intercepta Voltar da Web)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "menuBack" {
            dismissOnce()
        }
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onLoadingChange?(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadingChange?(false)

        if isLogoutFlow {
            AppLogger.logSuccess(.auth, operation: "WebDetail.logout", details: "Logout web concluído: \(webView.url?.absoluteString ?? "")")
            dismissOnce()
            return
        }

        if let url = webView.url?.absoluteString.lowercased(), shouldDismissMenu(for: url) {
            dismissOnce()
            return
        }
        webView.evaluateJavaScript(Self.backButtonJavaScript, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadingChange?(false)
        if isLogoutFlow {
            AppLogger.logFailure(.auth, operation: "WebDetail.logout.didFail", error: error)
            dismissOnce()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadingChange?(false)
        if isLogoutFlow {
            AppLogger.logFailure(.auth, operation: "WebDetail.logout.didFailProvisional", error: error)
            dismissOnce()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // No logout, a URL alvo do Bunker precisa carregar (pode ser intro.do ou app.do).
        if isLogoutFlow {
            decisionHandler(.allow)
            return
        }

        if let url = navigationAction.request.url?.absoluteString.lowercased(), shouldDismissMenu(for: url) {
            decisionHandler(.cancel)
            dismissOnce()
            return
        }
        decisionHandler(.allow)
    }

    private func shouldDismissMenu(for url: String) -> Bool {
        // Voltar ao menu/login fecha o fullScreenCover e retorna à Home nativa (ou logout).
        url.contains("novomenu") || url.contains("intro.do") || url.contains("app.do")
    }

    private func dismissOnce() {
        guard !hasDismissed else { return }
        hasDismissed = true
        onDismiss?()
    }

    static let backButtonJavaScript = """
    (function() {
      if (window.__postosValleMenuBackInstalled) { return; }
      window.__postosValleMenuBackInstalled = true;
      function notifyBack() {
        try { window.webkit.messageHandlers.menuBack.postMessage('back'); } catch (e) {}
      }
      function isBack(el) {
        if (!el || el === document.body) return false;
        var href = (el.getAttribute && (el.getAttribute('href') || '') || '').toLowerCase();
        var onclick = (el.getAttribute && (el.getAttribute('onclick') || '') || '').toLowerCase();
        var cls = ((el.className && el.className.toString) ? el.className.toString() : '').toLowerCase();
        if (href.indexOf('novomenu') >= 0 || href.indexOf('intro.do') >= 0 || href.indexOf('app.do') >= 0) return true;
        if (onclick.indexOf('novomenu') >= 0 || onclick.indexOf('intro.do') >= 0 || onclick.indexOf('app.do') >= 0) return true;
        if (cls.indexOf('voltar') >= 0 || cls.indexOf('back') >= 0) return true;
        return false;
      }
      document.addEventListener('click', function(e) {
        var el = e.target;
        for (var i = 0; i < 6 && el; i++) {
          if (isBack(el)) {
            e.preventDefault();
            e.stopPropagation();
            notifyBack();
            return false;
          }
          el = el.parentElement;
        }
      }, true);
    })();
    """
}

/// WebView em tela cheia sem chrome nativo — a navegação vem do próprio Bunker.
struct WebDetailSheetView: View {
    let url: URL
    let title: String
    var isLogoutFlow: Bool = false
    let onDismiss: () -> Void

    @State private var isLoading = true
    @State private var coordinator = WebDetailCoordinator()

    var body: some View {
        ZStack {
            PostosValleColors.primaryBlue.ignoresSafeArea()

            WebDetailRepresentable(url: url, coordinator: coordinator)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)

            if isLoading {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
            }
        }
        .onAppear {
            coordinator.isLogoutFlow = isLogoutFlow
            coordinator.onDismiss = onDismiss
            coordinator.onLoadingChange = { loading in
                self.isLoading = loading
            }
        }
    }
}

struct WebDetailRepresentable: UIViewRepresentable {
    let url: URL
    let coordinator: WebDetailCoordinator

    func makeCoordinator() -> WebDetailCoordinator {
        coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let contentController = configuration.userContentController
        contentController.add(context.coordinator, name: "menuBack")
        contentController.addUserScript(WKUserScript(
            source: WebDetailCoordinator.backButtonJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = UIColor(PostosValleColors.primaryBlue)
        webView.isOpaque = false
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: WebDetailCoordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "menuBack")
    }
}
