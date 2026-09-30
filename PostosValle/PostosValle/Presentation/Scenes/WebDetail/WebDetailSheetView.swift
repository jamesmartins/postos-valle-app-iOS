import Combine
import SwiftUI
import WebKit

/// Process pool compartilhado com o Login — mantém cookies/sessão Bunker entre as WebViews.
enum SharedWebKit {
    static let processPool = WKProcessPool()
}

final class WebDetailCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var onDismiss: (() -> Void)?
    var onLoadingChange: ((Bool) -> Void)?
    var onLoadError: ((String) -> Void)?
    /// Quando `true`, permite carregar a URL de logout do Bunker e fecha ao terminar.
    var isLogoutFlow = false
    private var hasDismissed = false
    /// Ignora auto-dismiss na primeira navegação (redirects iniciais do Bunker).
    private var didFinishInitialLoad = false
    /// Evita reload em loop no `updateUIView`.
    var lastAppliedReloadToken = 0

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "menuBack" {
            dismissOnce()
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onLoadingChange?(true)
        AppLogger.info(.app, "🌐 [WebDetail] Iniciando: \(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadingChange?(false)
        didFinishInitialLoad = true
        AppLogger.logSuccess(.app, operation: "WebDetail.didFinish", details: webView.url?.absoluteString ?? "")

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
        AppLogger.logFailure(.app, operation: "WebDetail.didFail", error: error)
        if isLogoutFlow {
            dismissOnce()
            return
        }
        if !isCancelled(error) {
            onLoadError?(userFacingMessage(for: error))
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadingChange?(false)
        AppLogger.logFailure(.app, operation: "WebDetail.didFailProvisional", error: error)
        if isLogoutFlow {
            dismissOnce()
            return
        }
        if !isCancelled(error) {
            onLoadError?(userFacingMessage(for: error))
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if isLogoutFlow {
            decisionHandler(.allow)
            return
        }

        let urlString = navigationAction.request.url?.absoluteString.lowercased() ?? ""

        // Só fecha em navegação do usuário após a 1ª carga — evita fechar no redirect inicial
        if didFinishInitialLoad,
           navigationAction.navigationType != .other,
           shouldDismissMenu(for: urlString) {
            AppLogger.info(.app, "WebDetail: navegação de retorno detectada → \(urlString)")
            decisionHandler(.cancel)
            dismissOnce()
            return
        }
        decisionHandler(.allow)
    }

    /// Fecha o card ao voltar para menu — path específico evita falso positivo com cadastro_*.do
    private func shouldDismissMenu(for url: String) -> Bool {
        if url.contains("novomenu") || url.contains("intro.do") {
            return true
        }
        // Login: somente `/app/app.do` (não confundir com `/app/cadastro...`)
        if url.contains("/app/app.do") {
            return true
        }
        return false
    }

    private func isCancelled(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    private func userFacingMessage(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "Sem conexão com a internet."
            case NSURLErrorTimedOut:
                return "A página demorou para responder. Tente novamente."
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return "Não foi possível conectar ao servidor."
            default:
                break
            }
        }
        return "Não foi possível carregar a página."
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
        if (href.indexOf('novomenu') >= 0 || href.indexOf('intro.do') >= 0 || href.indexOf('/app/app.do') >= 0) return true;
        if (onclick.indexOf('novomenu') >= 0 || onclick.indexOf('intro.do') >= 0 || onclick.indexOf('/app/app.do') >= 0) return true;
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
    @State private var loadError: String?
    @StateObject private var holder = WebDetailCoordinatorHolder()

    var body: some View {
        ZStack {
            PostosValleColors.brandGreen.ignoresSafeArea()

            WebDetailRepresentable(
                url: url,
                coordinator: holder.coordinator,
                reloadToken: holder.reloadToken
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .opacity(loadError == nil ? 1 : 0)

            if isLoading && loadError == nil {
                Color.black.opacity(0.15).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
                    .accessibilityLabel("Carregando \(title)")
            }

            if let loadError {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white)
                        .accessibilityHidden(true)

                    Text("Não foi possível abrir \(title)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(loadError)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        Button("Voltar") {
                            onDismiss()
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PostosValleColors.brandGreen)
                        .frame(minWidth: 120, minHeight: 44)
                        .background(Color.white)
                        .cornerRadius(10)

                        Button("Tentar de novo") {
                            self.loadError = nil
                            self.isLoading = true
                            holder.reloadToken += 1
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(minWidth: 120, minHeight: 44)
                        .background(Color.white.opacity(0.25))
                        .cornerRadius(10)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .onAppear {
            AppLogger.info(.app, "WebDetail abrindo '\(title)': \(url.absoluteString)")
            holder.coordinator.isLogoutFlow = isLogoutFlow
            holder.coordinator.onDismiss = onDismiss
            holder.coordinator.onLoadingChange = { loading in
                self.isLoading = loading
            }
            holder.coordinator.onLoadError = { message in
                self.loadError = message
            }
        }
    }
}

@MainActor
final class WebDetailCoordinatorHolder: ObservableObject {
    let coordinator = WebDetailCoordinator()
    @Published var reloadToken = 0
}

struct WebDetailRepresentable: UIViewRepresentable {
    let url: URL
    let coordinator: WebDetailCoordinator
    var reloadToken: Int = 0

    func makeCoordinator() -> WebDetailCoordinator {
        coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = SharedWebKit.processPool
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let contentController = configuration.userContentController
        contentController.add(context.coordinator, name: "menuBack")
        contentController.addUserScript(WKUserScript(
            source: WebDetailCoordinator.backButtonJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = UIColor(PostosValleColors.brandGreen)
        webView.isOpaque = false
        webView.scrollView.bounces = true
        webView.accessibilityLabel = "Conteúdo web"

        AppLogger.info(.app, "WebDetail WKWebView.load → \(url.absoluteString)")
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard reloadToken > 0, reloadToken != context.coordinator.lastAppliedReloadToken else { return }
        context.coordinator.lastAppliedReloadToken = reloadToken
        AppLogger.info(.app, "WebDetail reload (\(reloadToken)) → \(url.absoluteString)")
        uiView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: WebDetailCoordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "menuBack")
    }
}
