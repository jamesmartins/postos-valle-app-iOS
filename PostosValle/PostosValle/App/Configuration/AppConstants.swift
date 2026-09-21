import Foundation

enum AppConstants {
    /// Host do backend Bunker
    static let bunkerAppHost = "https://adm.bunkerapp.com.br"
    static let bunkerMkHost = "https://adm.bunker.mk"

    /// Chaves candidatas do aplicativo Postos Valle no Bunker.
    /// Preferencialmente preenchidas em runtime via `APP.do` (`AppRuntimeConfig`).
    /// Atualize estes fallbacks se o Bunker fornecer a chave curta de `app.do?key=`.
    static let bunkerAppKey = ""
    static let bunkerAppKeyWithoutCent = ""
    static let bunkerAppKeyBase64 = ""
    static let bunkerAppKeyLegacy = ""

    /// Código da empresa no Bunker para ConsultaCli.
    static let userCompany = "21"

    /// URL padrão de Login WebView (`app.do`). Postos Valle não usa tela de intro.
    static var loginURLString: String {
        if !bunkerAppKey.isEmpty,
           let url = AppRuntimeConfig.makeLoginURL(key: bunkerAppKey)?.absoluteString {
            return url
        }
        return "\(bunkerAppHost)/app/app.do"
    }

    /// Compat: aliases antigos apontavam para intro — agora resolvem para login.
    static var introURLString: String { loginURLString }

    static let appConfigURLString = "\(bunkerAppHost)/wsjson/APP.do"
    static let dadosComprasURLString = "\(bunkerMkHost)/wsjson/dadoscompras.php"
    static let consultaCliURLString = "\(bunkerAppHost)/wsjson/ConsultaCli.do"

    /// URLs de fallback para cards caso o APP.do não forneça
    enum HardcodedLinks {
        static let tokenBase = "\(bunkerAppHost)/app/tipoToken.do"
        /// Token `t=` do tipoToken — confirmar no Bunker se Gerar Token falhar.
        static let tokenT = ""

        static var cadastreseURL: String {
            loginURLString.replacingOccurrences(of: "app.do", with: "cadastro_V2.do")
        }

        static var termosURL: String {
            loginURLString.replacingOccurrences(of: "app.do", with: "termos.do")
        }
    }

    /// Lista ordenada de URLs candidatas para a Login WebView (`app.do?key=`).
    @MainActor
    static func loginCandidateURLs() -> [URL] {
        var urls = AppRuntimeConfig.shared.loginCandidateURLs()

        let keys = [
            AppConstants.bunkerAppKey,
            AppConstants.bunkerAppKeyWithoutCent,
            AppConstants.bunkerAppKeyBase64,
            AppConstants.bunkerAppKeyLegacy
        ].filter { !$0.isEmpty }

        for key in keys {
            guard let url = AppRuntimeConfig.makeLoginURL(key: key),
                  !urls.contains(url) else { continue }
            urls.append(url)
        }

        return urls
    }
}
