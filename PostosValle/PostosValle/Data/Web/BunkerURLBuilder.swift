import Foundation

enum BunkerURLBuilder {
    /// Caracteres permitidos em query parameters para a Bunker
    private static var queryValueAllowed: CharacterSet {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }

    /// Reconstrói a URL para carregar os cards do menu web
    /// Padrão: <path>?key=<appKey>&idU=<idU>&[extras]&t=<token>
    @MainActor
    static func build(
        from urlString: String,
        appKey: String? = nil,
        idU: String?,
        extra: [(String, String)] = []
    ) -> URL? {
        let effectiveAppKey = appKey ?? AppRuntimeConfig.shared.dynamicAppKey ?? AppConstants.bunkerAppKey
        let base = urlString.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? urlString

        let token = queryValue(named: "t", in: urlString)

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

        if let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
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
            return url
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: ":/?#[]@!$&'()*+,;=")
        return fullURLString.addingPercentEncoding(withAllowedCharacters: allowed).flatMap(URL.init(string:))
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
