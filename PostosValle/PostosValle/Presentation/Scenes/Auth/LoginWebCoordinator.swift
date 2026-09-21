import SwiftUI
import WebKit
import LocalAuthentication

final class LoginWebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var onLoginSuccess: ((_ cpf: String?, _ idU: String, _ idL: String?) -> Void)?
    var onDismiss: (() -> Void)?
    var onLoadingChange: ((Bool) -> Void)?
    var onErrorMessage: ((String?) -> Void)?

    weak var activeWebView: WKWebView?

    private var candidateURLs: [URL] = []
    private var currentCandidateIndex = 0
    private var hasSucceededLoadingPage = false
    private var hasReportedSuccess = false
    private var capturedCPF: String?
    private let sessionUseCase: ManageSessionUseCase

    init(sessionUseCase: ManageSessionUseCase, candidateURLs: [URL] = []) {
        self.sessionUseCase = sessionUseCase
        self.capturedCPF = sessionUseCase.currentSession().cpf
        self.candidateURLs = candidateURLs
        super.init()
    }

    func setCandidateURLs(_ urls: [URL]) {
        self.candidateURLs = urls
        self.currentCandidateIndex = 0
    }

    // MARK: - Script Message Handler (CPF Capture)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "cpfCapture", let value = message.body as? String else { return }
        let digits = value.filter(\.isNumber)
        if digits.count >= 10 && digits.count <= 11 {
            self.capturedCPF = digits
            self.sessionUseCase.save(cpf: digits)
            AppLogger.logSuccess(
                .auth,
                operation: "LoginWebCoordinator.cpfCapture",
                details: "CPF capturado com sucesso (\(digits.prefix(3)).***.***-\(digits.suffix(2)))"
            )
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let current = webView.url?.absoluteString ?? candidateURLs.first?.absoluteString ?? "URL pendente"
        AppLogger.info(.auth, "🌐 [LoginWebView] Iniciando navegação provisória para: \(current)")
        onLoadingChange?(true)
        onErrorMessage?(nil)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        AppLogger.info(.auth, "📥 [LoginWebView] Recebendo conteúdo da página (didCommit)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url?.absoluteString else {
            onLoadingChange?(false)
            return
        }

        AppLogger.logSuccess(.auth, operation: "LoginWebView.didFinish", details: "Página carregada: \(url)")

        // 1. Verificar se a resposta do servidor veio vazia (ex: chave rejeitada pelo Bunker retornando 3 bytes)
        webView.evaluateJavaScript("document.body ? (document.body.innerText || document.body.innerHTML || '').trim() : ''") { [weak self] result, _ in
            guard let self = self else { return }
            let bodyText = (result as? String) ?? ""

            if bodyText.isEmpty && !url.contains("novoMenu") {
                AppLogger.warning(.auth, "⚠️ [LoginWebView] Página carregou vazia (sem conteúdo no body) para a URL: \(url)")
                if self.canTryNextCandidate() {
                    self.tryNextCandidate(in: webView)
                    return
                } else {
                    self.onLoadingChange?(false)
                    self.onErrorMessage?("A página retornou sem conteúdo. Tente recarregar ou verifique as configurações da conta.")
                    return
                }
            }

            self.hasSucceededLoadingPage = true
            self.onLoadingChange?(false)
        }

        // 2. Fluxo Face ID / Biometria com idL
        if url.contains("app.do") && url.contains("idL=") {
            evaluateBiometrics(for: webView)
        } else if url.contains("app.do") && !url.contains("idL=") {
            if let idL = sessionUseCase.currentSession().idL, !idL.isEmpty {
                webView.stopLoading()
                let separator = url.contains("?") ? "&" : "?"
                if let newURL = URL(string: "\(url)\(separator)\(idL)") {
                    AppLogger.info(.auth, "🔑 Injetando idL de sessão anterior para login biométrico: \(newURL.absoluteString)")
                    webView.load(URLRequest(url: newURL))
                }
            }
        } else if url.contains("idL=") && !url.contains("app.do") {
            let after = url.components(separatedBy: "idL=").last ?? ""
            let idLValue = after.components(separatedBy: "&").first ?? after
            if !idLValue.isEmpty {
                sessionUseCase.save(idL: "idL=\(idLValue)")
            }
        }

        // 3. Detecção de pós-login (novoMenu)
        if url.contains("novoMenu") {
            handlePostLoginNavigation(url: url)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        AppLogger.logFailure(.auth, operation: "LoginWebView.didFail", error: error)
        handleNavigationFailure(in: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        AppLogger.logFailure(.auth, operation: "LoginWebView.didFailProvisionalNavigation", error: error)
        handleNavigationFailure(in: webView, error: error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let urlString = url.absoluteString
        AppLogger.info(.auth, "🔗 [LoginWebView] Navegação solicitada: \(urlString)")

        // Detecção antecipada de sucesso de login
        if urlString.contains("novoMenu") || urlString.contains("idU=") {
            AppLogger.info(.auth, "Login detectado na política de navegação: \(urlString)")
            handlePostLoginNavigation(url: urlString)
        }

        decisionHandler(.allow)
    }

    // MARK: - Tratamento de Falhas e Candidatas

    private func handleNavigationFailure(in webView: WKWebView, error: Error) {
        let nsError = error as NSError
        // Ignora erros de cancelamento normais (ex: quando chamamos webView.load novamente)
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }

        if canTryNextCandidate() {
            AppLogger.warning(.auth, "⚠️ Falha ao carregar candidata: \(nsError.localizedDescription). Tentando próxima opção...")
            tryNextCandidate(in: webView)
        } else {
            onLoadingChange?(false)
            onErrorMessage?("Erro ao conectar (\(nsError.localizedDescription)). Verifique sua conexão à internet.")
        }
    }

    private func canTryNextCandidate() -> Bool {
        (currentCandidateIndex + 1) < candidateURLs.count
    }

    func tryNextCandidate(in webView: WKWebView) {
        guard canTryNextCandidate() else { return }
        currentCandidateIndex += 1
        let nextURL = candidateURLs[currentCandidateIndex]
        AppLogger.info(.auth, "🔄 [LoginWebView] Alternando para URL candidata [\(currentCandidateIndex + 1)/\(candidateURLs.count)]: \(nextURL.absoluteString)")
        let request = URLRequest(url: nextURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        webView.load(request)
    }

    func retry(in webView: WKWebView) {
        onErrorMessage?(nil)
        onLoadingChange?(true)
        let urlToLoad = candidateURLs.indices.contains(currentCandidateIndex) ? candidateURLs[currentCandidateIndex] : candidateURLs.first
        if let url = urlToLoad {
            AppLogger.info(.auth, "🔄 [LoginWebView] Recarregando URL: \(url.absoluteString)")
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        }
    }

    // MARK: - Pós-login

    private func handlePostLoginNavigation(url: String) {
        guard !hasReportedSuccess else { return }

        var extractedIDU: String?
        if url.contains("idU=") {
            let after = url.components(separatedBy: "idU=").last ?? ""
            let rawIDU = after.components(separatedBy: "&").first ?? after
            extractedIDU = rawIDU.removingPercentEncoding ?? rawIDU
        }

        guard let idU = extractedIDU, !idU.isEmpty else { return }

        hasReportedSuccess = true
        sessionUseCase.save(idU: idU)

        let finalCPF = self.capturedCPF ?? sessionUseCase.currentSession().cpf
        let currentIDL = sessionUseCase.currentSession().idL

        AppLogger.logSuccess(
            .auth,
            operation: "LoginWebCoordinator.handlePostLoginNavigation",
            details: "Login detectado com sucesso! idU: '\(idU.prefix(6))...', CPF presente: \(finalCPF != nil)"
        )

        DispatchQueue.main.async {
            self.onLoginSuccess?(finalCPF, idU, currentIDL)
        }
    }

    private func evaluateBiometrics(for webView: WKWebView) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            AppLogger.info(.auth, "Disparando autenticação biométrica (Face ID / Touch ID)...")
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Autentique para entrar no Postos Valle") { success, biometryError in
                if success {
                    AppLogger.logSuccess(.auth, operation: "Biometria", details: "Autenticação biométrica autorizada.")
                    DispatchQueue.main.async {
                        webView.evaluateJavaScript("login()") { _, jsError in
                            if let jsError = jsError {
                                AppLogger.logFailure(.auth, operation: "Biometria.loginJS", error: jsError)
                            }
                        }
                    }
                } else if let bErr = biometryError {
                    AppLogger.logFailure(.auth, operation: "Biometria", error: bErr)
                }
            }
        }
    }

    static let cpfCaptureJavaScript = """
    (function() {
      if (window.__postosValleCpfCaptureInstalled) { return; }
      window.__postosValleCpfCaptureInstalled = true;
      function digits(v){ return String(v||'').replace(/\\D/g,''); }
      function send(v){
        var d = digits(v);
        if (d.length < 10 || d.length > 11) { return; }
        try {
          window.webkit.messageHandlers.cpfCapture.postMessage(d);
        } catch (e) {}
      }
      function scan(){
        try {
          ['login','cpf','NUM_CGCECPF','num_cgcecpf','usuario','user','documento'].forEach(function(k){
            send(window.localStorage.getItem(k));
            send(window.sessionStorage.getItem(k));
          });
        } catch (e) {}
        try {
          var parts = (document.cookie || '').split(';');
          for (var i = 0; i < parts.length; i++) {
            var kv = parts[i].split('=');
            if (kv.length >= 2) send(decodeURIComponent(kv.slice(1).join('=').trim()));
          }
        } catch (e) {}
        try {
          document.querySelectorAll('input').forEach(function(el){ send(el.value); });
        } catch (e) {}
      }
      document.addEventListener('submit', function(){ setTimeout(scan, 0); }, true);
      document.addEventListener('change', function(e){
        if (e && e.target) { send(e.target.value); }
      }, true);
      document.addEventListener('input', function(e){
        if (e && e.target) { send(e.target.value); }
      }, true);
      setTimeout(scan, 300);
      setTimeout(scan, 1000);
    })();
    """
}

// MARK: - WKWebViewRepresentable UIKit Wrapper

struct WKWebViewRepresentable: UIViewRepresentable {
    let url: URL
    let coordinator: LoginWebCoordinator

    func makeCoordinator() -> LoginWebCoordinator {
        coordinator
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true

        let contentController = configuration.userContentController
        contentController.add(context.coordinator, name: "cpfCapture")
        contentController.addUserScript(WKUserScript(
            source: LoginWebCoordinator.cpfCaptureJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = UIColor(PostosValleColors.primaryBlue)
        webView.isOpaque = false
        webView.scrollView.bounces = true

        context.coordinator.activeWebView = webView

        AppLogger.info(.auth, "Iniciando carga de URL no LoginWebView: \(url.absoluteString)")
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: LoginWebCoordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "cpfCapture")
        coordinator.activeWebView = nil
    }
}
