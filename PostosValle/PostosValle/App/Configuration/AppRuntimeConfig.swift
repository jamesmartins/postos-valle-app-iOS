import Foundation

@MainActor
final class AppRuntimeConfig {
    static let shared = AppRuntimeConfig()

    /// Login limpo (`app.do?key=…`) — sem token de logout. Postos Valle não usa intro.
    private(set) var dynamicLoginURL: URL?
    /// Compat: aliases antigos que apontavam para intro.
    var dynamicIntroURL: URL? { dynamicLoginURL }
    /// Chave do app (preferencialmente decodificada, ex: `…¢`).
    private(set) var dynamicAppKey: String?
    /// Chave como veio no APP.do (muitas vezes Base64).
    private(set) var dynamicAppKeyRaw: String?
    private(set) var menuLinks: [String: String] = [:]

    private init() {}

    func update(from links: [String: String]) {
        self.menuLinks = links

        guard let sample = links.first(where: { BunkerURLBuilder.queryValue(named: "key", in: $0.value) != nil }),
              let rawKey = BunkerURLBuilder.queryValue(named: "key", in: sample.value) else {
            AppLogger.warning(.auth, "AppRuntimeConfig: nenhum link com key= encontrado no APP.do")
            return
        }

        dynamicAppKeyRaw = rawKey

        if let decoded = Self.decodeBase64Key(rawKey) {
            dynamicAppKey = decoded
            AppLogger.info(.auth, "🔑 [AppRuntimeConfig] Chave Bunker de '\(sample.key)' decodificada: \(decoded)")
        } else {
            dynamicAppKey = rawKey
            AppLogger.info(.auth, "🔑 [AppRuntimeConfig] Chave Bunker de '\(sample.key)': \(rawKey)")
        }

        // Nunca reutilizar a URL de logout (com t=). Monta login limpo só com a key.
        if let login = Self.makeLoginURL(key: dynamicAppKey ?? rawKey) {
            dynamicLoginURL = login
            AppLogger.info(.auth, "🔗 [AppRuntimeConfig] Login limpo: \(login.absoluteString)")
        }
    }

    /// URLs de login candidatas (`app.do`, limpas, sem token de logout).
    func loginCandidateURLs() -> [URL] {
        var urls: [URL] = []
        var keys: [String] = []

        if let key = dynamicAppKey { keys.append(key) }
        if let raw = dynamicAppKeyRaw { keys.append(raw) }
        keys.append(contentsOf: [
            AppConstants.bunkerAppKey,
            AppConstants.bunkerAppKeyWithoutCent,
            AppConstants.bunkerAppKeyBase64,
            AppConstants.bunkerAppKeyLegacy
        ].filter { !$0.isEmpty })

        var seen = Set<String>()
        for key in keys {
            guard !key.isEmpty, let url = Self.makeLoginURL(key: key) else { continue }
            let id = url.absoluteString
            if seen.insert(id).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    /// Compat com chamadas antigas.
    func introCandidateURLs() -> [URL] {
        loginCandidateURLs()
    }

    /// Monta URL da tela de Login WebView (`app.do?key=`).
    nonisolated static func makeLoginURL(key: String) -> URL? {
        var components = URLComponents(string: "\(AppConstants.bunkerAppHost)/app/app.do")
        components?.queryItems = [URLQueryItem(name: "key", value: key)]
        return components?.url
    }

    /// @available — mantido para HardcodedLinks / cadastro; Postos Valle não abre intro.
    nonisolated static func makeIntroURL(key: String) -> URL? {
        makeLoginURL(key: key)
    }

    private nonisolated static func decodeBase64Key(_ value: String) -> String? {
        var padded = value
        let remainder = padded.count % 4
        if remainder > 0 {
            padded.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: padded),
              let decoded = String(data: data, encoding: .utf8),
              !decoded.isEmpty else {
            return nil
        }
        return decoded
    }
}
