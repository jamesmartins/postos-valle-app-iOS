import Foundation

enum BunkerURLBuilder {
    /// Caracteres permitidos em query valores para a Bunker (RFC 3986 unreserved + encoding do resto)
    private static var queryValueAllowed: CharacterSet {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }

    /// Reconstrói a URL para carregar os cards do menu web.
    /// Padrão: `<path>?key=<appKey>&idU=<idU>&[extras]&t=<token>`
    @MainActor
    static func build(
        from urlString: String,
        appKey: String? = nil,
        idU: String?,
        extra: [(String, String)] = [],
        fallbackToken: String? = nil
    ) -> URL? {
        let trimmedSource = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else { return nil }

        let effectiveAppKey = (appKey
            ?? AppRuntimeConfig.shared.dynamicAppKey
            ?? AppConstants.bunkerAppKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !effectiveAppKey.isEmpty else {
            AppLogger.warning(.app, "BunkerURLBuilder: appKey vazia — URL não montada")
            return nil
        }

        let base = trimmedSource
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? trimmedSource

        guard base.hasPrefix("http://") || base.hasPrefix("https://") else {
            AppLogger.warning(.app, "BunkerURLBuilder: base inválida '\(base)'")
            return nil
        }

        let tokenFromURL = queryValue(named: "t", in: trimmedSource)
        let token = (tokenFromURL ?? fallbackToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var pairs: [(String, String)] = [
            ("key", effectiveAppKey)
        ]

        if let idU = idU?.trimmingCharacters(in: .whitespacesAndNewlines), !idU.isEmpty {
            pairs.append(("idU", idU))
        }

        for (name, value) in extra {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pairs.append((name, trimmed))
            }
        }

        if let token, !token.isEmpty {
            pairs.append(("t", token))
        }

        let query = pairs
            .map { name, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
                return "\(name)=\(encoded)"
            }
            .joined(separator: "&")

        let fullURLString = "\(base)?\(query)"

        if let url = URL(string: fullURLString) {
            AppLogger.info(.app, "🔗 BunkerURLBuilder: \(url.absoluteString)")
            return url
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: ":/?#[]@!$&'()*+,;=")
        let encodedFull = fullURLString.addingPercentEncoding(withAllowedCharacters: allowed)
        let url = encodedFull.flatMap(URL.init(string:))
        if let url {
            AppLogger.info(.app, "🔗 BunkerURLBuilder (reencoded): \(url.absoluteString)")
        } else {
            AppLogger.warning(.app, "BunkerURLBuilder: falha ao criar URL a partir de '\(fullURLString)'")
        }
        return url
    }

    /// Extrai um `t=` de qualquer link do APP.do para usar em fallbacks hardcoded.
    static func anyToken(from links: [String: String]) -> String? {
        for (_, value) in links {
            if let token = queryValue(named: "t", in: value), !token.isEmpty {
                return token
            }
        }
        return nil
    }

    static func queryValue(named name: String, in urlString: String) -> String? {
        let marker = "\(name)="
        guard let range = urlString.range(of: marker, options: .caseInsensitive) else {
            return nil
        }
        let after = urlString[range.upperBound...]
        let end = after.firstIndex(of: "&") ?? after.endIndex
        let raw = String(after[..<end])
        return raw.removingPercentEncoding ?? raw
    }
}
